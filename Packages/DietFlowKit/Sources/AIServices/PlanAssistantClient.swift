import Foundation
import Domain

/// What the person asks for when the assistant writes a plan from nothing.
public struct PlanWishes: Hashable, Sendable {
    public static let dayRange = 1...30
    public static let mealRange = 2...6
    public static let wishesLimit = 600

    public var days: Int
    public var mealsPerDay: Int
    /// In the person's own words: how they eat, what they avoid, a calorie target.
    public var wishes: String

    public init(days: Int = 7, mealsPerDay: Int = 4, wishes: String = "") {
        self.days = days
        self.mealsPerDay = mealsPerDay
        self.wishes = wishes
    }
}

/// Why the assistant could not answer, in the terms the screen words for the person.
public enum PlanAssistantError: Error, Hashable, Sendable {
    /// No connection, or the request timed out.
    case offline
    /// The text is longer than the assistant reads.
    case tooLong
    /// The assistant read the text and found no meals in it.
    case noPlan
    /// Too many requests just now; a moment later it will work.
    case busy
    /// This phone has asked as often as one day allows.
    case dailyLimit
    /// The service is down, misconfigured, or answered with something that is not a plan.
    case unavailable
}

/// The plan assistant: a pasted list in any state, or a few wishes, in; a plan in the interchange
/// format out. It talks to our Worker (backend/assistant), never to a model provider: the key and
/// the prompts stay server-side.
///
/// What comes back is not trusted as it is. The caller runs it through `PlanImportNormalizer` and
/// shows it for review, like every other import.
public struct PlanAssistantClient: Sendable {
    /// Characters the assistant reads; longer text is refused before it is sent.
    public static let textLimit = 24_000

    public let endpoint: AssistantEndpoint
    /// A random identifier for this install, so the server can limit one phone without knowing whose it is.
    public let installID: String
    private let session: URLSession

    public init(endpoint: AssistantEndpoint, installID: String) {
        self.endpoint = endpoint
        self.installID = installID
        let configuration = URLSessionConfiguration.ephemeral
        // A 30-day plan is written in several model calls on the server; give it the time.
        configuration.timeoutIntervalForRequest = 240
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// Finds the plan in `text` and puts it in order.
    public func organize(text: String) async throws -> MealPlanPayload {
        guard text.count <= Self.textLimit else { throw PlanAssistantError.tooLong }
        return try await post("v1/plan/organize", OrganizeBody(text: text, language: Self.languageName()))
    }

    /// Writes a new plan.
    public func create(_ wishes: PlanWishes) async throws -> MealPlanPayload {
        let body = CreateBody(
            days: min(max(wishes.days, PlanWishes.dayRange.lowerBound), PlanWishes.dayRange.upperBound),
            mealsPerDay: min(max(wishes.mealsPerDay, PlanWishes.mealRange.lowerBound), PlanWishes.mealRange.upperBound),
            wishes: String(wishes.wishes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(PlanWishes.wishesLimit)),
            language: Self.languageName()
        )
        return try await post("v1/plan/create", body)
    }

    /// The language the phone is set to, in English ("Turkish"): what the prompt is told to write in.
    static func languageName(locale: Locale = .current) -> String {
        guard let code = locale.language.languageCode?.identifier else { return "" }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? ""
    }

    // MARK: Wire

    private struct OrganizeBody: Encodable {
        let text: String
        let language: String
    }

    private struct CreateBody: Encodable {
        let days: Int
        let mealsPerDay: Int
        let wishes: String
        let language: String
    }

    private struct Answer: Decodable {
        let plan: MealPlanPayload
    }

    private struct Refusal: Decodable {
        let error: String
    }

    private func post(_ path: String, _ body: some Encodable) async throws -> MealPlanPayload {
        var request = URLRequest(url: endpoint.url.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-dietflow-app")
        request.setValue(installID, forHTTPHeaderField: "x-dietflow-install")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlanAssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw PlanAssistantError.unavailable }

        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(Refusal.self, from: data))?.error ?? ""
            switch http.statusCode {
            case 413: throw PlanAssistantError.tooLong
            case 422: throw PlanAssistantError.noPlan
            case 429: throw code == "daily-limit" ? PlanAssistantError.dailyLimit : PlanAssistantError.busy
            default: throw PlanAssistantError.unavailable
            }
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data),
              answer.plan.days.contains(where: { !$0.meals.isEmpty })
        else { throw PlanAssistantError.unavailable }
        return answer.plan
    }
}
