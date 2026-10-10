import Foundation

/// What the assistant worked out one meal holds: one serving as the meal describes it.
public struct NutritionEstimate: Hashable, Sendable {
    public enum Confidence: String, Hashable, Sendable {
        /// The meal gave its foods and amounts.
        case high
        /// A usual portion of a clear dish was assumed.
        case medium
        /// The description was too vague to know.
        case low
    }

    public var calories: Int
    public var protein: Double?
    public var carbohydrates: Double?
    public var fat: Double?
    /// The serving the estimate assumed, in the person's language ("1 bowl (about 300 g)").
    public var portion: String?
    public var confidence: Confidence

    public init(calories: Int, protein: Double? = nil, carbohydrates: Double? = nil, fat: Double? = nil, portion: String? = nil, confidence: Confidence = .medium) {
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
        self.portion = portion
        self.confidence = confidence
    }

    /// The figures as stored on a meal: marked as an estimate.
    public var nutrition: Nutrition {
        Nutrition(calories: calories, protein: protein, carbohydrates: carbohydrates, fat: fat, estimated: true).sanitized()
    }
}

extension Meal {
    /// The plan gives none of the figures, so an estimate would add something rather than replace
    /// what the plan or the person wrote.
    public var lacksNutrition: Bool {
        nutrition.isEmpty
    }

    /// The meal with `estimate` filled in where it has nothing of its own. Figures the plan gave and
    /// a portion it named are never overwritten.
    public func filling(_ estimate: NutritionEstimate) -> Meal {
        guard lacksNutrition else { return self }
        var copy = self
        copy.nutrition = estimate.nutrition
        if copy.portion?.trimmedNonEmpty == nil { copy.portion = estimate.portion }
        return copy
    }

    /// Meals that are the same dish as far as an estimate or a recipe is concerned share this.
    public var dishKey: String {
        [title, details ?? "", portion ?? ""]
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")
    }
}
