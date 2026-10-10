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

/// The plan assistant's errors are the assistant's errors (`AssistantError`, in Domain, so the
/// screens that cannot see this module can word them too).
public typealias PlanAssistantError = AssistantError

/// The plan assistant: a pasted list in any state, or a few wishes, in; a plan in the interchange
/// format out. It talks to our Worker (backend/assistant), never to a model provider: the key and
/// the prompts stay server-side.
///
/// What comes back is not trusted as it is. The caller runs it through `PlanImportNormalizer` and
/// shows it for review, like every other import.
public struct PlanAssistantClient: MealAssistant {
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
        guard text.count <= Self.textLimit else { throw AssistantError.tooLong }
        return try await planPost("v1/plan/organize", OrganizeBody(text: text, language: Self.languageName()))
    }

    /// Writes a new plan.
    public func create(_ wishes: PlanWishes) async throws -> MealPlanPayload {
        let body = CreateBody(
            days: min(max(wishes.days, PlanWishes.dayRange.lowerBound), PlanWishes.dayRange.upperBound),
            mealsPerDay: min(max(wishes.mealsPerDay, PlanWishes.mealRange.lowerBound), PlanWishes.mealRange.upperBound),
            wishes: String(wishes.wishes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(PlanWishes.wishesLimit)),
            language: Self.languageName()
        )
        return try await planPost("v1/plan/create", body)
    }

    /// The language the phone is set to, in English ("Turkish"): what the prompt is told to write in.
    static func languageName(locale: Locale = .current) -> String {
        guard let code = locale.language.languageCode?.identifier else { return "" }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? ""
    }

    // MARK: Single meals

    /// Estimates what meals hold. Up to `MealAssistantLimits.questionsPerRequest` at once; the
    /// Worker splits them into several careful model calls.
    public func estimateNutrition(_ questions: [NutritionQuestion], language: String) async throws -> [String: NutritionEstimate] {
        guard !questions.isEmpty else { return [:] }
        guard questions.count <= MealAssistantLimits.questionsPerRequest else { throw AssistantError.tooLong }
        let body = NutritionBody(
            meals: questions.map { NutritionBody.Meal(id: $0.id, title: $0.title, details: $0.details, portion: $0.portion, type: $0.type.rawValue) },
            language: language
        )
        let answer: NutritionAnswer = try await post("v1/meals/nutrition", body)
        var result: [String: NutritionEstimate] = [:]
        for estimate in answer.meals where estimate.kcal > 0 {
            result[estimate.id] = NutritionEstimate(
                calories: estimate.kcal,
                protein: estimate.protein,
                carbohydrates: estimate.carbs,
                fat: estimate.fat,
                portion: estimate.portion,
                confidence: estimate.confidence.flatMap(NutritionEstimate.Confidence.init(rawValue:)) ?? .medium
            )
        }
        return result
    }

    /// Writes how to make one meal, with substitutes for its ingredients.
    public func recipe(_ request: RecipeRequest, avoiding: String?) async throws -> Recipe {
        let body = RecipeBody(
            title: request.title,
            details: request.details,
            type: request.type.rawValue,
            servings: request.servings,
            avoid: avoiding?.trimmedNonEmpty.map { String($0.prefix(200)) },
            language: request.language
        )
        let answer: RecipeAnswer = try await post("v1/meals/recipe", body)
        guard !answer.recipe.steps.isEmpty else { throw AssistantError.unavailable }
        return answer.recipe
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

    private struct NutritionBody: Encodable {
        struct Meal: Encodable {
            let id: String
            let title: String
            let details: String?
            let portion: String?
            let type: String
        }

        let meals: [Meal]
        let language: String
    }

    private struct NutritionAnswer: Decodable {
        struct Estimate: Decodable {
            let id: String
            let kcal: Int
            let protein: Double?
            let carbs: Double?
            let fat: Double?
            let portion: String?
            let confidence: String?
        }

        let meals: [Estimate]
    }

    private struct RecipeBody: Encodable {
        let title: String
        let details: String?
        let type: String
        let servings: Int
        let avoid: String?
        let language: String
    }

    private struct RecipeAnswer: Decodable {
        let recipe: Recipe
    }

    private struct Refusal: Decodable {
        let error: String
    }

    /// A plan request: an answer holding no meals is no plan.
    private func planPost(_ path: String, _ body: some Encodable) async throws -> MealPlanPayload {
        let answer: Answer = try await post(path, body)
        guard answer.plan.days.contains(where: { !$0.meals.isEmpty }) else { throw AssistantError.unavailable }
        return answer.plan
    }

    private func post<Response: Decodable>(_ path: String, _ body: some Encodable) async throws -> Response {
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
            throw AssistantError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantError.unavailable }

        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(Refusal.self, from: data))?.error ?? ""
            switch http.statusCode {
            case 413: throw AssistantError.tooLong
            case 422: throw AssistantError.noPlan
            case 429: throw code == "daily-limit" ? AssistantError.dailyLimit : AssistantError.busy
            default: throw AssistantError.unavailable
            }
        }
        guard let answer = try? JSONDecoder().decode(Response.self, from: data) else { throw AssistantError.unavailable }
        return answer
    }
}
