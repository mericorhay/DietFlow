import Foundation

public enum Tier: String, Codable, Sendable {
    case free
    case plus
}

/// What the person has paid for. StoreKit sits behind this so features ask one question.
public protocol EntitlementProvider: Sendable {
    func currentTier() async -> Tier
}
