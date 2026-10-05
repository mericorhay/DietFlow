import Foundation
import OSLog
import UserNotifications
import Domain

public enum ReminderAuthorization: Sendable {
    case notDetermined
    case denied
    case allowed
}

/// The buttons a meal reminder carries. Both work from the notification itself.
public enum MealReminderAction: String, Sendable {
    case done = "meal.done"
    case skip = "meal.skip"
}

/// Local notifications at meal times. Secondary to the widget, off until the person turns them on,
/// and nothing here needs a server or the app to be running once scheduled.
public struct MealReminderScheduler: Sendable {
    private static let logger = Logger(subsystem: "com.orhay.dietflow", category: "Reminders")
    private static let identifierPrefix = "meal."
    public static let categoryIdentifier = "meal.reminder"
    private static let occurrenceInfoKey = "occurrence"

    public init() {}

    /// Registers the Done and Skip buttons every meal reminder carries. Called at launch, so the
    /// titles are in the language the app is using.
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
        let category = UNNotificationCategory(identifier: Self.categoryIdentifier, actions: [done, skip], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
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

    /// Replaces every pending meal reminder with `requests`.
    public func reschedule(_ requests: [ReminderRequest], timeZone: TimeZone = .current) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard await authorization() == .allowed else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = Self.title(for: request)
            content.body = request.occurrence.meal.title
            content.sound = .default
            content.threadIdentifier = "meals"
            content.categoryIdentifier = Self.categoryIdentifier
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
