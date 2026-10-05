import Foundation
import Observation
import OSLog
import WidgetKit
import Domain
import MealReminders
import Persistence

public enum MealPlanStoreError: Error, Sendable {
    case noActivePlan
    case mealNotFound
    /// A meal with no name: there would be nothing to show for it.
    case mealHasNoTitle
    /// The plan already holds as many meals as a plan can.
    case planIsFull
}

/// A change the person asked for that could not be stored.
public struct StoreFailure: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public init() {}
}

/// The one place plans change, whoever changes them: a screen, a Shortcut, the widget's Done
/// button, an import, or later an MCP bridge. Each operation stores the change, then brings the
/// widget and the reminders along, so nothing that shows the plan can fall behind it.
///
/// The operations are named for what they do to the plan (`createPlan`, `addMeal`,
/// `markMealCompleted`, `getPlanForDate` …) rather than for a screen, so an agent can be handed the
/// same verbs a person uses.
@MainActor
@Observable
public final class MealPlanStore {
    public private(set) var plans: [PlanSummary] = []
    public private(set) var activePlan: MealPlan?
    /// The active plan as a schedule, in the current time zone.
    public private(set) var schedule: MealSchedule?
    /// What happened to the active plan's meals, by occurrence.
    public private(set) var states: OccurrenceStates = [:]
    public private(set) var settings: AppSettings
    /// Changes with every stored change, for views that animate on it.
    public private(set) var revision = 0
    /// Set when a change asked for by a screen could not be stored, so the app can say so.
    public private(set) var failure: StoreFailure?

    @ObservationIgnored private let persistence: PlanStore
    /// Off for previews and seeded test states, which must neither read nor change the person's
    /// real settings.
    @ObservationIgnored private let persistsSettings: Bool
    @ObservationIgnored private let snapshotWriter: WidgetSnapshotWriter?
    @ObservationIgnored private let reminders: MealReminderScheduler
    @ObservationIgnored private let reloadWidgets: @MainActor () -> Void
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.orhay.dietflow", category: "MealPlanStore")

    public init(
        persistence: PlanStore,
        snapshotWriter: WidgetSnapshotWriter?,
        reminders: MealReminderScheduler = MealReminderScheduler(),
        settings: AppSettings,
        persistsSettings: Bool = true,
        reloadWidgets: @escaping @MainActor () -> Void
    ) {
        self.persistence = persistence
        self.persistsSettings = persistsSettings
        self.snapshotWriter = snapshotWriter
        self.reminders = reminders
        self.settings = settings
        self.reloadWidgets = reloadWidgets
        load()
    }

    /// The store the app and the intents use: the shared database, the shared snapshot, real
    /// widget reloads and real notifications.
    public static func live() -> MealPlanStore {
        MealPlanStore(
            persistence: PlanStore(container: PlanStore.makeContainer()),
            snapshotWriter: WidgetSnapshotWriter.shared(),
            settings: AppSettingsStore.load(),
            reloadWidgets: { WidgetCenter.shared.reloadAllTimelines() }
        )
    }

    /// An in-memory store for previews and seeded test states, optionally holding the sample plan.
    /// It never touches the shared database, the widget or the person's settings.
    public static func preview(withSample: Bool = true, settings: AppSettings = AppSettings(hasCompletedOnboarding: true)) -> MealPlanStore {
        let store = MealPlanStore(
            persistence: PlanStore(container: PlanStore.makeContainer(inMemory: true)),
            snapshotWriter: nil,
            settings: settings,
            persistsSettings: false,
            reloadWidgets: {}
        )
        if withSample {
            _ = try? store.createPlan(SamplePlan.keto(startingOn: .today()))
        }
        return store
    }

    // MARK: - Asking for a change

    /// Runs a change a screen asked for. If it cannot be stored, the error is logged and
    /// `failure` is set, so the person hears about it instead of the change quietly not happening.
    @discardableResult
    public func attempt<Value>(_ change: () throws -> Value) -> Value? {
        do {
            return try change()
        } catch {
            logger.error("A change could not be stored: \(String(describing: error), privacy: .public)")
            failure = StoreFailure()
            return nil
        }
    }

