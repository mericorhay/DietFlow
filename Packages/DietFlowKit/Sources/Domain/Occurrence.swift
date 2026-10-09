import Foundation

/// What happened to one meal on one day. The plan's template is never touched by this: marking
/// Tuesday's lunch done says nothing about the same lunch next cycle.
public enum OccurrenceState: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
    case skipped
}

/// Names one meal on one day: the plan meal it comes from and the calendar day it falls on.
public struct OccurrenceKey: Hashable, Comparable, Sendable {
    public let mealID: UUID
    public let day: CalendarDay

    public init(mealID: UUID, day: CalendarDay) {
        self.mealID = mealID
        self.day = day
    }

    public static func < (lhs: OccurrenceKey, rhs: OccurrenceKey) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        return lhs.mealID.uuidString < rhs.mealID.uuidString
    }
}

extension OccurrenceKey: CustomStringConvertible, LosslessStringConvertible {
    /// "<meal UUID>@2026-10-05": stable, readable, and safe as a file key or an intent identifier.
    public var description: String {
        "\(mealID.uuidString)@\(day.description)"
    }

    public init?(_ description: String) {
        let parts = description.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, let mealID = UUID(uuidString: String(parts[0])), let day = CalendarDay(String(parts[1])) else {
            return nil
        }
        self.init(mealID: mealID, day: day)
    }
}

extension OccurrenceKey: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let key = OccurrenceKey(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a meal occurrence key: \(text)")
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Recorded states, by occurrence. A missing key means pending.
public typealias OccurrenceStates = [OccurrenceKey: OccurrenceState]

/// A plan meal placed on a real day and time, with what has happened to it.
public struct MealOccurrence: Hashable, Identifiable, Sendable {
    public let meal: Meal
    public let day: CalendarDay
    /// When it is scheduled, in the time zone the schedule was asked in.
    public let date: Date
    public let state: OccurrenceState
    /// The clock time it is at on this day: the plan's own time, or a later one when the day started
    /// late (`DayStart`).
    public let time: TimeOfDay

    public init(meal: Meal, day: CalendarDay, date: Date, state: OccurrenceState, time: TimeOfDay? = nil) {
        self.meal = meal
        self.day = day
        self.date = date
        self.state = state
        self.time = time ?? meal.time
    }

    public var key: OccurrenceKey { OccurrenceKey(mealID: meal.id, day: day) }
    public var id: OccurrenceKey { key }
    public var isPending: Bool { state == .pending }
    /// Moved from the plan's time today because the day started late.
    public var isMoved: Bool { time != meal.time }

    public func with(state: OccurrenceState) -> MealOccurrence {
        MealOccurrence(meal: meal, day: day, date: date, state: state, time: time)
    }
}
