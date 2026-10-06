import Foundation
import SwiftUI
import UIKit
import Analytics
import DesignSystem
import Domain
import Purchases

/// What DietFlow Plus adds, the three ways to buy it, and the purchase.
///
/// It is shown once on first launch as the app's introduction, from Settings, and whenever
/// something only Plus does is asked for. It can always be closed: everything the free tier does
/// stays free, and the screen says so.
///
/// Every price and every date on it comes from the App Store or is worked out from what the App
/// Store said (`BillingCycle`); nothing here is a number typed into the app.
public struct PaywallScreen: View {
    public enum Reason: Hashable, Sendable {
        /// First launch: what the app is, and what Plus adds to it.
        case intro
        /// Opened on purpose, from Settings.
        case upgrade
        /// The free tier's assistant allowance for the month is used up.
        case assistantLimit(limit: Int, resetsAt: Date)
        /// A second plan was asked for on the free tier.
        case additionalPlan
    }

    @Environment(PlusStore.self) private var plus
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PlusProductKind?
    @State private var notice: PaywallNotice?
    @State private var isRestoring = false
    private let reason: Reason
    private let showsAssistant: Bool
    private let onFinished: () -> Void

    /// - Parameters:
    ///   - showsAssistant: false when this build has no assistant to offer, so it is not promised.
    ///   - onFinished: called once, when the screen closes for any reason.
    public init(reason: Reason, showsAssistant: Bool, onFinished: @escaping () -> Void = {}) {
        self.reason = reason
        self.showsAssistant = showsAssistant
        self.onFinished = onFinished
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    header
                    benefits
                    footer
                }
                .padding(.horizontal, AppSpacing.screenMargin)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.xLarge)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("paywall.close", bundle: .module))
                    .disabled(plus.isPurchasing)
                }
            }
        }
        .interactiveDismissDisabled(plus.isPurchasing)
        .task {
            await plus.loadProducts()
            selectDefault()
        }
        .onChange(of: plus.offers) { _, _ in selectDefault() }
        .alert(
            notice?.title ?? Text(verbatim: ""),
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { noticeDismissed() } }),
            presenting: notice
        ) { _ in
            Button(role: .cancel) {} label: { Text("paywall.notice.ok", bundle: .module) }
        } message: { notice in
            notice.message
        }
    }

    // MARK: What it says

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(AppColors.onBrandAccent)
                .frame(width: 48, height: 48)
                .background(AppColors.brandAccent, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .accessibilityHidden(true)
            Text("paywall.title", bundle: .module)
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: String {
        switch reason {
        case .intro, .upgrade:
            return showsAssistant
                ? String(localized: "paywall.subtitle.assistant", bundle: .module)
                : String(localized: "paywall.subtitle.plans", bundle: .module)
        case .assistantLimit(let limit, let resetsAt):
            let date = resetsAt.formatted(.dateTime.day().month(.wide))
            let plusLimit = AccessPolicy.limit(.aiPlan, tier: .plus) ?? limit
            return String(localized: "paywall.subtitle.limit", defaultValue: "You have used the \(limit) assistant plans the free plan includes this month. They come back on \(date); Plus has \(plusLimit) a month.", bundle: .module)
        case .additionalPlan:
            return String(localized: "paywall.subtitle.additionalPlan", bundle: .module)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            if showsAssistant {
                BenefitRow(symbol: "wand.and.stars", title: "paywall.benefit.organize.title", message: "paywall.benefit.organize.message")
                BenefitRow(symbol: "calendar.badge.plus", title: "paywall.benefit.create.title", message: "paywall.benefit.create.message")
            }
            BenefitRow(symbol: "square.stack", title: "paywall.benefit.plans.title", message: "paywall.benefit.plans.message")
            BenefitRow(symbol: "checkmark.circle", title: "paywall.benefit.free.title", message: "paywall.benefit.free.message", isQuiet: true)
        }
    }

    // MARK: The three ways to buy

    @ViewBuilder
    private var products: some View {
        switch plus.loadState {
        case .idle, .loading:
            HStack(spacing: AppSpacing.small) {
                ProgressView()
                Text("paywall.products.loading", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed:
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("paywall.products.failed", bundle: .module)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await plus.loadProducts() }
                } label: {
                    Text("paywall.products.retry", bundle: .module)
                }
                .buttonStyle(.bordered)
            }
        case .loaded:
            VStack(spacing: AppSpacing.xxSmall + 2) {
                ForEach(plus.offers) { offer in
                    ProductRow(
                        title: title(for: offer.kind),
                        detail: detail(for: offer),
                        badge: badge(for: offer),
                        price: offer.displayPrice,
                        isSelected: selected == offer.kind
                    ) {
                        selected = offer.kind
                    }
                }
            }
        }
    }

    private func title(for kind: PlusProductKind) -> String {
        switch kind {
        case .monthly: String(localized: "paywall.product.monthly", bundle: .module)
        case .yearly: String(localized: "paywall.product.yearly", bundle: .module)
        case .lifetime: String(localized: "paywall.product.lifetime", bundle: .module)
        }
    }

    private func detail(for offer: PlusStore.Offer) -> String {
        switch offer.kind {
        case .monthly:
            return String(localized: "paywall.product.monthly.detail", bundle: .module)
        case .yearly:
            guard let perMonth = offer.pricePerMonth else { return String(localized: "paywall.product.yearly.detail", bundle: .module) }
            return String(localized: "paywall.product.yearly.perMonth", defaultValue: "\(perMonth) a month", bundle: .module)
        case .lifetime:
            return String(localized: "paywall.product.lifetime.detail", bundle: .module)
        }
    }

    private func badge(for offer: PlusStore.Offer) -> String? {
        if let trial = offer.trial {
            let length = Self.text(for: trial)
            return String(localized: "paywall.badge.trial", defaultValue: "\(length) free", bundle: .module)
        }
        if offer.kind == .yearly, let saving = plus.yearlySavingPercent {
            let percent = (Double(saving) / 100).formatted(.percent.precision(.fractionLength(0)))
            return String(localized: "paywall.badge.saving", defaultValue: "Save \(percent)", bundle: .module)
        }
        return nil
    }

    private func selectDefault() {
        if let selected, plus.offer(selected) != nil { return }
        // The offer with a free trial first: it is the one that costs nothing to try.
        selected = plus.offers.first { $0.trial != nil }?.kind ?? plus.offers.first?.kind
    }

    // MARK: Buying

    private var selectedOffer: PlusStore.Offer? {
        selected.flatMap { plus.offer($0) }
    }

    private var purchaseBar: some View {
        VStack(spacing: AppSpacing.xSmall) {
            // The prices stay in sight with the button, whatever is scrolled above them: nobody
            // should have to go looking for what this costs.
            products
                .padding(.bottom, AppSpacing.xxSmall)
            Button(action: purchase) {
                ZStack {
                    Text(selectedOffer?.trial == nil ? "paywall.cta.continue" : "paywall.cta.trial", bundle: .module)
                        .font(.headline)
                        .opacity(plus.isPurchasing ? 0 : 1)
                    if plus.isPurchasing { ProgressView() }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.brandAccent)
            .controlSize(.large)
            .disabled(selectedOffer == nil || plus.isPurchasing)

            if let offer = selectedOffer {
                Text(verbatim: terms(for: offer))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // What every subscription screen has to say before the purchase.
                if offer.kind != .lifetime {
                    Text("paywall.autoRenew", bundle: .module)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if reason == .intro {
                Button(action: close) {
                    Text("paywall.continueFree", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: AppSpacing.minimumHitTarget)
                }
                .buttonStyle(.borderless)
                .tint(AppColors.brandAccent)
                .disabled(plus.isPurchasing)
            }
        }
        .padding(.horizontal, AppSpacing.screenMargin)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.xSmall)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// The price in a sentence, with the day the first charge would fall when there is a trial.
    private func terms(for offer: PlusStore.Offer) -> String {
        let price = offer.displayPrice
        if let trial = offer.trial, offer.kind != .lifetime {
            let length = Self.text(for: trial)
            let firstCharge = BillingCycle.date(byAdding: trial, to: .now).formatted(.dateTime.day().month(.wide))
            if offer.kind == .yearly {
                return String(localized: "paywall.terms.trialYearly", defaultValue: "\(length) free, then \(price) a year. Nothing is charged before \(firstCharge).", bundle: .module)
            }
            return String(localized: "paywall.terms.trialMonthly", defaultValue: "\(length) free, then \(price) a month. Nothing is charged before \(firstCharge).", bundle: .module)
        }
        switch offer.kind {
        case .monthly:
            return String(localized: "paywall.terms.monthly", defaultValue: "\(price) a month. Cancel anytime.", bundle: .module)
        case .yearly:
            return String(localized: "paywall.terms.yearly", defaultValue: "\(price) a year. Cancel anytime.", bundle: .module)
        case .lifetime:
            return String(localized: "paywall.terms.lifetime", defaultValue: "\(price) once. No subscription, nothing to cancel.", bundle: .module)
        }
    }

    /// "7 days", "1 month": a length of time in the person's language.
    static func text(for span: BillingCycle.Span) -> String {
        var components = DateComponents()
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        switch span.unit {
        case .day:
            components.day = span.value
            formatter.allowedUnits = [.day]
        case .week:
            components.weekOfMonth = span.value
            formatter.allowedUnits = [.weekOfMonth]
        case .month:
            components.month = span.value
            formatter.allowedUnits = [.month]
        case .year:
            components.year = span.value
            formatter.allowedUnits = [.year]
        }
        return formatter.string(from: components) ?? String(span.value)
    }

    private func purchase() {
        guard let offer = selectedOffer else { return }
        Task {
            let outcome = await plus.purchase(offer.id)
            Analytics.track("plus_purchase", [
                "product": .text(offer.kind.rawValue),
                "trial": .flag(offer.trial != nil),
                "outcome": .text(String(describing: outcome)),
            ])
            switch outcome {
            case .purchased:
                close()
            case .pending:
                notice = .pending
            case .failed:
                notice = .failed
            case .cancelled:
                break
            }
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            // Restore always answers, found or not: silence here reads as a broken button.
            let found = await plus.restore()
            Analytics.track("plus_restore", ["found": .flag(found), "from": "paywall"])
            notice = found ? .restored : .nothingToRestore
            isRestoring = false
        }
    }

    private func noticeDismissed() {
        let shown = notice
        notice = nil
        if shown == .restored { close() }
    }

    private func close() {
        dismiss()
        onFinished()
    }

    // MARK: Restore, terms, privacy

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.large) { footerLinks }
            VStack(alignment: .leading, spacing: AppSpacing.small) { footerLinks }
        }
        .font(.footnote)
        .tint(.secondary)
    }

    @ViewBuilder
    private var footerLinks: some View {
        Button(action: restore) {
            Text("paywall.restore", bundle: .module)
        }
        .disabled(isRestoring || plus.isPurchasing)
        Link(destination: PlusStore.termsURL) {
            Text("paywall.terms", bundle: .module)
        }
        Link(destination: PlusStore.privacyURL) {
            Text("paywall.privacy", bundle: .module)
        }
    }
}

