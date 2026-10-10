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
    /// How long a meal stays in front after its time, on the widget and on Today alike.
    public var mealWindowMinutes: Int
    public var showDoneButtonOnWidget: Bool
    public var widgetAccent: WidgetAccent
    public var widgetBackground: WidgetBackgroundStyle
    /// The person has agreed that what they give the assistant is sent to the AI company that
    /// reads it. Asked the first time, and again whenever this is switched back off.
    public var allowsAssistantSharing: Bool
    /// A day that starts late moves its meals with it (`DayStart`). On unless switched off.
    public var smartMealTimes: Bool
    /// The person closed Today's offer to work out the plan's missing nutrition.
    public var hasDismissedEstimateCard: Bool
    /// The person closed Today's card about DietFlow Plus. It is not shown again.
    public var hasDismissedPlusCard: Bool
    /// The App Store's rating prompt has been asked for once, after a few good days.
    public var hasAskedForReview: Bool
    /// What the person does not eat, in their own words ("no pork, lactose"). Sent with a recipe
    /// request so its steps and substitutes leave those out. Empty when nothing was said.
    public var foodsToAvoid: String

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
        hasSeenPlusIntro: Bool = false,
        mealWindowMinutes: Int = WidgetPreferences.defaultWindowMinutes,
        showDoneButtonOnWidget: Bool = true,
        widgetAccent: WidgetAccent = .terracotta,
        widgetBackground: WidgetBackgroundStyle = .system,
        allowsAssistantSharing: Bool = false,
        smartMealTimes: Bool = true,
        hasDismissedEstimateCard: Bool = false,
        hasDismissedPlusCard: Bool = false,
        hasAskedForReview: Bool = false,
        foodsToAvoid: String = ""
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
        self.mealWindowMinutes = WidgetPreferences.clampedWindow(mealWindowMinutes)
        self.showDoneButtonOnWidget = showDoneButtonOnWidget
        self.widgetAccent = widgetAccent
        self.widgetBackground = widgetBackground
        self.allowsAssistantSharing = allowsAssistantSharing
        self.smartMealTimes = smartMealTimes
        self.hasDismissedEstimateCard = hasDismissedEstimateCard
        self.hasDismissedPlusCard = hasDismissedPlusCard
        self.hasAskedForReview = hasAskedForReview
        self.foodsToAvoid = String(foodsToAvoid.prefix(Self.foodsToAvoidLimit))
    }

    /// Characters kept of `foodsToAvoid`: what the assistant's server reads of it.
    public static let foodsToAvoidLimit = 200

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
        mealWindowMinutes = WidgetPreferences.clampedWindow((try? container.decode(Int.self, forKey: .mealWindowMinutes)) ?? defaults.mealWindowMinutes)
        showDoneButtonOnWidget = (try? container.decode(Bool.self, forKey: .showDoneButtonOnWidget)) ?? defaults.showDoneButtonOnWidget
        widgetAccent = (try? container.decode(WidgetAccent.self, forKey: .widgetAccent)) ?? defaults.widgetAccent
        widgetBackground = (try? container.decode(WidgetBackgroundStyle.self, forKey: .widgetBackground)) ?? defaults.widgetBackground
        allowsAssistantSharing = (try? container.decode(Bool.self, forKey: .allowsAssistantSharing)) ?? defaults.allowsAssistantSharing
        smartMealTimes = (try? container.decode(Bool.self, forKey: .smartMealTimes)) ?? defaults.smartMealTimes
        hasDismissedEstimateCard = (try? container.decode(Bool.self, forKey: .hasDismissedEstimateCard)) ?? defaults.hasDismissedEstimateCard
        hasDismissedPlusCard = (try? container.decode(Bool.self, forKey: .hasDismissedPlusCard)) ?? defaults.hasDismissedPlusCard
        hasAskedForReview = (try? container.decode(Bool.self, forKey: .hasAskedForReview)) ?? defaults.hasAskedForReview
        foodsToAvoid = String(((try? container.decode(String.self, forKey: .foodsToAvoid)) ?? defaults.foodsToAvoid).prefix(Self.foodsToAvoidLimit))
    }

    public var widgetPreferences: WidgetPreferences {
        WidgetPreferences(
            showCalories: showCaloriesOnWidget,
            showFollowingMeal: showFollowingMealOnWidget,
            showCompletedMeals: showCompletedMealsOnWidget,
            energyUnit: energyUnit,
            mealWindowMinutes: mealWindowMinutes,
            showDoneButton: showDoneButtonOnWidget,
            accent: widgetAccent,
            background: widgetBackground
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