    /// The person has been told about `failure`.
    public func clearFailure() {
        failure = nil
    }

    // MARK: - Reading

    public var hasPlans: Bool { !plans.isEmpty }

    /// One day's meals and where each stands at `now`.
    public func agenda(on day: CalendarDay, now: Date = .now) -> DayAgenda? {
        schedule?.agenda(on: day, states: states, now: now)
    }

    /// The meal to put in front of the person at `now`.
    public func focus(now: Date = .now) -> MealFocus? {
        schedule?.focus(states: states, now: now)
    }

    public func occurrence(for key: OccurrenceKey) -> MealOccurrence? {
        schedule?.occurrence(for: key, states: states)
    }

    public func meal(id: UUID) -> Meal? {
        activePlan?.meals.first { $0.id == id }
    }

    public func getActivePlan() -> MealPlan? {
        activePlan
    }

    /// The active plan's meals on `day`, each with its state and role at `now`.
    public func getPlanForDate(_ day: CalendarDay, now: Date = .now) -> DayAgenda? {
        agenda(on: day, now: now)
    }

    // MARK: - Plans

    /// Stores a new plan; by default it becomes the active plan.
    @discardableResult
    public func createPlan(_ plan: MealPlan, activate: Bool = true) throws -> MealPlan {
        // Screens, imports, Shortcuts and later an MCP bridge all arrive here, so this is where
        // what they hand over is bounded — not in each of them.
        let plan = plan.sanitized()
        try persistence.insert(plan, activate: activate || plans.isEmpty)
        didChange("createPlan")
        return plan
    }

    /// Replaces a plan's name, schedule and meals. Meals that keep their id keep their history.
    public func replacePlan(_ plan: MealPlan) throws {
        try persistence.replace(plan.sanitized())
        didChange("replacePlan")
    }

    public func activatePlan(id: UUID) throws {
        try persistence.activate(planID: id)
        didChange("activatePlan")
    }

    public func deletePlan(id: UUID) throws {
        try persistence.deletePlan(id: id)
        didChange("deletePlan")
    }

    // MARK: - Meals

    /// Adds a meal to the active plan, or to `planID`.
    @discardableResult
    public func addMeal(_ meal: Meal, toPlan planID: UUID? = nil) throws -> Meal {
        guard let target = planID ?? activePlan?.id else { throw MealPlanStoreError.noActivePlan }
        guard let meal = meal.sanitized() else { throw MealPlanStoreError.mealHasNoTitle }
        if let plan = activePlan, plan.id == target, plan.meals.count >= PlanLimits.mealsPerPlan, !plan.meals.contains(where: { $0.id == meal.id }) {
            throw MealPlanStoreError.planIsFull
        }
        try persistence.upsert(meal, planID: target)
        didChange("addMeal")
        return meal
    }

    public func updateMeal(_ meal: Meal, inPlan planID: UUID? = nil) throws {
        guard let target = planID ?? activePlan?.id else { throw MealPlanStoreError.noActivePlan }
        guard let meal = meal.sanitized() else { throw MealPlanStoreError.mealHasNoTitle }
        try persistence.upsert(meal, planID: target)
        didChange("updateMeal")
    }

    public func deleteMeal(id: UUID) throws {
        try persistence.deleteMeal(id: id)
        didChange("deleteMeal")
    }

    // MARK: - What happened

    public func markMealCompleted(_ key: OccurrenceKey) throws {
        try setState(.completed, for: key)
    }

    public func markMealSkipped(_ key: OccurrenceKey) throws {
        try setState(.skipped, for: key)
    }

    /// Back to not marked.
    public func clearMealState(_ key: OccurrenceKey) throws {
        try setState(.pending, for: key)
    }