/// What the store said back, worded for an alert.
enum PaywallNotice: Identifiable, Hashable {
    case pending
    case failed
    case restored
    case nothingToRestore

    var id: Self { self }

    var title: Text {
        switch self {
        case .pending: Text("paywall.notice.pending.title", bundle: .module)
        case .failed: Text("paywall.notice.failed.title", bundle: .module)
        case .restored: Text("paywall.notice.restored.title", bundle: .module)
        case .nothingToRestore: Text("paywall.notice.nothing.title", bundle: .module)
        }
    }

    var message: Text {
        switch self {
        case .pending: Text("paywall.notice.pending.message", bundle: .module)
        case .failed: Text("paywall.notice.failed.message", bundle: .module)
        case .restored: Text("paywall.notice.restored.message", bundle: .module)
        case .nothingToRestore: Text("paywall.notice.nothing.message", bundle: .module)
        }
    }
}

private struct BenefitRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var isQuiet = false

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isQuiet ? Color.secondary : AppColors.brandAccent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title, bundle: .module)
                    .font(.headline)
                Text(message, bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One way to buy, as a row that can be chosen.
private struct ProductRow: View {
    let title: String
    let detail: String
    let badge: String?
    let price: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppSpacing.small) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppColors.brandAccent : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppSpacing.xSmall) { heading }
                        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) { heading }
                    }
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AppSpacing.xSmall)
                Text(verbatim: price)
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppColors.brandWash : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .strokeBorder(isSelected ? AppColors.brandAccent : Color.clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var heading: some View {
        Text(verbatim: title)
            .font(.subheadline.weight(.semibold))
        if let badge {
            Text(verbatim: badge)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.onBrandAccent)
                .padding(.horizontal, AppSpacing.xSmall)
                .padding(.vertical, 2)
                .background(AppColors.brandAccent, in: Capsule())
        }
    }
}
