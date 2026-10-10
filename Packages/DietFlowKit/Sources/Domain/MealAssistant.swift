import Foundation

/// Why the assistant could not answer, in the terms a screen words for the person. The same for
/// every request: a plan, an estimate or a recipe.
public enum AssistantError: Error, Hashable, Sendable {
    /// No connection, or the request timed out.
    case offline
    /// More than the assistant reads in one request.
    case tooLong
    /// The assistant read what it was given and found nothing it could use (no meals in a list).
    case noPlan
    /// Too many requests just now; a moment later it will work.
    case busy
    /// This phone has asked as often as one day allows.
    case dailyLimit
    /// The service is down, misconfigured, or answered with something that could not be read.
    case unavailable
}

/// One meal as the assistant is asked about it: an id its answer is matched by, and what the plan
/// says the meal is. Nothing else about the person or the plan goes with it.
public struct NutritionQuestion: Hashable, Sendable {
    public var id: String
    public var title: String
    public var details: String?
    public var portion: String?
    public var type: MealType

    public init(id: String, meal: Meal) {
        self.id = id
        title = meal.title
        details = meal.details?.trimmedNonEmpty
        portion = meal.portion?.trimmedNonEmpty
        type = meal.type
    }
}

/// What the assistant does for single meals. Our Worker answers it (`AIServices`); the app reaches
/// it through `MealAssistantModel`, which asks for consent, counts the allowance and keeps recipes.
public protocol MealAssistant: Sendable {
    /// Estimates for at most `MealAssistantLimits.questionsPerRequest` meals, by question id. A meal
    /// the assistant could not estimate is missing from the answer.
    func estimateNutrition(_ questions: [NutritionQuestion], language: String) async throws -> [String: NutritionEstimate]
    /// How to make one meal. `avoiding` is what the person does not eat, in their words.
    func recipe(_ request: RecipeRequest, avoiding: String?) async throws -> Recipe
}

public enum MealAssistantLimits {
    /// Meals in one estimate request; the Worker refuses more.
    public static let questionsPerRequest = 60
    /// Distinct dishes one estimate of a whole plan asks about. A 30-day plan written by the
    /// assistant has at most 180 meals; a repeating dietitian plan far fewer distinct ones.
    public static let dishesPerPlan = 240
}

/// The questions an estimate for some meals asks, and how the answers go back to the meals: one
/// question per dish, so a breakfast that repeats every day is asked about once, and none for a
/// meal that already has figures of its own.
public struct NutritionRequestPlan: Sendable {
    /// Requests to send, each within the Worker's limit, in plan order.
    public let batches: [[NutritionQuestion]]
    /// Meals left out because the plan has more distinct dishes than one estimate covers.
    public let skippedDishes: Int
    private let mealsByQuestion: [String: [UUID]]

    public init(meals: [Meal], batchSize: Int = MealAssistantLimits.questionsPerRequest, dishLimit: Int = MealAssistantLimits.dishesPerPlan) {
        var questions: [NutritionQuestion] = []
        var idByDish: [String: String] = [:]
        var mealsByQuestion: [String: [UUID]] = [:]
        var skipped = Set<String>()
        let ordered = meals.filter(\.lacksNutrition).sorted { ($0.dayIndex, $0.time) < ($1.dayIndex, $1.time) }
        for meal in ordered {
            let dish = meal.dishKey
            if let id = idByDish[dish] {
                mealsByQuestion[id, default: []].append(meal.id)
                continue
            }
            guard questions.count < dishLimit else {
                skipped.insert(dish)
                continue
            }
            // Short ids: they are all the answer needs to be matched by, and say nothing.
            let id = "d\(questions.count + 1)"
            idByDish[dish] = id
            mealsByQuestion[id] = [meal.id]
            questions.append(NutritionQuestion(id: id, meal: meal))
        }
        let size = max(1, batchSize)
        batches = stride(from: 0, to: questions.count, by: size).map { Array(questions[$0..<min($0 + size, questions.count)]) }
        skippedDishes = skipped.count
        self.mealsByQuestion = mealsByQuestion
    }

    /// Distinct dishes asked about.
    public var dishCount: Int { batches.reduce(0) { $0 + $1.count } }

    public var isEmpty: Bool { batches.isEmpty }

    /// Each answer given to every meal that is the same dish.
    public func estimates(from answers: [String: NutritionEstimate]) -> [UUID: NutritionEstimate] {
        var result: [UUID: NutritionEstimate] = [:]
        for (id, estimate) in answers {
            for meal in mealsByQuestion[id] ?? [] { result[meal] = estimate }
        }
        return result
    }
}

extension MealType {
    /// The SF Symbol that stands for this sitting wherever a meal is drawn: the widget, Today, the
    /// plan. Always beside its name, never instead of it.
    public var symbolName: String {
        switch self {
        case .breakfast: "sunrise"
        case .snack: "carrot"
        case .lunch: "fork.knife"
        case .dinner: "moon.stars"
        case .other: "circle.grid.2x2"
        }
    }
}

extension AppLanguage {
    /// The language the assistant writes in, named in English ("Turkish"): what its prompts are told.
    /// The app's own language, so a recipe reads like the screen around it.
    public static func assistantLanguageName(bundle: Bundle = .main) -> String {
        let code = Locale(identifier: currentCode(bundle: bundle)).language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }
}
