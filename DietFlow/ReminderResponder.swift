import Foundation
import UserNotifications
import AppCore
import Domain
import MealReminders

/// Answers meal reminders. Done and Skip mark the meal from the notification itself, without
/// opening the app — the widget moves on at once; tapping the reminder opens that meal.
///
/// Notification Center may call in on any thread, so this type is not tied to the main actor; it
/// hops there to touch the store.
nonisolated final class ReminderResponder: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let store: MealPlanStore
    private let open: @MainActor @Sendable (AppLink) -> Void

    init(store: MealPlanStore, open: @escaping @MainActor @Sendable (AppLink) -> Void) {
        self.store = store
        self.open = open
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let key = MealReminderScheduler.occurrenceKey(userInfo: response.notification.request.content.userInfo) else { return }
        let action = response.actionIdentifier
        let store = store
        let open = open
        await MainActor.run {
            // The widget may have changed something since the app last looked.
            store.refresh()
            // A reminder delivered before its meal or plan was deleted has nothing left to mark;
            // its buttons then do nothing, rather than raise an error about a change that was
            // never possible.
            let exists = store.occurrence(for: key) != nil
            switch action {
            case MealReminderAction.done.rawValue:
                if exists { store.attempt { try store.markMealCompleted(key) } }
            case MealReminderAction.skip.rawValue:
                if exists { store.attempt { try store.markMealSkipped(key) } }
            default:
                open(.meal(key))
            }
        }
    }

    /// A reminder that arrives while the app is open still shows.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
