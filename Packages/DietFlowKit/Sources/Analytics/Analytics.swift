import Foundation

/// Which features are used and where people stop. Nothing the person wrote or eats leaves in it.
public protocol AnalyticsSink: Sendable {
    func track(_ event: String, properties: [String: String])
}

/// Used when no analytics key is in the bundle.
public struct NoAnalytics: AnalyticsSink {
    public init() {}
    public func track(_ event: String, properties: [String: String]) {}
}
