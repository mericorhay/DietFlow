import Foundation

/// A clock time with no date and no time zone: 08:30 means 08:30 wherever the phone is.
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// Which meal of the day this is. The raw values are part of the stored plan and of the MCP
/// contract, so they are never renamed; display names come from the string catalogs.
public enum MealSlot: String, Codable, CaseIterable, Sendable {
    case breakfast
    case morningSnack
    case lunch
    case afternoonSnack
    case dinner
    case eveningSnack
}

public struct Meal: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var slot: MealSlot
    public var time: TimeOfDay
    /// Written by the person, their dietitian or the assistant, in their own language. Never translated.
    public var title: String
    public var items: [String]
    public var note: String?

    public init(id: UUID = UUID(), slot: MealSlot, time: TimeOfDay, title: String, items: [String] = [], note: String? = nil) {
        self.id = id
        self.slot = slot
        self.time = time
        self.title = title
        self.items = items
        self.note = note
    }
}

public struct DayPlan: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var meals: [Meal]

    public init(id: UUID = UUID(), meals: [Meal]) {
        self.id = id
        self.meals = meals
    }
}

/// A plan is a cycle of days that repeats from `startDate`: seven days make a weekly plan, one day
/// makes "the same every day". Set once, it keeps answering "what do I eat next" indefinitely.
public struct MealPlan: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var startDate: Date
    public var days: [DayPlan]

    public init(id: UUID = UUID(), name: String, startDate: Date, days: [DayPlan]) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.days = days
    }
}
