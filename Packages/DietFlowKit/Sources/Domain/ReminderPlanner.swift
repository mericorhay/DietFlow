import Foundation

/// One reminder to schedule: which meal, and when to fire.
public struct ReminderRequest: Hashable, Sendable {
    public let occurrence: MealOccurrence
    public let fireDate: Date
    public let minutesBefore: Int

    /// Stable per meal and day, so rescheduling replaces rather than duplicates.
    public var identifier: String { "meal.\(occurrence.key.description)" }
}

/// Decides which reminders should exist. Scheduling them is the notification module's job; what
/// they are is decided here, where it can be tested.
public enum ReminderPlanner {
    /// iOS keeps at most 64 pending local notifications per app. Stay under it and top up on launch.
    public static let limit = 60

    public static func requests(
        plan: MealPlan?,
        states: OccurrenceStates,
        defaultOffset: ReminderOffset,
        now: Date,
        timeZone: TimeZone = .current,
        days: Int = 7
    ) -> [ReminderRequest] {
        guard let plan else { return [] }
        let schedule = MealSchedule(plan: plan, timeZone: timeZone)
        let today = CalendarDay(now, in: timeZone)

        var requests: [ReminderRequest] = []
        for occurrence in schedule.occurrences(from: today, days: days, states: states) where occurrence.isPending {
            guard let minutes = (occurrence.meal.reminder ?? defaultOffset).minutesBefore else { continue }
            let fireDate = occurrence.date.addingTimeInterval(TimeInterval(-minutes * 60))
            guard fireDate > now else { continue }
            requests.append(ReminderRequest(occurrence: occurrence, fireDate: fireDate, minutesBefore: minutes))
        }
        return Array(requests.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
