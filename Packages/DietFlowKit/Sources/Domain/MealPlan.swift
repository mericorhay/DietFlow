import Foundation

/// A clock time with no date and no time zone: 08:30 means 08:30 wherever the phone is.
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public init(minutesSinceMidnight: Int) {
        let wrapped = ((minutesSinceMidnight % 1440) + 1440) % 1440
        self.init(hour: wrapped / 60, minute: wrapped % 60)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    /// The instant this clock time happens on `day` in `timeZone`. A time skipped by a
    /// daylight-saving jump moves to the first moment after the jump; a time that happens twice
    /// when clocks go back uses its first pass.
    public func date(on day: CalendarDay, in timeZone: TimeZone = .current) -> Date {
        let calendar = CalendarDay.gregorian(in: timeZone)
        let start = day.startDate(in: timeZone)
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: start,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? start.addingTimeInterval(TimeInterval(minutesSinceMidnight * 60))
    }

    /// "14:05": the stored and imported form. Never shown; display goes through a `Date` so the
    /// person's 12- or 24-hour preference applies.
    public var isoString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// Which meal of the day this is. The raw values are stored and are part of the import format,
/// so they never change; display names come from the string catalog.
public enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast
    case snack
    case lunch
    case dinner
    case other

    public var displayName: String {
        switch self {
        case .breakfast: String(localized: "mealType.breakfast", bundle: .module)
        case .snack: String(localized: "mealType.snack", bundle: .module)
        case .lunch: String(localized: "mealType.lunch", bundle: .module)
        case .dinner: String(localized: "mealType.dinner", bundle: .module)
        case .other: String(localized: "mealType.other", bundle: .module)
        }
    }

    /// Used when a meal arrives without a time, so it lands somewhere sensible and the review
    /// screen can point it out.
    public var typicalTime: TimeOfDay {
        switch self {
        case .breakfast: TimeOfDay(hour: 8, minute: 0)
        case .snack: TimeOfDay(hour: 16, minute: 0)
        case .lunch: TimeOfDay(hour: 13, minute: 0)
        case .dinner: TimeOfDay(hour: 19, minute: 0)
        case .other: TimeOfDay(hour: 12, minute: 0)
        }
    }

    /// The sitting a clock time most likely is, when nothing names it: before 10:30 breakfast,
    /// midday lunch, evening dinner, and a snack in between.
    public static func suggested(for time: TimeOfDay) -> MealType {
        switch time.minutesSinceMidnight {
        case ..<(10 * 60 + 30): .breakfast
        case (11 * 60 + 30)..<(15 * 60): .lunch
        case (17 * 60 + 30)..<(22 * 60): .dinner
        default: .snack
        }
    }

    /// Tie-breaker for meals at the same minute.
    var sortRank: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .snack: 2
        case .dinner: 3
        case .other: 4
        }
    }
}

/// Energy in kilocalories and macronutrients in grams, all optional: most plans list some of
/// these for some meals, and nothing is ever invented to fill the gaps.
public struct Nutrition: Codable, Hashable, Sendable {
    public var calories: Int?
    public var protein: Double?
    public var carbohydrates: Double?
    public var fat: Double?

    public init(calories: Int? = nil, protein: Double? = nil, carbohydrates: Double? = nil, fat: Double? = nil) {
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
    }

    public var isEmpty: Bool {
        calories == nil && protein == nil && carbohydrates == nil && fat == nil
    }

    public static let calorieRange = 0...10_000
    public static let gramRange = 0.0...2_000.0
}

/// How long before a meal its reminder arrives.
public enum ReminderOffset: Int, Codable, CaseIterable, Sendable {
    case off = -1
    case atTime = 0
    case tenMinutes = 10
    case thirtyMinutes = 30
    case oneHour = 60

    /// Nil when there is no reminder.
    public var minutesBefore: Int? {
        self == .off ? nil : rawValue
    }

    public var displayName: String {
        switch self {
        case .off: String(localized: "reminder.offset.off", bundle: .module)
        case .atTime: String(localized: "reminder.offset.atTime", bundle: .module)
        case .tenMinutes: String(localized: "reminder.offset.tenMinutes", bundle: .module)
        case .thirtyMinutes: String(localized: "reminder.offset.thirtyMinutes", bundle: .module)
        case .oneHour: String(localized: "reminder.offset.oneHour", bundle: .module)
        }
    }
}