    public func setState(_ state: OccurrenceState, for key: OccurrenceKey) throws {
        guard let plan = activePlan else { throw MealPlanStoreError.noActivePlan }
        // A reminder or a link can outlive the meal it names. Recording a state for a meal the
        // plan no longer has would leave a row nothing ever reads or removes.
        guard plan.meals.contains(where: { $0.id == key.mealID }) else { throw MealPlanStoreError.mealNotFound }
        try persistence.setState(state, for: key, planID: plan.id)
        didChange("setState")
    }

    // MARK: - Settings

    public func updateSettings(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
        if persistsSettings { AppSettingsStore.save(updated) }
        publish()
    }

    /// Turns reminders on, asking for notification permission the first time. False when the
    /// person declines, in which case reminders stay off.
    public func enableReminders() async -> Bool {
        switch await reminders.authorization() {
        case .denied:
            return false
        case .notDetermined:
            guard await reminders.requestAuthorization() else { return false }
        case .allowed:
            break
        }
        updateSettings { $0.remindersEnabled = true }
        return true
    }

    public func reminderAuthorization() async -> ReminderAuthorization {
        await reminders.authorization()
    }

    /// True when the person has turned this app's notifications off in the Settings app.
    public func areNotificationsDenied() async -> Bool {
        await reminders.authorization() == .denied
    }

    // MARK: - Data

    /// Adds the sample plan, starting today, and makes it the active plan. For trying the app
    /// before writing a plan of one's own; nothing else is touched.
    @discardableResult
    public func addSamplePlan() throws -> MealPlan {
        try createPlan(SamplePlan.keto(startingOn: .today()), activate: true)
    }

    /// Whether any of this app's widgets is on a Home Screen or the Lock Screen.
    public func isWidgetOnScreen() async -> Bool {
        await withCheckedContinuation { continuation in
            // WidgetKit may answer on any queue: the callback must not assume the main actor.
            WidgetCenter.shared.getCurrentConfigurations { @Sendable result in
                let count = (try? result.get())?.count ?? 0
                continuation.resume(returning: count > 0)
            }
        }
    }

    /// Replaces everything with the sample plan, starting today.
    public func resetSampleData() throws {
        try persistence.deleteAll()
        try persistence.insert(SamplePlan.keto(startingOn: .today()), activate: true)
        didChange("resetSampleData")
    }

    /// Re-reads the store — the widget's Done button may have written to it from its own process —
    /// and brings the widget and reminders up to date. Called when the app comes to the front and
    /// when the clock, the day or the time zone changes.
    public func refresh() {
        load()
        publish()
    }

    // MARK: - Effects

    private func load() {
        do {
            plans = try persistence.planSummaries()
            let plan = try persistence.activePlan()
            activePlan = plan
            schedule = plan.map { MealSchedule(plan: $0, timeZone: .current) }
            states = try plan.map { try persistence.states(planID: $0.id) } ?? [:]
        } catch {
            logger.error("Could not read plans: \(String(describing: error), privacy: .public)")
        }
        if persistsSettings { settings = AppSettingsStore.load() }
    }

    private func didChange(_ operation: String) {
        load()
        revision += 1
        logger.info("\(operation, privacy: .public)")
        publish()
    }

    /// Writes the widget snapshot, asks WidgetKit to reload, and reschedules reminders.
    private func publish(now: Date = .now) {
        if let snapshotWriter {
            let snapshot = WidgetSnapshot(plan: activePlan, states: states, preferences: settings.widgetPreferences, generatedAt: now)
            do {
                try snapshotWriter.write(snapshot)
            } catch {
                logger.error("Could not write the widget snapshot: \(String(describing: error), privacy: .public)")
            }
        }
        reloadWidgets()

        let requests = settings.remindersEnabled
            ? ReminderPlanner.requests(plan: activePlan, states: states, defaultOffset: settings.defaultReminder, now: now)
            : []
        // One reschedule at a time, newest last. Run side by side, an older one could still be
        // adding reminders after a newer one had cleared them, and bring back the reminder for a
        // meal that was just marked done.
        let reminders = self.reminders
        let previous = reminderTask
        previous?.cancel()
        reminderTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await reminders.reschedule(requests)
        }
    }
}
