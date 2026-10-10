import SwiftUI
import Analytics
import AppCore
import Domain
import PaywallFeature

/// A reason to show the DietFlow Plus screen. Identified so the same reason can be shown twice.
struct PaywallRequest: Identifiable {
    let id = UUID()
    let reason: PaywallScreen.Reason

    init(_ reason: PaywallScreen.Reason) {
        self.reason = reason
    }
}

extension AppDependencies {
    /// Turns a refused attempt into what the person sees. On the free tier that is the Plus
    /// screen, saying what was asked for. On Plus the only refusal is a used-up allowance, and
    /// there is nothing to sell: an alert says when it comes back.
    func answer(_ request: AccessRequest) {
        switch request.decision {
        case .allowed:
            break
        case .plusOnly:
            Analytics.track("paywall_shown", ["reason": "additional_plan"])
            paywall = PaywallRequest(.additionalPlan)
        case .limitReached(let limit):
            if access.tier == .plus {
                Analytics.track("allowance_used_up", ["limit": .int(limit), "point": .text(request.point.rawValue)])
                allowanceResetsAt = access.resetsAt
                allowanceUsedUp = request.point
            } else {
                let resetsAt = access.resetsAt
                let reason: PaywallScreen.Reason
                let name: String
                switch request.point {
                case .aiPlan, .additionalPlan:
                    reason = .assistantLimit(limit: limit, resetsAt: resetsAt)
                    name = "assistant_limit"
                case .aiNutrition:
                    reason = .nutritionLimit(limit: limit, resetsAt: resetsAt)
                    name = "nutrition_limit"
                case .aiRecipe:
                    reason = .cookLimit(limit: limit, resetsAt: resetsAt)
                    name = "cook_limit"
                }
                Analytics.track("paywall_shown", ["reason": .text(name)])
                paywall = PaywallRequest(reason)
            }
        }
    }

    /// Product analytics for what the meal assistant did: counts and outcomes, nothing written.
    static func track(_ event: AssistantEvent) {
        switch event {
        case .estimated(let source, let dishes, let meals):
            Analytics.track("nutrition_estimated", ["source": .text(source.rawValue), "dishes": .int(dishes), "meals": .int(meals)])
        case .estimateFailed(let source, let reason):
            Analytics.track("nutrition_estimate_failed", ["source": .text(source.rawValue), "reason": .text(reason)])
        case .recipeOpened(let cached, let steps):
            Analytics.track("recipe_opened", ["cached": .flag(cached), "steps": .int(steps)])
        case .recipeFailed(let reason):
            Analytics.track("recipe_failed", ["reason": .text(reason)])
        }
    }
}

/// Presents the Plus screen, and the "allowance used up" alert, from whatever is in front.
///
/// A sheet can only be presented by the view on top, so this is attached to the tabs and to every
/// sheet over them; `isFrontmost` says which one is on top now. All of them read the same request
/// from `AppDependencies`, so one request is shown once, wherever it was raised.
struct PlusPresenter: ViewModifier {
    @Environment(AppDependencies.self) private var dependencies
    let isFrontmost: Bool

    func body(content: Content) -> some View {
        @Bindable var dependencies = dependencies
        content
            .sheet(item: isFrontmost ? $dependencies.paywall : .constant(nil)) { request in
                PaywallScreen(reason: request.reason, showsAssistant: dependencies.assistant != nil)
            }
            .alert(
                Text("plus.allowance.title"),
                isPresented: isFrontmost
                    ? Binding(get: { dependencies.allowanceResetsAt != nil }, set: { if !$0 { dependencies.allowanceResetsAt = nil } })
                    : .constant(false),
                presenting: dependencies.allowanceResetsAt
            ) { _ in
                Button(role: .cancel) {} label: { Text("plus.allowance.ok") }
            } message: { date in
                let day = date.formatted(.dateTime.day().month(.wide))
                switch dependencies.allowanceUsedUp {
                case .aiNutrition:
                    Text(String(localized: "plus.allowance.nutrition", defaultValue: "This period's nutrition estimates are used up. They come back on \(day)."))
                case .aiRecipe:
                    Text(String(localized: "plus.allowance.recipes", defaultValue: "This period's new recipes are used up; the ones you opened stay. More come back on \(day)."))
                default:
                    Text(String(localized: "plus.allowance.message", defaultValue: "The assistant's plans for this period are used up. They come back on \(day)."))
                }
            }
    }
}
