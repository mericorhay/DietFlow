import Foundation
import Observation
import Domain
import Persistence

/// A refused attempt, for the paywall to open on.
public struct AccessRequest: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let point: AccessPoint
    public let decision: AccessDecision

    public init(point: AccessPoint, decision: AccessDecision) {
        self.point = point
        self.decision = decision
    }
}

/// The tier the person is on and what they have used this period, asked before anything paid runs.
///
/// A period is what an allowance is counted over. On the free tier it is the calendar month. On
/// Plus it is the person's own billing month: someone who subscribes on the 16th has a full
/// allowance from the 16th and a fresh one on the 16th of the next month — the day the App Store
/// renews, not the 1st. A year or a lifetime purchase is counted month by month from the day it
/// was bought. `PlusEntitlement.allowanceWindow` and `BillingCycle` work the dates out; counts are
/// kept per period, so going to Plus starts a clean count and going back to free finds that
/// month's free count where it was left.
///
/// Counts live in the Keychain, which outlives deleting the app, so reinstalling does not reset an
/// allowance. The tier is `free` until the store says otherwise (`apply`).
///
/// Counted on the phone. A determined person can get round a phone-side count, so the server has
/// its own rate limit; this is what the app shows and enforces.
@MainActor
@Observable
public final class AccessModel {
    public private(set) var tier: Tier
    /// What the store last said. Nil on the free tier.
    public private(set) var entitlement: PlusEntitlement?
    /// The last refused attempt. Whoever shows the paywall reads it and sets it back to nil.
    public var request: AccessRequest?

    /// Uses by period name, then by meter key.
    private var periods: [String: [String: Int]]
    @ObservationIgnored private let keychain: KeychainStore?
    @ObservationIgnored private let defaults: UserDefaults?
    private static let entitlementKey = "plus.entitlement.v1"

    private struct Saved: Codable {
        var periods: [String: [String: Int]]
    }

    /// - Parameter persists: false for previews and seeded test states, which must neither read nor
    ///   change what the person has really used.
    public init(persists: Bool = true, entitlement: PlusEntitlement? = nil) {
        let keychain: KeychainStore? = persists ? KeychainStore(account: "usage.v1") : nil
        let defaults: UserDefaults? = persists ? .standard : nil
        var counted: [String: [String: Int]] = [:]
        if let text = keychain?.read(), let saved = try? JSONDecoder().decode(Saved.self, from: Data(text.utf8)) {
            counted = saved.periods
        }
        // What the store said last time, until it answers again: a subscriber is on Plus from the
        // first frame, and a start with no network does not look like a lapsed subscription.
        var remembered = entitlement
        if remembered == nil, let data = defaults?.data(forKey: Self.entitlementKey) {
            remembered = try? JSONDecoder().decode(PlusEntitlement.self, from: data)
        }
        self.keychain = keychain
        self.defaults = defaults
        self.periods = counted
        self.entitlement = remembered
        self.tier = remembered == nil ? .free : .plus
    }

    /// The store's answer: an entitlement while something is owned or active, nil when not.
    public func apply(_ entitlement: PlusEntitlement?) {
        self.entitlement = entitlement
        tier = entitlement == nil ? .free : .plus
        if let entitlement, let data = try? JSONEncoder().encode(entitlement) {
            defaults?.set(data, forKey: Self.entitlementKey)
        } else {
            defaults?.removeObject(forKey: Self.entitlementKey)
        }
    }

    // MARK: Periods

    /// The window the allowance in force is counted over.
    public func window(at date: Date = .now) -> BillingWindow {
        if tier == .plus, let entitlement {
            return entitlement.allowanceWindow(containing: date)
        }
        return BillingCycle.calendarMonth(containing: date)
    }

    /// When the allowance starts again.
    public var resetsAt: Date { window().end }

    private func periodKey(at date: Date = .now) -> String {
        if tier == .plus, entitlement != nil {
            return BillingCycle.windowKey(for: window(at: date))
        }
        return BillingCycle.monthKey(for: date)
    }

    /// This period's counts.
    public var ledger: UsageLedger {
        let key = periodKey()
        return UsageLedger(period: key, counts: periods[key] ?? [:])
    }

    // MARK: Asking

    public func decision(_ point: AccessPoint) -> AccessDecision {
        AccessPolicy.decide(point, tier: tier, ledger: ledger)
    }

    /// Uses left this period; nil when there is no limit.
    public func remaining(_ point: AccessPoint) -> Int? {
        AccessPolicy.remaining(point, tier: tier, ledger: ledger)
    }

    public func limit(_ point: AccessPoint) -> Int? {
        AccessPolicy.limit(point, tier: tier)
    }

    /// Whether `point` may happen now, without counting anything. Refused, it records the request
    /// for the paywall.
    @discardableResult
    public func check(_ point: AccessPoint) -> Bool {
        let decision = decision(point)
        if !decision.isAllowed { request = AccessRequest(point: point, decision: decision) }
        return decision.isAllowed
    }

    /// Whether `point` may run now; counts it when it may. Refused, it records the request for the
    /// paywall. Call `refund` if the attempt then fails on our side.
    @discardableResult
    public func use(_ point: AccessPoint) -> Bool {
        guard check(point) else { return false }
        var ledger = self.ledger
        ledger.record(point)
        save(ledger)
        return true
    }

    /// Gives a use back when the attempt failed on our side: no network, the server down.
    public func refund(_ point: AccessPoint) {
        var ledger = self.ledger
        ledger.refund(point)
        save(ledger)
    }

    /// Writes this period's counts, keeping the two most recent periods of each kind (their names
    /// sort by date), so the Keychain entry stays small.
    private func save(_ ledger: UsageLedger) {
        var kept = periods
        kept[ledger.period] = ledger.counts
        let months = Set(kept.keys.filter { !$0.hasPrefix("plus-") }.sorted().suffix(2))
        let billing = Set(kept.keys.filter { $0.hasPrefix("plus-") }.sorted().suffix(2))
        periods = kept.filter { months.contains($0.key) || billing.contains($0.key) }
        guard let data = try? JSONEncoder().encode(Saved(periods: periods)), let text = String(data: data, encoding: .utf8) else { return }
        keychain?.save(text)
    }
}
