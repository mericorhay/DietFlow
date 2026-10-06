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
                Analytics.track("allowance_used_up", ["limit": .int(limit)])
                allowanceResetsAt = access.resetsAt
            } else {
                Analytics.track("paywall_shown", ["reason": "assistant_limit"])
                paywall = PaywallRequest(.assistantLimit(limit: limit, resetsAt: access.resetsAt))
            }
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
                Text(String(localized: "plus.allowance.message", defaultValue: "The assistant's plans for this period are used up. They come back on \(day)."))
            }
    }
}
