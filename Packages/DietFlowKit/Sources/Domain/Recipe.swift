import Foundation

/// How to make one meal, written by the assistant from what the plan says the meal is: what goes
/// in, the steps, and what could go in instead. The plan's foods and amounts are kept; the recipe
/// only adds what cooking needs.
///
/// Everything in it was written by a model and is shown as written (never translated, never a
/// string key), and the app says so where it is shown.
public struct Recipe: Codable, Hashable, Sendable {
    public var title: String
    public var summary: String?
    public var servings: Int
    /// The whole thing, waiting included.
    public var minutes: Int
    public var difficulty: Difficulty
    public var ingredients: [Ingredient]
    public var steps: [Step]
    public var tips: [String]

    public init(title: String, summary: String? = nil, servings: Int = 1, minutes: Int, difficulty: Difficulty = .easy, ingredients: [Ingredient], steps: [Step], tips: [String] = []) {
        self.title = title
        self.summary = summary
        self.servings = max(1, servings)
        self.minutes = max(0, minutes)
        self.difficulty = difficulty
        self.ingredients = ingredients
        self.steps = steps
        self.tips = tips
    }

    public enum Difficulty: String, Codable, Hashable, Sendable {
        case easy
        case medium
        case hard
    }

    public struct Ingredient: Codable, Hashable, Sendable, Identifiable {
        public var name: String
        public var amount: String?
        public var substitutes: [Substitute]

        public init(name: String, amount: String? = nil, substitutes: [Substitute] = []) {
            self.name = name
            self.amount = amount
            self.substitutes = substitutes
        }

        public var id: String { name + "|" + (amount ?? "") }
    }

    /// Something that could go in instead of an ingredient, and what changes if it does.
    public struct Substitute: Codable, Hashable, Sendable, Identifiable {
        public var name: String
        public var amount: String?
        public var note: String?

        public init(name: String, amount: String? = nil, note: String? = nil) {
            self.name = name
            self.amount = amount
            self.note = note
        }

        public var id: String { name }
    }

    public struct Step: Codable, Hashable, Sendable {
        public var text: String
        /// Minutes of waiting this step involves (simmering, baking, resting); nil when it is just
        /// something to do.
        public var minutes: Int?
        public var kind: StepKind

        public init(text: String, minutes: Int? = nil, kind: StepKind = .other) {
            self.text = text
            self.minutes = minutes.flatMap { $0 > 0 ? $0 : nil }
            self.kind = kind
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            // `try?` flattens the optional, so a missing, null or unreadable value is simply nil.
            let stated: Int? = try? container.decodeIfPresent(Int.self, forKey: .minutes)
            minutes = stated.flatMap { $0 > 0 ? $0 : nil }
            let named: StepKind? = try? container.decodeIfPresent(StepKind.self, forKey: .kind)
            kind = named ?? .other
        }
    }

    /// What a step does, so it can be drawn. The same list as the assistant's server
    /// (`backend/assistant/meals.mjs`, `STEP_KINDS`); a word it does not know becomes `other`.
    public enum StepKind: String, Codable, Hashable, Sendable, CaseIterable {
        case prep, chop, mix, heat, boil, fry, bake, grill, blend, rest, cool, season, plate, other

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = StepKind(rawValue: raw) ?? .other
        }
    }

    /// Steps that involve waiting, for the timers.
    public var timedSteps: Int { steps.filter { $0.minutes != nil }.count }
}

/// What a recipe is asked for: one meal as the plan describes it, for some number of servings.
/// Two requests that are the same are the same recipe, so `cacheKey` lets one already written be
/// opened again without asking.
public struct RecipeRequest: Hashable, Sendable {
    public var title: String
    public var details: String?
    public var portion: String?
    public var type: MealType
    public var servings: Int
    /// The language the recipe is written in ("Turkish").
    public var language: String

    public init(meal: Meal, servings: Int = 1, language: String) {
        self.title = meal.title
        self.details = [meal.details, meal.portion.map { "(\($0))" }].compactMap { $0?.trimmedNonEmpty }.joined(separator: " ").trimmedNonEmpty
        self.portion = meal.portion
        self.type = meal.type
        self.servings = min(max(servings, 1), 8)
        self.language = language
    }

    /// A short, stable name for this request: the same meal, servings and language give the same
    /// key on every launch. FNV-1a, because Swift's own hashing changes from launch to launch.
    public var cacheKey: String {
        let text = [title, details ?? "", type.rawValue, String(servings), language].joined(separator: "\u{1F}")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
