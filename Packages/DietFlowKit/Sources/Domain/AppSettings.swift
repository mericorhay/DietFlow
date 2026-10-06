import Foundation

/// App-wide settings. Kept in the App Group's defaults because the widget needs the widget
/// preferences and the intents need the reminder settings.
public struct AppSettings: Codable, Hashable, Sendable {
    public var remindersEnabled: Bool
    public var defaultReminder: ReminderOffset
    public var energyUnit: EnergyUnit
    /// 1 = Sunday … 7 = Saturday; nil follows the system.
    public var firstWeekday: Int?
    public var showCaloriesOnWidget: Bool
    public var showFollowingMealOnWidget: Bool
    public var showCompletedMealsOnWidget: Bool
    public var hasCompletedOnboarding: Bool
    /// The person closed Today's suggestion to add the widget.
    public var hasDismissedWidgetTip: Bool
    /// The first-launch introduction to DietFlow Plus has been shown. It is shown once.
    public var hasSeenPlusIntro: Bool

    public init(
        remindersEnabled: Bool = false,
        defaultReminder: ReminderOffset = .tenMinutes,
        energyUnit: EnergyUnit = .kilocalories,
        firstWeekday: Int? = nil,
        showCaloriesOnWidget: Bool = false,
        showFollowingMealOnWidget: Bool = true,
        showCompletedMealsOnWidget: Bool = true,
        hasCompletedOnboarding: Bool = false,
        hasDismissedWidgetTip: Bool = false,
        hasSeenPlusIntro: Bool = false
    ) {
        self.remindersEnabled = remindersEnabled
        self.defaultReminder = defaultReminder
        self.energyUnit = energyUnit
        self.firstWeekday = firstWeekday
        self.showCaloriesOnWidget = showCaloriesOnWidget
        self.showFollowingMealOnWidget = showFollowingMealOnWidget
        self.showCompletedMealsOnWidget = showCompletedMealsOnWidget
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.hasDismissedWidgetTip = hasDismissedWidgetTip
        self.hasSeenPlusIntro = hasSeenPlusIntro
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        remindersEnabled = (try? container.decode(Bool.self, forKey: .remindersEnabled)) ?? defaults.remindersEnabled
        defaultReminder = (try? container.decode(ReminderOffset.self, forKey: .defaultReminder)) ?? defaults.defaultReminder
        energyUnit = (try? container.decode(EnergyUnit.self, forKey: .energyUnit)) ?? defaults.energyUnit
        firstWeekday = try? container.decode(Int.self, forKey: .firstWeekday)
        showCaloriesOnWidget = (try? container.decode(Bool.self, forKey: .showCaloriesOnWidget)) ?? defaults.showCaloriesOnWidget
        showFollowingMealOnWidget = (try? container.decode(Bool.self, forKey: .showFollowingMealOnWidget)) ?? defaults.showFollowingMealOnWidget
        showCompletedMealsOnWidget = (try? container.decode(Bool.self, forKey: .showCompletedMealsOnWidget)) ?? defaults.showCompletedMealsOnWidget
        hasCompletedOnboarding = (try? container.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? defaults.hasCompletedOnboarding
        hasDismissedWidgetTip = (try? container.decode(Bool.self, forKey: .hasDismissedWidgetTip)) ?? defaults.hasDismissedWidgetTip
        hasSeenPlusIntro = (try? container.decode(Bool.self, forKey: .hasSeenPlusIntro)) ?? defaults.hasSeenPlusIntro
    }

    public var widgetPreferences: WidgetPreferences {
        WidgetPreferences(
            showCalories: showCaloriesOnWidget,
            showFollowingMeal: showFollowingMealOnWidget,
            showCompletedMeals: showCompletedMealsOnWidget,
            energyUnit: energyUnit
        )
    }
}

/// A plan in the list of plans, without its meals.
public struct PlanSummary: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let schedule: PlanSchedule
    public let isActive: Bool
    public let mealCount: Int
    public let updatedAt: Date

    public init(id: UUID, name: String, schedule: PlanSchedule, isActive: Bool, mealCount: Int, updatedAt: Date) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.isActive = isActive
        self.mealCount = mealCount
        self.updatedAt = updatedAt
    }
}
