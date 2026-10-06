import Foundation

/// A stretch of time an allowance is counted over: from `start` up to, not including, `end`.
public struct BillingWindow: Hashable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// The dates subscriptions turn on: when a free trial ends, when a month's allowance starts
/// again. All of it is counted in UTC on the Gregorian calendar, so the answer does not move when
/// the person crosses a time zone or uses another calendar.
public enum BillingCycle {
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    public enum Unit: String, Codable, Hashable, Sendable {
        case day, week, month, year
    }

    /// A length of time as the App Store states it: "7 days", "1 month".
    public struct Span: Codable, Hashable, Sendable {
        public let value: Int
        public let unit: Unit

        public init(value: Int, unit: Unit) {
            self.value = value
            self.unit = unit
        }
    }

    /// The moment `span` after `date`: when a trial started now would end, when a period that began
    /// then would renew. A month added to the 31st lands on the last day of a shorter month.
    public static func date(byAdding span: Span, to date: Date) -> Date {
        let component: Calendar.Component
        var value = span.value
        switch span.unit {
        case .day: component = .day
        case .week:
            component = .day
            value *= 7
        case .month: component = .month
        case .year: component = .year
        }
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    /// The month-long window that holds `date`, counted from `anchor`: someone who paid on the
    /// 16th has windows from the 16th to the 16th.
    ///
    /// Every window is measured from the anchor itself, never from the window before it. Counted
    /// the other way, an anchor on the 31st would slip to the 28th in February and stay there for
    /// good; measured from the anchor it goes 31 January, 28 February, 31 March.
    ///
    /// A `date` before the anchor gets the first window.
    public static func monthlyWindow(anchoredAt anchor: Date, containing date: Date) -> BillingWindow {
        func boundary(_ months: Int) -> Date {
            calendar.date(byAdding: .month, value: months, to: anchor) ?? anchor.addingTimeInterval(Double(months) * 30 * 86_400)
        }
        guard date >= anchor else { return BillingWindow(start: anchor, end: boundary(1)) }

        // A first guess from whole months elapsed, then a step either way: the guess is off by
        // one around the short months, which is exactly where this has to be right.
        var months = max(0, calendar.dateComponents([.month], from: anchor, to: date).month ?? 0)
        while months > 0, boundary(months) > date { months -= 1 }
        while boundary(months + 1) <= date { months += 1 }
        return BillingWindow(start: boundary(months), end: boundary(months + 1))
    }

    /// The calendar month that holds `date`.
    public static func calendarMonth(containing date: Date) -> BillingWindow {
        let interval = calendar.dateInterval(of: .month, for: date)
        let start = interval?.start ?? date
        return BillingWindow(start: start, end: interval?.end ?? start.addingTimeInterval(30 * 86_400))
    }

    /// "2026-10": the name a calendar month's uses are counted under.
    public static func monthKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// "plus-2026-10-16": the name a billing window's uses are counted under. A new window is a new
    /// name, so a new count; names sort by date.
    public static func windowKey(for window: BillingWindow) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: window.start)
        return String(format: "plus-%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Which DietFlow Plus product a purchase is.
public enum PlusProductKind: String, Codable, Hashable, CaseIterable, Sendable {
    case monthly
    case yearly
    /// Bought once, never renews, never ends.
    case lifetime
}

/// What the App Store says the person holds right now.
public struct PlusEntitlement: Codable, Hashable, Sendable {
    public var kind: PlusProductKind
    /// When the current period was charged, or the trial began; for lifetime, when it was bought.
    public var periodStart: Date
    /// When the current period ends. Nil for lifetime.
    public var periodEnd: Date?
    /// Whether it renews at `periodEnd`. False once the person has cancelled, and for lifetime.
    public var willRenew: Bool
    /// Whether the current period is the free trial, with the first charge still ahead.
    public var isTrial: Bool

    public init(kind: PlusProductKind, periodStart: Date, periodEnd: Date?, willRenew: Bool, isTrial: Bool) {
        self.kind = kind
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.willRenew = willRenew
        self.isTrial = isTrial
    }

    /// The window the allowance is counted over at `date`.
    ///
    /// A monthly subscription's window is the period the App Store charged for, trial included:
    /// those are the real dates, so there is nothing to work out. A year or a lifetime is still
    /// counted month by month, from the day it was bought, so the allowance comes back every
    /// month rather than once a year or never.
    public func allowanceWindow(containing date: Date = .now) -> BillingWindow {
        if kind == .monthly, let periodEnd, periodEnd > periodStart {
            let window = BillingWindow(start: periodStart, end: periodEnd)
            if window.contains(date) { return window }
        }
        return BillingCycle.monthlyWindow(anchoredAt: periodStart, containing: date)
    }
}
