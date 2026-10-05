import Foundation
import Observation
import AIServices
import Analytics
import AppCore

/// The composition root. Modules never reach for each other; whatever a screen needs is built here
/// and handed to it, which is also what lets previews and tests swap the real thing out.
@Observable
final class AppDependencies {
    /// Every plan change goes through here: the screens, the intents and imports alike.
    let store: MealPlanStore
    /// Kept for the assistant module, which no screen shows at the moment.
    let assistantEndpoint: AssistantEndpoint?
    let analytics: any AnalyticsSink = NoAnalytics()

    init(store: MealPlanStore = .live()) {
        self.store = store
        assistantEndpoint = AssistantEndpoint.bundled()
    }
}
