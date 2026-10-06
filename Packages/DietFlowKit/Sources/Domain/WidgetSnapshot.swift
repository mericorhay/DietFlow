import Foundation

/// The colour a widget's accents, or its whole background, are drawn in. The raw values are
/// stored, so they never change; what each looks like is decided where it is drawn.
public enum WidgetAccent: String, Codable, CaseIterable, Sendable {
    /// The app's own colour.
    case terracotta
    case orange
    case red
    case pink
    case purple
    case indigo
    case blue
    case teal
    case green
    case graphite
}

/// The tone of a Home Screen widget's background.
public enum WidgetBackgroundStyle: String, Codable, CaseIterable, Sendable {
    /// White in Light Mode, black in Dark Mode: what widgets look like by default.
    case system
    /// A light wash of the chosen colour.
    case soft
    /// The chosen colour itself, with white text.
    case bold
    /// Dark at any time of day.
    case dark
}

/// What the person chose on the Widgets tab. Applies to every widget.
public struct WidgetPreferences: Codable, Hashable, Sendable {
    /// How long a meal can be kept in front, in minutes: what the Widgets tab offers.
    public static let windowOptions = [30, 45, 60, 90, 120]
    public static let defaultWindowMinutes = 60

    public var showCalories: Bool
    public var showFollowingMeal: Bool
    public var showCompletedMeals: Bool
    public var energyUnit: EnergyUnit
    /// How long a meal stays in front after its time before the next one takes its place.
    public var mealWindowMinutes: Int
    /// Whether the medium and large widgets carry a Done button. Off by default: meals move on
    /// by themselves, and ticking them off is for those who like to.
    public var showDoneButton: Bool
    public var accent: WidgetAccent
    public var background: WidgetBackgroundStyle

    public init(
        showCalories: Bool = false,
        showFollowingMeal: Bool = true,
        showCompletedMeals: Bool = true,
        energyUnit: EnergyUnit = .kilocalories,
        mealWindowMinutes: Int = WidgetPreferences.defaultWindowMinutes,
        showDoneButton: Bool = false,
        accent: WidgetAccent = .terracotta,
        background: WidgetBackgroundStyle = .system
    ) {
        self.showCalories = showCalories
        self.showFollowingMeal = showFollowingMeal
        self.showCompletedMeals = showCompletedMeals
        self.energyUnit = energyUnit
        self.mealWindowMinutes = WidgetPreferences.clampedWindow(mealWindowMinutes)
        self.showDoneButton = showDoneButton
        self.accent = accent
        self.background = background
    }

    /// Between a quarter of an hour and four hours, whatever was stored.
    public static func clampedWindow(_ minutes: Int) -> Int {
        min(max(minutes, 15), 240)
    }

    public var mealWindow: TimeInterval {
        TimeInterval(mealWindowMinutes * 60)
    }

    // Tolerant decoding: a field added later must not make an older file unreadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WidgetPreferences()
        showCalories = try container.decodeIfPresent(Bool.self, forKey: .showCalories) ?? defaults.showCalories
        showFollowingMeal = try container.decodeIfPresent(Bool.self, forKey: .showFollowingMeal) ?? defaults.showFollowingMeal
        showCompletedMeals = try container.decodeIfPresent(Bool.self, forKey: .showCompletedMeals) ?? defaults.showCompletedMeals
        energyUnit = (try? container.decodeIfPresent(EnergyUnit.self, forKey: .energyUnit)) ?? defaults.energyUnit
        mealWindowMinutes = WidgetPreferences.clampedWindow((try? container.decodeIfPresent(Int.self, forKey: .mealWindowMinutes)) ?? defaults.mealWindowMinutes)
        showDoneButton = (try? container.decodeIfPresent(Bool.self, forKey: .showDoneButton)) ?? defaults.showDoneButton
        // A colour or tone this version does not know — written by a newer one — falls back to the default.
        accent = (try? container.decodeIfPresent(WidgetAccent.self, forKey: .accent)) ?? defaults.accent
        background = (try? container.decodeIfPresent(WidgetBackgroundStyle.self, forKey: .background)) ?? defaults.background
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
        let schedule = MealSchedule(plan: plan, timeZone: timeZone, currentWindow: preferences.mealWindow)
        var states: OccurrenceStates = [:]
        for occurrence in schedule.occurrences(on: today) where occurrence.date.addingTimeInterval(schedule.currentWindow) < now {
            states[occurrence.key] = .completed
        }
        return WidgetSnapshot(plan: plan, states: states, preferences: preferences, generatedAt: now, timeZone: timeZone)
    }
}
