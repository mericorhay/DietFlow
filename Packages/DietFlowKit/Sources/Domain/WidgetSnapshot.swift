import Foundation

/// What the person chose on the Widgets tab. Applies to every widget.
public struct WidgetPreferences: Codable, Hashable, Sendable {
    public var showCalories: Bool
    public var showFollowingMeal: Bool
    public var showCompletedMeals: Bool
    public var energyUnit: EnergyUnit

    public init(showCalories: Bool = false, showFollowingMeal: Bool = true, showCompletedMeals: Bool = true, energyUnit: EnergyUnit = .kilocalories) {
        self.showCalories = showCalories
        self.showFollowingMeal = showFollowingMeal
        self.showCompletedMeals = showCompletedMeals
        self.energyUnit = energyUnit
    }

    // Tolerant decoding: a field added later must not make an older file unreadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WidgetPreferences()
        showCalories = try container.decodeIfPresent(Bool.self, forKey: .showCalories) ?? defaults.showCalories
        showFollowingMeal = try container.decodeIfPresent(Bool.self, forKey: .showFollowingMeal) ?? defaults.showFollowingMeal
        showCompletedMeals = try container.decodeIfPresent(Bool.self, forKey: .showCompletedMeals) ?? defaults.showCompletedMeals
        energyUnit = (try? container.decodeIfPresent(EnergyUnit.self, forKey: .energyUnit)) ?? defaults.energyUnit
    }
}

/// Everything a widget needs, written by the app whenever the plan, a meal's state or a widget
/// preference changes. The widget never opens the database: it reads this one small file and
/// works out each moment of the day from it.
///
/// It carries the plan itself (trimmed to what is drawn) rather than a list of upcoming meals, so
/// the widget keeps moving from meal to meal and day to day for as long as the plan runs, even if
/// the app is not opened for weeks.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    /// Recorded states are kept for this window around the day the snapshot is written.
    public static let stateWindow = -2...14

    public var version: Int
    public var generatedAt: Date
    /// Nil when there is no active plan.
    public var plan: MealPlan?
    /// Occurrence key → state, for the days in `stateWindow`. Missing means pending.
    public var states: [String: OccurrenceState]
    public var preferences: WidgetPreferences

    public init(plan: MealPlan?, states: OccurrenceStates, preferences: WidgetPreferences, generatedAt: Date = .now, timeZone: TimeZone = .current) {
        let today = CalendarDay(generatedAt, in: timeZone)
        let first = today.adding(days: Self.stateWindow.lowerBound)
        let last = today.adding(days: Self.stateWindow.upperBound)
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.plan = plan?.trimmedForWidget()
        self.states = Dictionary(
            states
                .filter { $0.value != .pending && $0.key.day >= first && $0.key.day <= last }
                .map { ($0.key.description, $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
        self.preferences = preferences
    }

    public var occurrenceStates: OccurrenceStates {
        var result: OccurrenceStates = [:]
        for (text, state) in states {
            if let key = OccurrenceKey(text) { result[key] = state }
        }
        return result
    }

    /// A snapshot written by a newer version of the app may mean something this one cannot read.
    public var isReadable: Bool {
        version <= Self.currentVersion
    }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

extension WidgetSnapshot {
    /// The sample plan on its first day, with the meals already past marked done: what the
    /// widget gallery and previews show before a real plan exists.
    public static func sample(now: Date = .now, timeZone: TimeZone = .current, preferences: WidgetPreferences = WidgetPreferences()) -> WidgetSnapshot {
        let today = CalendarDay(now, in: timeZone)
        let plan = SamplePlan.keto(startingOn: today)
        let schedule = MealSchedule(plan: plan, timeZone: timeZone)
        var states: OccurrenceStates = [:]
        for occurrence in schedule.occurrences(on: today) where occurrence.date.addingTimeInterval(MealSchedule.currentWindow) < now {
            states[occurrence.key] = .completed
        }
        return WidgetSnapshot(plan: plan, states: states, preferences: preferences, generatedAt: now, timeZone: timeZone)
    }
}
