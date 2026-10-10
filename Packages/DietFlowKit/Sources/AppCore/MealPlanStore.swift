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
    /// Days of the active plan that started late, and where their first meal went. Empty while
    /// smart meal times are off.
    public private(set) var dayStarts: DayStarts = [:]
    public private(set) var settings: AppSettings
    /// Changes with every stored change, for views that animate on it.
    public private(set) var revision = 0
    /// Set when a change asked for by a screen could not be stored, so the app can say so.
    public private(set) var failure: StoreFailure?

    @ObservationIgnored private let persistence: PlanStore
    @ObservationIgnored private let dayStartStore: DayStartStore
    /// Off for previews and seeded test states, which must neither read nor change the person's
    /// real settings.
    @ObservationIgnored private let persistsSettings: Bool
    @ObservationIgnored private let snapshotWriter: WidgetSnapshotWriter?
    @ObservationIgnored private let reminders: MealReminderScheduler
    @ObservationIgnored private let reloadWidgets: @MainActor () -> Void
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    /// False in the widget's process, where the full reschedule is left to the app (see `publish`).
    @ObservationIgnored private let reschedulesReminders: Bool
    /// The last read of the store failed, so what is in memory may not be what is on disk.
    @ObservationIgnored private var lastLoadFailed = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.orhay.dietflow", category: "MealPlanStore")

    public init(
        persistence: PlanStore,
        dayStartStore: DayStartStore = DayStartStore(),
        snapshotWriter: WidgetSnapshotWriter?,
        reminders: MealReminderScheduler = MealReminderScheduler(),
        settings: AppSettings,
        persistsSettings: Bool = true,
        reschedulesReminders: Bool = true,
        reloadWidgets: @escaping @MainActor () -> Void
    ) {
        self.persistence = persistence
        self.dayStartStore = dayStartStore
        self.reschedulesReminders = reschedulesReminders
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
            // The widget's Done button runs this in the widget extension.
            reschedulesReminders: !Bundle.main.bundlePath.hasSuffix(".appex"),
            reloadWidgets: { WidgetCenter.shared.reloadAllTimelines() }
        )
    }

    /// An in-memory store for previews and seeded test states, optionally holding the sample plan.
    /// It never touches the shared database, the widget or the person's settings.
    public static func preview(withSample: Bool = true, settings: AppSettings = AppSettings(hasCompletedOnboarding: true)) -> MealPlanStore {
        let store = MealPlanStore(
            persistence: PlanStore(container: PlanStore.makeContainer(inMemory: true)),
            dayStartStore: DayStartStore(inMemory: true),
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

    /// Where `day` started, when it started late.
    public func dayStart(on day: CalendarDay) -> DayStart? {
        dayStarts[day]
    }

    /// How many minutes later than planned `day`'s meals are: 0 when it follows the plan.
    public func delay(on day: CalendarDay) -> Int {
        schedule?.delay(on: day) ?? 0
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

    /// Puts `plan` in the place of the active plan: the new one is saved and made active, then the
    /// old one is deleted with what happened to its meals. What the free tier offers instead of
    /// keeping a second plan. Without an active plan it is `createPlan`.
    @discardableResult
    public func replaceActivePlan(with plan: MealPlan) throws -> MealPlan {
        let previous = activePlan?.id
        let plan = plan.sanitized()
        try persistence.insert(plan, activate: true)
        do {
            if let previous, previous != plan.id {
                try persistence.deletePlan(id: previous)
                dayStartStore.removePlan(previous)
            }
        } catch {
            // The new plan is in and active; the old one stays beside it rather than nothing changing.
            didChange("replaceActivePlan")
            throw error
        }
        didChange("replaceActivePlan")
        return plan
    }

    public func activatePlan(id: UUID) throws {
        try persistence.activate(planID: id)
        didChange("activatePlan")
    }

    public func deletePlan(id: UUID) throws {
        try persistence.deletePlan(id: id)
        dayStartStore.removePlan(id)
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

    /// Fills in the assistant's estimates for meals of the active plan that have no nutrition of
    /// their own, in one change. Meals that were edited meanwhile to have figures, or deleted, are
    /// left alone; what the plan or the person wrote is never overwritten.
    /// Returns how many meals were filled in.
    @discardableResult
    public func applyNutritionEstimates(_ estimates: [UUID: NutritionEstimate]) throws -> Int {
        guard var plan = activePlan else { throw MealPlanStoreError.noActivePlan }
        var filled = 0
        plan.meals = plan.meals.map { meal in
            guard let estimate = estimates[meal.id], meal.lacksNutrition else { return meal }
            filled += 1
            return meal.filling(estimate)
        }
        guard filled > 0 else { return 0 }
        try persistence.replace(plan.sanitized())
        didChange("applyNutritionEstimates")
        return filled
    }

    /// The active plan's meals that have no nutrition of their own, one per dish: what an estimate
    /// for the whole plan would be asked about.
    public func mealsNeedingEstimates() -> [Meal] {
        var seen = Set<String>()
        return (activePlan?.meals ?? [])
            .filter(\.lacksNutrition)
            .sorted { ($0.dayIndex, $0.time) < ($1.dayIndex, $1.time) }
            .filter { seen.insert($0.dishKey).inserted }
    }

    // MARK: - Late starts

    /// `day` started late: its meals move after `start.firstMeal` (`DayShift`). Today by default.
    public func startDay(_ start: DayStart, on day: CalendarDay = .today()) throws {
        guard let plan = activePlan else { throw MealPlanStoreError.noActivePlan }
        dayStartStore.set(start, on: day, planID: plan.id)
        didChange("startDay")
        moveRemindersInThisProcess()
    }

    /// `day` follows the plan again.
    public func clearDayStart(on day: CalendarDay = .today()) throws {
        guard let plan = activePlan else { throw MealPlanStoreError.noActivePlan }
        dayStartStore.set(nil, on: day, planID: plan.id)
        didChange("clearDayStart")
        moveRemindersInThisProcess()
    }

    /// How late the first meal has to be marked eaten for the rest of the day to follow it, and how
    /// late is more likely "marked afterwards" than "eaten then".
    static let inferredLateness: ClosedRange<TimeInterval> = (45 * 60)...(4 * 3600)

    /// The day's first meal was just marked eaten well after its time: unless the person already said
    /// when the day started, it started then, and the rest of the day follows (`DayStart.Source
    /// .firstMeal`). Marking it again as not eaten takes that back.
    private func followFirstMeal(_ state: OccurrenceState, for key: OccurrenceKey, planID: UUID, now: Date) {
        let today = CalendarDay.today(now: now)
        guard settings.smartMealTimes, key.day == today, let schedule else { return }
        let recorded = dayStartStore.starts(planID: planID)[today]
        if state == .pending {
            if recorded?.source == .firstMeal, schedule.meals(on: today).first?.id == key.mealID {
                dayStartStore.set(nil, on: today, planID: planID)
            }
            return
        }
        guard state == .completed, recorded == nil,
              let first = schedule.occurrences(on: today).first, first.meal.id == key.mealID,
              Self.inferredLateness.contains(now.timeIntervalSince(first.date))
        else { return }
        dayStartStore.set(DayStart(firstMeal: TimeOfDay(now), source: .firstMeal), on: today, planID: planID)
    }

    /// In the widget's process the reminders are not rescheduled on every change (see `publish`),
    /// but a day whose meals just moved would otherwise be reminded at the old times, or, with its
    /// reminders taken back, not at all. So that one change reschedules them here too; callers
    /// await `remindersSettled()`. If this process may not add notifications, the old ones stay.
    private func moveRemindersInThisProcess() {
        // As in `publish`: what an unreadable store shows is no reason to touch the reminders.
        guard !reschedulesReminders, !persistence.isTemporary, !lastLoadFailed else { return }
        scheduleReminders(now: .now)
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
        try setState(state, for: key, now: .now)
    }

    func setState(_ state: OccurrenceState, for key: OccurrenceKey, now: Date) throws {
        guard let plan = activePlan else { throw MealPlanStoreError.noActivePlan }
        // A reminder or a link can outlive the meal it names. Recording a state for a meal the
        // plan no longer has would leave a row nothing ever reads or removes.
        guard plan.meals.contains(where: { $0.id == key.mealID }) else { throw MealPlanStoreError.mealNotFound }
        try persistence.setState(state, for: key, planID: plan.id)
        // At once and in this process: a meal marked done must not then be announced.
        if state != .pending { reminders.cancelReminder(for: key) }
        let startedBefore = dayStarts[key.day]
        followFirstMeal(state, for: key, planID: plan.id, now: now)
        didChange("setState")
        if dayStarts[key.day] != startedBefore { moveRemindersInThisProcess() }
    }

    // MARK: - Settings

    public func updateSettings(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
        if persistsSettings { AppSettingsStore.save(updated) }
        dayStarts = effectiveDayStarts(for: activePlan)
        schedule = activePlan.map(makeSchedule)
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

    /// Waits until the reminders asked for by the last change are scheduled. A notification button
    /// that changes the plan awaits this, because the app may be suspended as soon as it returns.
    public func remindersSettled() async {
        await reminderTask?.value
    }

    /// True when the person has turned this app's notifications off in the Settings app.
    public func areNotificationsDenied() async -> Bool {
        await reminders.authorization() == .denied
    }

    // MARK: - Data

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

    /// Deletes every plan and everything recorded against them. Settings are kept. The widget and
    /// the reminders follow at once: the widget shows that there is no plan, and no reminder stays
    /// scheduled for a meal that no longer exists.
    public func deleteAllData() throws {
        try persistence.deleteAll()
        dayStartStore.removeAll()
        didChange("deleteAllData")
    }

    /// Re-reads the store — the widget's Done button may have written to it from its own process —
    /// and brings the widget and reminders up to date. Called when the app comes to the front and
    /// when the clock, the day or the time zone changes.
    public func refresh() {
        load()
        publish()
    }

    // MARK: - Effects

    /// The schedule Today and the intents ask, with the same "how long a meal stays in front" the
    /// widget uses, so the app and the widget never disagree about which meal is on now.
    private func makeSchedule(_ plan: MealPlan) -> MealSchedule {
        MealSchedule(plan: plan, timeZone: .current, currentWindow: settings.widgetPreferences.mealWindow, dayStarts: dayStarts)
    }

    /// The late starts recorded for `plan`, or none while smart meal times are off: then every day
    /// follows the plan, and the recorded ones come back if they are switched on again.
    private func effectiveDayStarts(for plan: MealPlan?) -> DayStarts {
        guard settings.smartMealTimes, let plan else { return [:] }
        return dayStartStore.starts(planID: plan.id)
    }

    private func load() {
        // Settings first: the schedule below is built from them.
        if persistsSettings { settings = AppSettingsStore.load() }
        do {
            plans = try persistence.planSummaries()
            let plan = try persistence.activePlan()
            activePlan = plan
            dayStarts = effectiveDayStarts(for: plan)
            schedule = plan.map(makeSchedule)
            states = try plan.map { try persistence.states(planID: $0.id) } ?? [:]
            lastLoadFailed = false
        } catch {
            lastLoadFailed = true
            logger.error("Could not read plans: \(String(describing: error), privacy: .public)")
        }
    }

    private func didChange(_ operation: String) {
        load()
        revision += 1
        logger.info("\(operation, privacy: .public)")
        publish()
    }

    /// Writes the widget snapshot, asks WidgetKit to reload, and reschedules reminders.
    private func publish(now: Date = .now) {
        // The store on disk could not be opened or read, so this process is looking at nothing, or
        // at something stale. Telling the widget "no plan" and clearing the reminders on that
        // evidence would wipe what the person still has; leave both as they last were.
        if snapshotWriter != nil, persistence.isTemporary || lastLoadFailed {
            logger.error("Not publishing: the plan store could not be read")
            return
        }
        if let snapshotWriter {
            let snapshot = WidgetSnapshot(plan: activePlan, states: states, preferences: settings.widgetPreferences, generatedAt: now, dayStarts: dayStarts)
            do {
                try snapshotWriter.write(snapshot)
            } catch {
                logger.error("Could not write the widget snapshot: \(String(describing: error), privacy: .public)")
            }
        }
        reloadWidgets()

        // The widget extension is suspended as soon as its button's work returns, and may not be
        // allowed what the app is. It only cancels the one reminder it made redundant (`setState`),
        // or moves a day's that just moved (`moveRemindersInThisProcess`); the app brings the rest
        // up to date the next time it comes forward.
        guard reschedulesReminders else { return }
        scheduleReminders(now: now)
    }

    private func scheduleReminders(now: Date) {
        let requests = settings.remindersEnabled
            ? ReminderPlanner.requests(plan: activePlan, states: states, defaultOffset: settings.defaultReminder, now: now, dayStarts: dayStarts)
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
