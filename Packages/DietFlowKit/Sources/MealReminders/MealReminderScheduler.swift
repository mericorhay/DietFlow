import Foundation
import UserNotifications
import Domain

/// One local notification per upcoming meal. Nothing here needs a server or the app to be running.
public struct MealReminderScheduler: Sendable {
    /// iOS keeps at most 64 pending local notifications per app; stay under it and top up on launch.
    public static let limit = 60

    public init() {}

    public func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Replaces every pending reminder with ones for `upcoming`.
    public func reschedule(_ upcoming: [ScheduledMeal], calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for scheduled in upcoming.prefix(Self.limit) {
            let content = UNMutableNotificationContent()
            content.title = scheduled.meal.title
            content.body = scheduled.meal.items.joined(separator: ", ")
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduled.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = "meal.\(Int(scheduled.date.timeIntervalSince1970))"
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger), withCompletionHandler: nil)
        }
    }
}
