import Foundation

/// A date on the wall calendar, with no time and no time zone: "5 October 2026" is that day
/// wherever the phone happens to be. Plans start on one and completions are recorded against one,
/// so neither shifts by a day when the person flies across time zones.
///
/// Always Gregorian, whatever calendar the person uses: this is an identifier, not something shown.
/// Anything displayed goes through a `Date` and the person's own calendar and locale.
public struct CalendarDay: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone = .current) {
        let components = Self.gregorian(in: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    public static func today(in timeZone: TimeZone = .current, now: Date = .now) -> CalendarDay {
        CalendarDay(now, in: timeZone)
    }

    /// The first instant of this day in `timeZone`. Usually midnight; in the few zones that jump
    /// over midnight for daylight saving, the first moment that exists.
    public func startDate(in timeZone: TimeZone = .current) -> Date {
        let calendar = Self.gregorian(in: timeZone)
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? utcMidnight
        return calendar.startOfDay(for: noon)
    }

    /// The first instant of the following day: where this day ends.
    public func endDate(in timeZone: TimeZone = .current) -> Date {
        adding(days: 1).startDate(in: timeZone)
    }

    /// Noon in `timeZone`: a safe instant to hand to formatters, clear of any daylight-saving jump.
    public func middayDate(in timeZone: TimeZone = .current) -> Date {
        Self.gregorian(in: timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? utcMidnight
    }

    public func adding(days: Int) -> CalendarDay {
        guard days != 0, let shifted = Self.utc.date(byAdding: .day, value: days, to: utcMidnight) else { return self }
        return CalendarDay(shifted, in: Self.utcZone)
    }

    /// Whole calendar days from this day to `other`; negative when `other` is earlier. Counted on
    /// the wall calendar, so a 23- or 25-hour daylight-saving day still counts as one.
    public func days(to other: CalendarDay) -> Int {
        Self.utc.dateComponents([.day], from: utcMidnight, to: other.utcMidnight).day ?? 0
    }

    /// 1 is Sunday through 7 Saturday, the numbering `Calendar.firstWeekday` uses.
    public var weekday: Int {
        Self.utc.component(.weekday, from: utcMidnight)
    }

    /// The days of the week containing this one, starting on `firstWeekday` (1 = Sunday).
    public func week(startingOn firstWeekday: Int) -> [CalendarDay] {
        let back = (weekday - firstWeekday + 7) % 7
        let first = adding(days: -back)
        return (0..<7).map { first.adding(days: $0) }
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private var utcMidnight: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    private static let utcZone = TimeZone(secondsFromGMT: 0) ?? .gmt

    private static let utc: Calendar = gregorian(in: utcZone)

    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

// MARK: - Text form

extension CalendarDay: CustomStringConvertible, LosslessStringConvertible {
    /// "2026-10-05": the form used in stored files and in the import format.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Reads "2026-10-05". Rejects days that do not exist, like 30 February.
    public init?(_ description: String) {
        let parts = description.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        let candidate = CalendarDay(year: year, month: month, day: day)
        // A day past the end of its month rolls over into the next one; that is not the day asked for.
        guard CalendarDay(candidate.utcMidnight, in: Self.utcZone) == candidate else { return nil }
        self = candidate
    }
}

extension CalendarDay: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = CalendarDay(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a day as yyyy-MM-dd, found \(text)")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
