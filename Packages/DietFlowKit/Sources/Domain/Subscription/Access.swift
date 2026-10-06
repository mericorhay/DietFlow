import Foundation

/// What the person is on. `free` until the App Store says otherwise.
public enum Tier: String, Codable, Hashable, Sendable {
    case free
    case plus
}

/// Something only DietFlow Plus opens, or that both tiers may do a limited number of times.
/// This and `AccessPolicy` are the whole commercial model: change what is paid for here and
/// nowhere else.
public enum AccessPoint: String, Hashable, CaseIterable, Sendable {
    /// One request to the plan assistant: organising a list, or writing a new plan. Each one is a
    /// call to a model we pay for, so it is counted on both tiers.
    case aiPlan
    /// Keeping a second plan beside the first.
    case additionalPlan

    /// The name its uses are counted under, for the points that are counted.
    public var meterKey: String? {
        switch self {
        case .aiPlan: rawValue
        case .additionalPlan: nil
        }
    }
}

public enum AccessDecision: Hashable, Sendable {
    case allowed
    case plusOnly
    /// The period's allowance is used up. `limit` is what it was.
    case limitReached(limit: Int)

    public var isAllowed: Bool { self == .allowed }
}

/// Uses in one period, by meter key. A period is a calendar month on the free tier and the
/// person's own billing month on Plus (see `BillingCycle`); `period` is its name.
public struct UsageLedger: Codable, Hashable, Sendable {
    public var period: String
    public var counts: [String: Int]

    public init(period: String, counts: [String: Int] = [:]) {
        self.period = period
        self.counts = counts
    }

    public func used(_ point: AccessPoint) -> Int {
        point.meterKey.map { counts[$0] ?? 0 } ?? 0
    }

    public mutating func record(_ point: AccessPoint) {
        guard let key = point.meterKey else { return }
        counts[key, default: 0] += 1
    }

    /// Gives a use back, for an attempt that failed on our side.
    public mutating func refund(_ point: AccessPoint) {
        guard let key = point.meterKey, let count = counts[key], count > 0 else { return }
        counts[key] = count - 1
    }
}

public enum AccessPolicy {
    public static func isPlusOnly(_ point: AccessPoint) -> Bool {
        switch point {
        case .aiPlan: false
        case .additionalPlan: true
        }
    }

    /// Uses per period, or nil for no limit. The free tier gets a taste of the assistant; Plus gets
    /// far more than a person plans in a month, and still a number, because each use costs money.
    public static func limit(_ point: AccessPoint, tier: Tier) -> Int? {
        switch (point, tier) {
        case (.aiPlan, .free): 2
        case (.aiPlan, .plus): 60
        case (.additionalPlan, _): nil
        }
    }

    public static func decide(_ point: AccessPoint, tier: Tier, ledger: UsageLedger) -> AccessDecision {
        if tier == .free, isPlusOnly(point) { return .plusOnly }
        if let limit = limit(point, tier: tier), ledger.used(point) >= limit {
            return .limitReached(limit: limit)
        }
        return .allowed
    }

    /// Uses left this period; nil when there is no limit.
    public static func remaining(_ point: AccessPoint, tier: Tier, ledger: UsageLedger) -> Int? {
        if tier == .free, isPlusOnly(point) { return 0 }
        guard let limit = limit(point, tier: tier) else { return nil }
        return max(0, limit - ledger.used(point))
    }
}
