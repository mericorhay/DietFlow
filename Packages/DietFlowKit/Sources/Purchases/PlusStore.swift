import Foundation
import Observation
import StoreKit
import UIKit
import Domain

/// DietFlow Plus through the App Store: the three ways to buy it, the purchase, and what is held
/// right now.
///
/// The App Store is the only judge. Every launch reads the current entitlements, and a listener
/// follows renewals, refunds and expiries while the app runs, so a lapsed subscription drops back
/// to the free tier without the person doing anything, and a purchase made on another device
/// arrives on this one.
///
/// Nothing here is worded for the screen: prices come formatted by the App Store, and everything
/// else is handed over as values for the paywall and Settings to put into words.
@MainActor
@Observable
public final class PlusStore {
    public static let monthlyID = "com.orhay.dietflow.plus.monthly"
    public static let yearlyID = "com.orhay.dietflow.plus.yearly"
    public static let lifetimeID = "com.orhay.dietflow.plus.lifetime"
    /// In the order the paywall lists them.
    public static let productIDs = [monthlyID, yearlyID, lifetimeID]

    public static func kind(of productID: String) -> PlusProductKind? {
        switch productID {
        case monthlyID: .monthly
        case yearlyID: .yearly
        case lifetimeID: .lifetime
        default: nil
        }
    }

    /// One way to buy Plus, as the paywall shows it.
    public struct Offer: Identifiable, Hashable, Sendable {
        /// The product identifier.
        public let id: String
        public let kind: PlusProductKind
        /// "$3.99", in the storefront's currency and format.
        public let displayPrice: String
        /// For the yearly product, what a month of it comes to: "$2.08".
        public let pricePerMonth: String?
        /// The free trial, when App Store Connect has one and this Apple Account can still take it.
        public let trial: BillingCycle.Span?

        public init(id: String, kind: PlusProductKind, displayPrice: String, pricePerMonth: String? = nil, trial: BillingCycle.Span? = nil) {
            self.id = id
            self.kind = kind
            self.displayPrice = displayPrice
            self.pricePerMonth = pricePerMonth
            self.trial = trial
        }
    }

    public enum LoadState: Sendable {
        case idle
        case loading
        case loaded
        /// The App Store could not be reached, or returned none of the products.
        case failed
    }

    public enum Outcome: Sendable {
        case purchased
        case cancelled
        /// Waiting on something outside the app: Ask to Buy, or a bank's confirmation.
        case pending
        case failed
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var offers: [Offer] = []
    /// How much less a year costs than twelve single months, in percent. Nil until both are known.
    public private(set) var yearlySavingPercent: Int?
    public private(set) var isPurchasing = false
    public private(set) var entitlement: PlusEntitlement?

    public var isActive: Bool { entitlement != nil }

    /// Tells the rest of the app what the store says, every time it is asked.
    @ObservationIgnored public var onChange: (@MainActor (PlusEntitlement?) -> Void)?
    @ObservationIgnored private var products: [String: Product] = [:]
    @ObservationIgnored private var updates: Task<Void, Never>?
    /// A store made for previews and screenshots: it shows what it was given and asks nothing.
    @ObservationIgnored private var isStandIn = false

    public init() {}

    #if DEBUG
    /// A store that shows `offers` without the App Store, for previews and CI screenshots.
    public convenience init(standInOffers offers: [Offer], yearlySavingPercent: Int? = nil, entitlement: PlusEntitlement? = nil) {
        self.init()
        self.offers = offers
        self.yearlySavingPercent = yearlySavingPercent
        self.entitlement = entitlement
        loadState = .loaded
        isStandIn = true
    }
    #endif

    public func offer(_ kind: PlusProductKind) -> Offer? {
        offers.first { $0.kind == kind }
    }

    // MARK: Following the store

    /// Starts following purchases made anywhere on this Apple Account, loads the products and reads
    /// what is held. Safe to call more than once.
    public func start() {
        guard !isStandIn, updates == nil else { return }
        updates = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await loadProducts()
            await refresh()
        }
    }

    /// Fetches the products. Called again by the paywall's Try Again when the first attempt failed.
    public func loadProducts() async {
        guard !isStandIn, loadState != .loading else { return }
        guard products.count < Self.productIDs.count else {
            loadState = .loaded
            return
        }
        loadState = .loading
        if let loaded = try? await Product.products(for: Self.productIDs) {
            for product in loaded { products[product.id] = product }
        }
        await rebuildOffers()
        loadState = products.isEmpty ? .failed : .loaded
    }