public enum PlanKind: String, Codable, CaseIterable, Sendable {
    /// Day 1, Day 2, … from a start date, optionally starting over after the last day.
    case cycle
    /// Each day of the plan is a particular date. Never repeats.
    case fixedDates
}

/// When a plan runs.
public struct PlanSchedule: Codable, Hashable, Sendable {
    public var kind: PlanKind
    public var startDay: CalendarDay
    /// Days in one pass through the plan. At least one.
    public var length: Int
    /// Whether the plan starts over at Day 1 after its last day. Always false for fixed dates.
    public var repeats: Bool

    public init(kind: PlanKind = .cycle, startDay: CalendarDay, length: Int, repeats: Bool) {
        self.kind = kind
        self.startDay = startDay
        self.length = max(1, length)
        self.repeats = kind == .cycle ? repeats : false
    }

    /// The last day of the plan, or nil when it repeats forever.
    public var lastDay: CalendarDay? {
        repeats ? nil : startDay.adding(days: length - 1)
    }

    public static let maximumLength = 366
}

/// One meal in the plan's template: "Day 3, 14:00, lunch". Whether it was eaten on a particular
/// date is recorded separately (`OccurrenceState`), so a repeating plan is never edited by use.
public struct Meal: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Zero-based day of the plan. Day 1 on screen is index 0.
    public var dayIndex: Int
    public var type: MealType
    /// Shown instead of the type's name when set — "Pre-workout", "Brunch". Mostly for `.other`.
    public var customTypeName: String?
    public var time: TimeOfDay
    /// Written by the person, their dietitian or an AI, in their own language. Never translated.
    public var title: String
    public var details: String?
    public var portion: String?
    public var nutrition: Nutrition
    public var notes: String?
    /// Nil follows the app-wide default.
    public var reminder: ReminderOffset?

    public init(
        id: UUID = UUID(),
        dayIndex: Int,
        type: MealType,
        customTypeName: String? = nil,
        time: TimeOfDay,
        title: String,
        details: String? = nil,
        portion: String? = nil,
        nutrition: Nutrition = Nutrition(),
        notes: String? = nil,
        reminder: ReminderOffset? = nil
    ) {
        self.id = id
        self.dayIndex = max(0, dayIndex)
        self.type = type
        self.customTypeName = customTypeName
        self.time = time
        self.title = title
        self.details = details
        self.portion = portion
        self.nutrition = nutrition
        self.notes = notes
        self.reminder = reminder
    }

    /// What to call this meal on screen: the person's own name for it, or its type.
    public var typeLabel: String {
        customTypeName?.trimmedNonEmpty ?? type.displayName
    }

    /// Clock order; meals at the same minute keep a stable, sensible order.
    public static func scheduleOrder(_ lhs: Meal, _ rhs: Meal) -> Bool {
        if lhs.time != rhs.time { return lhs.time < rhs.time }
        if lhs.type.sortRank != rhs.type.sortRank { return lhs.type.sortRank < rhs.type.sortRank }
        if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// A plan: a run of days, each with its meals, starting on a date and optionally repeating.
/// Set once, it keeps answering "what do I eat next" for as long as it runs.
public struct MealPlan: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var schedule: PlanSchedule
    public var meals: [Meal]

    public init(id: UUID = UUID(), name: String, schedule: PlanSchedule, meals: [Meal] = []) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.meals = meals
    }

    /// The meals of one plan day, in clock order. Meals placed beyond the plan's length are ignored.
    public func meals(onDayIndex index: Int) -> [Meal] {
        guard index >= 0, index < schedule.length else { return [] }
        return meals.filter { $0.dayIndex == index }.sorted(by: Meal.scheduleOrder)
    }

    public var mealCount: Int {
        meals.filter { $0.dayIndex < schedule.length }.count
    }

    /// The copy the widget carries: what it draws and nothing else, so the shared file stays small.
    public func trimmedForWidget() -> MealPlan {
        var copy = self
        copy.meals = meals
            .filter { $0.dayIndex < schedule.length }
            .map { meal in
                var lean = meal
                lean.details = meal.details?.trimmedNonEmpty.map { String($0.prefix(140)) }
                lean.portion = nil
                lean.notes = nil
                lean.reminder = nil
                lean.nutrition = Nutrition(calories: meal.nutrition.calories)
                return lean
            }
        return copy
    }
}

extension String {
    /// The string without surrounding whitespace, or nil when nothing is left.
    public var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
