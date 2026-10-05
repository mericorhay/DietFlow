import Foundation
import Domain

/// Where the in-app assistant lives. CI writes this file into the bundle from repository secrets;
/// without it the assistant shows as not connected instead of failing the build.
public struct AssistantEndpoint: Codable, Sendable {
    public let url: URL
    public let appToken: String

    public init(url: URL, appToken: String) {
        self.url = url
        self.appToken = appToken
    }

    public static func bundled(in bundle: Bundle = .main) -> AssistantEndpoint? {
        guard let file = bundle.url(forResource: "AssistantEndpoint", withExtension: "json"),
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(AssistantEndpoint.self, from: data)
    }
}

public struct AssistantMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// What the assistant said, and the plan it wants to put in place if it proposed one. The app
/// shows the proposal and the person accepts it; the assistant never overwrites a plan on its own.
public struct AssistantReply: Sendable {
    public var text: String
    public var proposedPlan: MealPlan?

    public init(text: String, proposedPlan: MealPlan? = nil) {
        self.text = text
        self.proposedPlan = proposedPlan
    }
}

/// The assistant goes through our Worker (backend/assistant). The provider key and the system
/// prompt stay server-side: a key compiled into an app is extractable, and a server-side prompt
/// changes without an app release.
public protocol AssistantClient: Sendable {
    func reply(to conversation: [AssistantMessage], currentPlan: MealPlan?) async throws -> AssistantReply
}
