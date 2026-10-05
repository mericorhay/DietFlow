import Foundation
import Domain

/// What the phone holds after pairing with the MCP server (backend/mcp).
public struct SyncCredential: Codable, Hashable, Sendable {
    public let deviceID: String
    public let token: String

    public init(deviceID: String, token: String) {
        self.deviceID = deviceID
        self.token = token
    }
}

/// The phone's side of the MCP connection. Claude (or any MCP client) writes a plan to our server
/// through its tools; the phone pairs once with a short code and then pulls what was written.
/// The phone is never an MCP server itself: it cannot be reached from outside.
public protocol PlanSyncClient: Sendable {
    func pair(code: String) async throws -> SyncCredential
    /// Nil when the server has nothing newer than what the phone already has.
    func pull(using credential: SyncCredential) async throws -> MealPlan?
    func push(_ plan: MealPlan, using credential: SyncCredential) async throws
}