    private func rebuildOffers() async {
        var built: [Offer] = []
        for id in Self.productIDs {
            guard let product = products[id], let kind = Self.kind(of: id) else { continue }
            var perMonth: String?
            if kind == .yearly {
                perMonth = (product.price / 12).formatted(product.priceFormatStyle)
            }
            built.append(Offer(id: id, kind: kind, displayPrice: product.displayPrice, pricePerMonth: perMonth, trial: await trial(for: product)))
        }
        offers = built

        if let monthly = products[Self.monthlyID]?.price, let yearly = products[Self.yearlyID]?.price, monthly > 0 {
            let twelveMonths = NSDecimalNumber(decimal: monthly * 12).doubleValue
            let year = NSDecimalNumber(decimal: yearly).doubleValue
            let percent = Int(((1 - year / twelveMonths) * 100).rounded())
            yearlySavingPercent = percent > 0 ? percent : nil
        } else {
            yearlySavingPercent = nil
        }
    }

    /// The introductory free trial, when there is one this Apple Account can still take.
    private func trial(for product: Product) async -> BillingCycle.Span? {
        guard let subscription = product.subscription,
              let offer = subscription.introductoryOffer,
              offer.paymentMode == .freeTrial,
              await subscription.isEligibleForIntroOffer
        else { return nil }
        let unit: BillingCycle.Unit
        switch offer.period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: return nil
        }
        return BillingCycle.Span(value: offer.period.value, unit: unit)
    }

    /// Reads what is held now: the best verified, unrevoked, unexpired DietFlow Plus transaction.
    /// A lifetime purchase outranks a year, and a year a month, should more than one be current.
    public func refresh() async {
        guard !isStandIn else { return }
        var best: (rank: Int, transaction: StoreKit.Transaction)?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let kind = Self.kind(of: transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            if let expiry = transaction.expirationDate, expiry < .now { continue }
            let rank: Int
            switch kind {
            case .monthly: rank = 1
            case .yearly: rank = 2
            case .lifetime: rank = 3
            }
            if let current = best, current.rank >= rank { continue }
            best = (rank, transaction)
        }

        var found: PlusEntitlement?
        if let transaction = best?.transaction, let kind = Self.kind(of: transaction.productID) {
            // Each renewal is a transaction of its own: its purchase date is the day this period
            // was charged, or the day the free trial began.
            found = PlusEntitlement(
                kind: kind,
                periodStart: transaction.purchaseDate,
                periodEnd: transaction.expirationDate,
                willRenew: kind == .lifetime ? false : await willAutoRenew(productID: transaction.productID),
                isTrial: transaction.offer?.type == .introductory
            )
        }
        let trialWasOnOffer = offers.contains { $0.trial != nil }
        entitlement = found
        // Taking the trial uses it up: the paywall stops offering it.
        if found != nil, trialWasOnOffer { await rebuildOffers() }
        onChange?(found)
    }

    /// Whether the subscription renews at the end of its period, or has been cancelled and stops.
    private func willAutoRenew(productID: String) async -> Bool {
        if products[productID] == nil { await loadProducts() }
        guard let statuses = try? await products[productID]?.subscription?.status else { return true }
        for status in statuses {
            guard case .verified(let info) = status.renewalInfo,
                  case .verified(let transaction) = status.transaction,
                  transaction.productID == productID
            else { continue }
            return info.willAutoRenew
        }
        return true
    }

    // MARK: Buying

    public func purchase(_ productID: String) async -> Outcome {
        guard !isStandIn, !isPurchasing else { return .failed }
        if products[productID] == nil { await loadProducts() }
        guard let product = products[productID] else { return .failed }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { return .failed }
                await transaction.finish()
                await refresh()
                return .purchased
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Asks the App Store for this Apple Account's purchases again, for a new phone or a
    /// reinstall. True when Plus was found.
    public func restore() async -> Bool {
        guard !isStandIn else { return isActive }
        try? await AppStore.sync()
        await refresh()
        return isActive
    }

    /// Apple's own sheet for an offer code.
    public func redeemOfferCode() async {
        guard !isStandIn, let scene = Self.activeScene else { return }
        try? await AppStore.presentOfferCodeRedeemSheet(in: scene)
        await refresh()
    }

    /// Apple's own sheet for changing or cancelling a subscription.
    public func manageSubscription() async {
        guard !isStandIn, let scene = Self.activeScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await refresh()
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    // MARK: Links every subscription screen must carry

    /// The app's terms, which rest on Apple's standard licence agreement and add what is the
    /// app's own: the subscription and the assistant.
    public static let termsURL = LegalLinks.terms
    public static let privacyURL = LegalLinks.privacy
}
