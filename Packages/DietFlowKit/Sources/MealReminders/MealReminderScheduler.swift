import Foundation
import OSLog
import UserNotifications
import Domain

public enum ReminderAuthorization: Sendable {
    case notDetermined
    case denied
    case allowed
}

/// The buttons a meal reminder carries. All of them work from the notification itself.
public enum MealReminderAction: String, Sendable {
    case done = "meal.done"
    case skip = "meal.skip"
    /// Only on the day's first meal: the person just got up, so the day's meals move with them.
    case wokeUp = "meal.wokeUp"
}

/// Local notifications at meal times. Secondary to the widget, off until the person turns them on,
/// and nothing here needs a server or the app to be running once scheduled.
public struct MealReminderScheduler: Sendable {
    private static let logger = Logger(subsystem: "com.orhay.dietflow", category: "Reminders")
    private static let identifierPrefix = "meal."
    public static let categoryIdentifier = "meal.reminder"
    /// The day's first meal: the same buttons, led by "Just Woke Up".
    public static let firstMealCategoryIdentifier = "meal.reminder.first"
    private static let occurrenceInfoKey = "occurrence"

    public init() {}

    /// Registers the Done and Skip buttons every meal reminder carries, and "Just Woke Up" on the
    /// day's first. Called at launch, so the titles are in the language the app is using.
    public func registerActions() {
        let done = UNNotificationAction(
            identifier: MealReminderAction.done.rawValue,
            title: String(localized: "notification.action.done", bundle: .module),
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "checkmark")
        )
        let skip = UNNotificationAction(
            identifier: MealReminderAction.skip.rawValue,
            title: String(localized: "notification.action.skip", bundle: .module),
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "forward.end")
        )
        let wokeUp = UNNotificationAction(
            identifier: MealReminderAction.wokeUp.rawValue,
            title: String(localized: "notification.action.wokeUp", bundle: .module),
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "sun.horizon")
        )
        let category = UNNotificationCategory(identifier: Self.categoryIdentifier, actions: [done, skip], intentIdentifiers: [], options: [])
        let first = UNNotificationCategory(identifier: Self.firstMealCategoryIdentifier, actions: [wokeUp, done, skip], intentIdentifiers: [], options: [])
        // One call with every category: each call replaces all of them.
        UNUserNotificationCenter.current().setNotificationCategories([category, first])
    }

    /// The meal a delivered reminder is about.
    public static func occurrenceKey(userInfo: [AnyHashable: Any]) -> OccurrenceKey? {
        (userInfo[occurrenceInfoKey] as? String).flatMap(OccurrenceKey.init)
    }

    public func authorization() async -> ReminderAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    /// Asks for permission. Only ever called after the person turns reminders on.
    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.logger.error("Notification permission request failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Removes the reminder for one meal on one day, at once. Called the moment a meal is marked
    /// done or skipped, from whichever process marked it: the widget's Done button runs in the
    /// widget's process, which may be suspended before anything asynchronous finishes.
    public func cancelReminder(for key: OccurrenceKey) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifierPrefix + key.description])
    }

    /// Makes the pending meal reminders exactly `requests`.
    ///
    /// Nothing is cleared up front. Reminders that are no longer wanted are removed; the rest are
    /// added over what is already there, since a request with the same identifier replaces the
    /// pending one. So if this is cut off halfway — the app suspended, a newer reschedule taking
    /// over — every reminder that should exist still does. Clearing first and adding after left a
    /// window in which an interruption wiped them all.
    public func reschedule(_ requests: [ReminderRequest], timeZone: TimeZone = .current) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }

        guard await authorization() == .allowed else {
            center.removePendingNotificationRequests(withIdentifiers: ours)
            return
        }
        let wanted = Set(requests.map(\.identifier))
        center.removePendingNotificationRequests(withIdentifiers: ours.filter { !wanted.contains($0) })

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        for request in requests {
            // Superseded by a newer reschedule: stop adding what it is about to replace.
            if Task.isCancelled { return }
            let content = UNMutableNotificationContent()
            content.title = Self.title(for: request)
            content.body = request.occurrence.meal.title
            content.sound = .default
            content.threadIdentifier = "meals"
            content.categoryIdentifier = request.isFirstOfDay ? Self.firstMealCategoryIdentifier : Self.categoryIdentifier
            content.userInfo = [Self.occurrenceInfoKey: request.occurrence.key.description]

            // Wall-clock components: if the person changes time zone, the reminder follows the
            // local clock, just like the plan.
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: request.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
            } catch {
                Self.logger.error("Could not schedule a reminder: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) })
    }

    /// "Lunch in 10 minutes", "Dinner in 1 hour", "Lunch now".
    static func title(for request: ReminderRequest) -> String {
        let meal = request.occurrence.meal.typeLabel
        guard request.minutesBefore > 0 else {
            return String(localized: "notification.title.now", defaultValue: "\(meal) now", bundle: .module)
        }
        let duration = Duration.seconds(request.minutesBefore * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2))
        return String(localized: "notification.title.upcoming", defaultValue: "\(meal) in \(duration)", bundle: .module)
    }
}
