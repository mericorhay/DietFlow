import Foundation
import OSLog
import SwiftData
import Domain

public enum AppGroup {
    /// Must match the App Group in DietFlow.entitlements and DietFlowWidget.entitlements.
    public static let identifier = "group.com.orhay.dietflow"

    /// Nil when the App Group is not provisioned for this build (an unsigned simulator build).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// The SwiftData store: every plan, its meals and what happened to them. It lives in the App Group
/// container so the widget's Done button, which runs in the widget's process, writes to the same
/// store the app reads.
///
/// Every call works in a fresh `ModelContext`, so a change written by the other process is never
/// hidden behind objects this one cached earlier.
@MainActor
public final class PlanStore {
    public let container: ModelContainer
    private let logger = Logger(subsystem: "com.orhay.dietflow", category: "PlanStore")

    public init(container: ModelContainer) {
        self.container = container
    }

    /// True when the store lives in memory only: a preview, or the stand-in used when the store
    /// on disk could not be opened. What it holds says nothing about what the person has saved.
    public var isTemporary: Bool {
        container.configurations.contains { $0.isStoredInMemoryOnly }
    }

    /// The shared on-disk store, or an in-memory one when the disk store cannot be opened, so the
    /// app always starts. The failure is logged; nothing is silently deleted.
    public static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([MealPlanRecord.self, MealRecord.self, MealCompletionRecord.self])
        let logger = Logger(subsystem: "com.orhay.dietflow", category: "PlanStore")
        if !inMemory {
            let group: ModelConfiguration.GroupContainer = AppGroup.containerURL == nil ? .none : .identifier(AppGroup.identifier)
            let configuration = ModelConfiguration("MealPlans", schema: schema, isStoredInMemoryOnly: false, allowsSave: true, groupContainer: group, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                logger.error("Could not open the plan store: \(String(describing: error), privacy: .public)")
            }
        }
        let memory = ModelConfiguration("MealPlansInMemory", schema: schema, isStoredInMemoryOnly: true, allowsSave: true, groupContainer: .none, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            fatalError("An in-memory store cannot fail to open: \(error)")
        }
    }

    private func context() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    // MARK: Reading

