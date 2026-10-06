import Foundation
import SwiftUI
import Analytics
import AppCore
import DesignSystem
import Domain
import Purchases

/// DietFlow Plus in Settings: what the person holds, when it renews or ends, how much of the
/// assistant's allowance is left and when it comes back, and the ways to change any of it.
///
/// The dates are the App Store's own, or worked out from them (`PlusEntitlement.allowanceWindow`):
/// someone billed on the 16th reads "the 16th" here, not the 1st.
struct PlusSection: View {
    @Environment(PlusStore.self) private var plus
    @Environment(AccessModel.self) private var access
    @State private var restoreResult: RestoreResult?
    @State private var isRestoring = false
    let showsAssistant: Bool
    let showPlus: () -> Void

    var body: some View {
        Section {
            if let entitlement = access.entitlement {
                LabeledContent {
                    Text(verbatim: name(of: entitlement.kind))
                } label: {
                    Text("settings.plus.plan", bundle: .module)
                }
                if entitlement.kind != .lifetime {
                    Button {
                        Task { await plus.manageSubscription() }
                    } label: {
                        Text("settings.plus.manage", bundle: .module)
                    }
                }
            } else {
                Button(action: showPlus) {
                    HStack(spacing: AppSpacing.small) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.plus.get", bundle: .module)
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            Text(showsAssistant ? "settings.plus.get.assistant" : "settings.plus.get.plans", bundle: .module)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: AppSpacing.xSmall)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
            Button(action: restore) {
                Text("settings.plus.restore", bundle: .module)
            }
            .disabled(isRestoring)
            .alert(
                restoreResult?.title ?? Text(verbatim: ""),
                isPresented: Binding(get: { restoreResult != nil }, set: { if !$0 { restoreResult = nil } }),
                presenting: restoreResult
            ) { _ in
                Button(role: .cancel) {} label: { Text("settings.plus.notice.ok", bundle: .module) }
            } message: { result in
                result.message
            }
            Button {
                Task { await plus.redeemOfferCode() }
            } label: {
                Text("settings.plus.redeem", bundle: .module)
            }
        } header: {
            Text("settings.plus.header", bundle: .module)
        } footer: {
            Text(verbatim: footer)
        }
    }

    private func name(of kind: PlusProductKind) -> String {
        switch kind {
        case .monthly: String(localized: "settings.plus.kind.monthly", bundle: .module)
        case .yearly: String(localized: "settings.plus.kind.yearly", bundle: .module)
        case .lifetime: String(localized: "settings.plus.kind.lifetime", bundle: .module)
        }
    }

    /// The subscription's state, then the assistant's allowance, as the sentences under the section.
    private var footer: String {
        var lines: [String] = []
        if let entitlement = access.entitlement {
            lines.append(status(of: entitlement))
        } else if !showsAssistant {
            lines.append(String(localized: "settings.plus.free", bundle: .module))
        }
        if showsAssistant, let limit = access.limit(.aiPlan), let left = access.remaining(.aiPlan) {
            let date = Self.day(access.resetsAt)
            lines.append(String(localized: "settings.plus.assistant", defaultValue: "\(left) of \(limit) assistant plans left. They come back on \(date).", bundle: .module))
        }
        return lines.joined(separator: "\n")
    }

    private func status(of entitlement: PlusEntitlement) -> String {
        guard entitlement.kind != .lifetime, let end = entitlement.periodEnd else {
            return String(localized: "settings.plus.status.lifetime", bundle: .module)
        }
        let date = Self.day(end)
        switch (entitlement.isTrial, entitlement.willRenew) {
        case (true, true):
            return String(localized: "settings.plus.status.trial", defaultValue: "Free trial until \(date). It then renews, unless cancelled at least a day before.", bundle: .module)
        case (true, false):
            return String(localized: "settings.plus.status.trialEnds", defaultValue: "Free trial until \(date). It will not renew.", bundle: .module)
        case (false, true):
            return String(localized: "settings.plus.status.renews", defaultValue: "Renews on \(date).", bundle: .module)
        case (false, false):
            return String(localized: "settings.plus.status.ends", defaultValue: "Ends on \(date). It will not renew.", bundle: .module)
        }
    }

    /// "16 November 2026", in the person's own calendar and language.
    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            // Always answers, found or not: a Restore row that says nothing reads as broken.
            let found = await plus.restore()
            Analytics.track("plus_restore", ["found": .flag(found), "from": "settings"])
            restoreResult = found ? .restored : .nothing
            isRestoring = false
        }
    }
}

private enum RestoreResult: Identifiable {
    case restored
    case nothing

    var id: Self { self }

    var title: Text {
        switch self {
        case .restored: Text("settings.plus.restored.title", bundle: .module)
        case .nothing: Text("settings.plus.nothing.title", bundle: .module)
        }
    }

    var message: Text {
        switch self {
        case .restored: Text("settings.plus.restored.message", bundle: .module)
        case .nothing: Text("settings.plus.nothing.message", bundle: .module)
        }
    }
}
