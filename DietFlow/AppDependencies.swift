import Foundation
import Observation
import UserNotifications
import AIServices
import Analytics
import AppCore
import Domain
import MealReminders

/// The composition root. Modules never reach for each other; whatever a screen needs is built here
/// and handed to it, which is also what lets previews and tests swap the real thing out.
@Observable
final class AppDependencies {
    /// Every plan change goes through here: the screens, the intents and imports alike.
    let store: MealPlanStore
    /// Kept for the assistant module, which no screen shows at the moment.
    let assistantEndpoint: AssistantEndpoint?
    let analytics: any AnalyticsSink = NoAnalytics()
    /// A place to open that arrived from outside the views, such as a tapped reminder. RootView
    /// takes it, also when the tap is what launched the app.
    var pendingLink: AppLink? = nil
    @ObservationIgnored private var reminderResponder: ReminderResponder? = nil

    init(store: MealPlanStore? = nil) {
        #if DEBUG
        self.store = store ?? DebugLaunch.seededStore() ?? .live()
        #else
        self.store = store ?? .live()
        #endif
        assistantEndpoint = AssistantEndpoint.bundled()

        // Set before launch finishes, so a reminder's button that launches the app is answered.
        let responder = ReminderResponder(store: self.store) { [weak self] link in
            self?.pendingLink = link
        }
        reminderResponder = responder
        UNUserNotificationCenter.current().delegate = responder
        MealReminderScheduler().registerActions()
    }
}
