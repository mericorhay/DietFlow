import Foundation
import Observation
import AIServices
import Analytics
import Domain
import MealReminders
import Persistence
import WidgetKit

/// The composition root. Modules never reach for each other; whatever a screen needs is built here
/// and handed to it, which is also what lets previews and tests swap the real thing out.
@Observable
final class AppDependencies {
    let planStore: PlanStore?
    let reminders = MealReminderScheduler()
    let assistantEndpoint: AssistantEndpoint?
    let analytics: any AnalyticsSink = NoAnalytics()

    private(set) var plan: MealPlan?

    init() {
        planStore = PlanStore.shared()
        assistantEndpoint = AssistantEndpoint.bundled()
        plan = planStore?.load()
    }

    /// The one way a plan becomes the active plan, whether it was typed, imported, proposed by the
    /// assistant or pulled from the MCP server: store it, then bring the widget and reminders along.
    func activate(_ newPlan: MealPlan) throws {
        try planStore?.save(newPlan)
        plan = newPlan
        WidgetCenter.shared.reloadAllTimelines()
        reminders.reschedule(MealSchedule(plan: newPlan).upcoming(after: .now, days: 7))
    }
}