    public func planSummaries() throws -> [PlanSummary] {
        let records = try context().fetch(FetchDescriptor<MealPlanRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        return records.map { record in
            PlanSummary(
                id: record.id,
                name: record.name,
                schedule: PlanSchedule(kind: PlanKind(rawValue: record.kindRaw) ?? .cycle, startDay: CalendarDay(record.startDay) ?? .today(), length: record.length, repeats: record.repeats),
                isActive: record.isActive,
                mealCount: record.meals.filter { $0.dayIndex < record.length }.count,
                updatedAt: record.updatedAt
            )
        }
    }

    public func activePlan() throws -> MealPlan? {
        var descriptor = FetchDescriptor<MealPlanRecord>(predicate: #Predicate { $0.isActive }, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context().fetch(descriptor).first?.value()
    }

    public func plan(id: UUID) throws -> MealPlan? {
        try planRecord(id: id, in: context())?.value()
    }

    /// Recorded states for a plan. Pending occurrences have no record.
    public func states(planID: UUID) throws -> OccurrenceStates {
        let descriptor = FetchDescriptor<MealCompletionRecord>(predicate: #Predicate { $0.planID == planID })
        var states: OccurrenceStates = [:]
        for record in try context().fetch(descriptor) {
            guard let key = OccurrenceKey(record.key), let state = OccurrenceState(rawValue: record.stateRaw) else { continue }
            states[key] = state
        }
        return states
    }

    // MARK: Writing

    /// Stores a new plan. With `activate`, every other plan stops being active.
    public func insert(_ plan: MealPlan, activate: Bool, now: Date = .now) throws {
        let context = context()
        if activate { try deactivateAll(in: context) }
        let record = MealPlanRecord(
            id: plan.id,
            name: plan.name,
            kindRaw: plan.schedule.kind.rawValue,
            startDay: plan.schedule.startDay.description,
            length: plan.schedule.length,
            repeats: plan.schedule.repeats,
            isActive: activate,
            createdAt: now,
            updatedAt: now
        )
        context.insert(record)
        for meal in plan.meals {
            let mealRecord = MealRecord(meal)
            context.insert(mealRecord)
            mealRecord.plan = record
        }
        try context.save()
        logger.info("Stored plan with \(plan.meals.count) meals")
    }

    /// Replaces a stored plan's name, schedule and meals with `plan`'s. Meals keep their identity,
    /// so what was done on past days stays recorded.
    public func replace(_ plan: MealPlan, now: Date = .now) throws {
        let context = context()
        guard let record = try planRecord(id: plan.id, in: context) else {
            throw PlanStoreError.planNotFound
        }
        record.apply(plan, now: now)

        let incoming = Dictionary(plan.meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for mealRecord in record.meals {
            if let meal = incoming[mealRecord.id] {
                mealRecord.apply(meal)
            } else {
                try deleteCompletions(mealID: mealRecord.id, in: context)
                context.delete(mealRecord)
            }
        }
        let existing = Set(record.meals.map(\.id))
        for meal in plan.meals where !existing.contains(meal.id) {
            let mealRecord = MealRecord(meal)
            context.insert(mealRecord)
            mealRecord.plan = record
        }
        try context.save()
    }

    public func activate(planID: UUID, now: Date = .now) throws {
        let context = context()
        guard let record = try planRecord(id: planID, in: context) else { throw PlanStoreError.planNotFound }
        try deactivateAll(in: context)
        record.isActive = true
        record.updatedAt = now
        try context.save()
    }

    /// Deletes a plan, its meals and their recorded states. If it was the active plan, the most
    /// recently changed remaining plan becomes active.
    public func deletePlan(id: UUID) throws {
        let context = context()
        guard let record = try planRecord(id: id, in: context) else { return }
        let wasActive = record.isActive
        for completion in try context.fetch(FetchDescriptor<MealCompletionRecord>(predicate: #Predicate { $0.planID == id })) {
            context.delete(completion)
        }
        context.delete(record)
        if wasActive {
            var descriptor = FetchDescriptor<MealPlanRecord>(predicate: #Predicate { $0.id != id }, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            descriptor.fetchLimit = 1
            try context.fetch(descriptor).first?.isActive = true
        }
        try context.save()
    }

    /// Adds `meal` to the plan, or updates it if the plan already has a meal with its id.
    public func upsert(_ meal: Meal, planID: UUID, now: Date = .now) throws {
        let context = context()
        guard let plan = try planRecord(id: planID, in: context) else { throw PlanStoreError.planNotFound }
        if let existing = plan.meals.first(where: { $0.id == meal.id }) {
            existing.apply(meal)
        } else {
            let record = MealRecord(meal)
            context.insert(record)
            record.plan = plan
        }
        plan.updatedAt = now
        try context.save()
    }

    public func deleteMeal(id: UUID, now: Date = .now) throws {
        let context = context()
        let descriptor = FetchDescriptor<MealRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        record.plan?.updatedAt = now
        try deleteCompletions(mealID: id, in: context)
        context.delete(record)
        try context.save()
    }

    /// Records what happened to one meal on one day. `.pending` removes the record.
    public func setState(_ state: OccurrenceState, for key: OccurrenceKey, planID: UUID, now: Date = .now) throws {
        let context = context()
        let text = key.description
        let existing = try context.fetch(FetchDescriptor<MealCompletionRecord>(predicate: #Predicate { $0.key == text })).first
        switch (state, existing) {
        case (.pending, let record?):
            context.delete(record)
        case (.pending, nil):
            return
        case (_, let record?):
            record.stateRaw = state.rawValue
            record.updatedAt = now
        case (_, nil):
            context.insert(MealCompletionRecord(key: text, mealID: key.mealID, planID: planID, occurrenceDay: key.day.description, stateRaw: state.rawValue, updatedAt: now))
        }
        try context.save()
    }

    /// Deletes every plan, meal and recorded state. Used by "Delete All Data".
    public func deleteAll() throws {
        let context = context()
        try context.delete(model: MealCompletionRecord.self)
        try context.delete(model: MealRecord.self)
        try context.delete(model: MealPlanRecord.self)
        try context.save()
    }

    // MARK: Helpers

    private func planRecord(id: UUID, in context: ModelContext) throws -> MealPlanRecord? {
        var descriptor = FetchDescriptor<MealPlanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func deactivateAll(in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<MealPlanRecord>(predicate: #Predicate { $0.isActive })) {
            record.isActive = false
        }
    }

    private func deleteCompletions(mealID: UUID, in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<MealCompletionRecord>(predicate: #Predicate { $0.mealID == mealID })) {
            context.delete(record)
        }
    }
}

public enum PlanStoreError: Error, Sendable {
    case planNotFound
}
