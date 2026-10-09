import Foundation

/// One reminder to schedule: which meal, and when to fire.
public struct ReminderRequest: Hashable, Sendable {
    public let occurrence: MealOccurrence
    public let fireDate: Date
    public let minutesBefore: Int
    /// The day's first meal: its reminder is where the person can say they just got up.
    public var isFirstOfDay: Bool = false

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
        days: Int = 7,
        dayStarts: DayStarts = [:]
    ) -> [ReminderRequest] {
        guard let plan else { return [] }
        // A day that started late moves its reminders with its meals.
        let schedule = MealSchedule(plan: plan, timeZone: timeZone, dayStarts: dayStarts)
        let today = CalendarDay(now, in: timeZone)

        var requests: [ReminderRequest] = []
        let occurrences = schedule.occurrences(from: today, days: days, states: states)
        for (index, occurrence) in occurrences.enumerated() where occurrence.isPending {
            guard let minutes = (occurrence.meal.reminder ?? defaultOffset).minutesBefore else { continue }
            let fireDate = occurrence.date.addingTimeInterval(TimeInterval(-minutes * 60))
            guard fireDate > now else { continue }
            let isFirst = index == 0 || occurrences[index - 1].day != occurrence.day
            requests.append(ReminderRequest(occurrence: occurrence, fireDate: fireDate, minutesBefore: minutes, isFirstOfDay: isFirst))
        }
        return Array(requests.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
