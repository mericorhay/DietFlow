import Foundation
import Observation
import UserNotifications
import AIServices
import Analytics
import AppCore
import Domain
import MealReminders
import Purchases

/// The composition root. Modules never reach for each other; whatever a screen needs is built here
/// and handed to it, which is also what lets previews and tests swap the real thing out.
@Observable
final class AppDependencies {
    /// Every plan change goes through here: the screens, the intents and imports alike.
    let store: MealPlanStore
    /// DietFlow Plus as the App Store sees it.
    let plus: PlusStore
    /// The tier in force and what has been used of its allowances. Follows `plus`.
    let access: AccessModel
    /// The plan assistant, or nil when this build was made without its address: the app then
    /// leaves the assistant out rather than offer something that cannot work.
    let assistant: PlanAssistantClient?
    let analytics: any AnalyticsSink = NoAnalytics()
    /// True for the real app; false for a state seeded by launch arguments, where the first-launch
    /// Plus screen would cover what is being checked.
    let showsPlusOnFirstLaunch: Bool
    /// A place to open that arrived from outside the views, such as a tapped reminder. RootView
    /// takes it, also when the tap is what launched the app.
    var pendingLink: AppLink? = nil
    /// The Plus screen, waiting to be shown by whatever is in front (see `PlusPresenter`).
    var paywall: PaywallRequest? = nil
    /// Set when someone on Plus has used a period's allowance: the day it comes back.
    var allowanceResetsAt: Date? = nil
    @ObservationIgnored private var reminderResponder: ReminderResponder? = nil

    init(store: MealPlanStore? = nil) {
        let seeded: MealPlanStore?
        #if DEBUG
        seeded = store ?? DebugLaunch.seededStore()
        #else
        seeded = store
        #endif
        self.store = seeded ?? .live()
        showsPlusOnFirstLaunch = seeded == nil

        let access: AccessModel
        let plus: PlusStore
        if seeded == nil {
            access = AccessModel()
            plus = PlusStore()
            // The store is the only judge of the tier; this is the one place its answer lands.
            plus.onChange = { entitlement in access.apply(entitlement) }
            assistant = AssistantEndpoint.bundled().map { PlanAssistantClient(endpoint: $0, installID: Self.installID()) }
        } else {
            #if DEBUG
            let entitlement = DebugLaunch.seededEntitlement()
            access = AccessModel(persists: false, entitlement: entitlement)
            plus = DebugLaunch.standInStore(entitlement: entitlement)
            assistant = DebugLaunch.standInAssistant()
            #else
            access = AccessModel(persists: false)
            plus = PlusStore()
            assistant = nil
            #endif
        }
        self.access = access
        self.plus = plus
        // Asks the App Store what is held, and follows it from here on. A stand-in store ignores this.
        plus.start()

        // Set before launch finishes, so a reminder's button that launches the app is answered.
        let responder = ReminderResponder(store: self.store) { [weak self] link in
            self?.pendingLink = link
        }
        reminderResponder = responder
        UNUserNotificationCenter.current().delegate = responder
        MealReminderScheduler().registerActions()
    }

    /// A random identifier made on first launch. It lets the assistant's server limit one phone
    /// without knowing anything about whose it is; it is not tied to an account or a device id.
    private static func installID() -> String {
        let key = "install.id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
