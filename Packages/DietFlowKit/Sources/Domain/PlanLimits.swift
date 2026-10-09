import Foundation

/// How big anything a person, a file, a Shortcut or a model hands the app may be. A plan is small;
/// these are far above any real one and exist so that a wrong file or a runaway paste is refused
/// instead of freezing the app or bloating what the widget reads.
public enum PlanLimits {
    public static let planNameLength = 80
    public static let mealTitleLength = 200
    public static let typeNameLength = 40
    public static let portionLength = 120
    public static let detailsLength = 2_000
    public static let notesLength = 2_000
    /// A year of twelve meals a day is 4,392.
    public static let mealsPerPlan = 5_000

    /// Characters of pasted, shared or recognised text read for a plan.
    public static let importTextLength = 400_000
    /// Bytes of a `.mealplan`, JSON or text file.
    public static let importFileBytes = 4 * 1024 * 1024
    /// Bytes of a photo or PDF.
    public static let importDocumentBytes = 50 * 1024 * 1024
}

extension String {
    /// One line, trimmed and cut to `limit` characters; nil when nothing is left. For names.
    func singleLine(limit: Int) -> String? {
        let joined = components(separatedBy: .newlines).joined(separator: " ")
        return joined.trimmedNonEmpty.map { String($0.prefix(limit)) }?.trimmedNonEmpty
    }

    /// Trimmed and cut to `limit` characters, line breaks kept; nil when nothing is left. For notes.
    func bounded(limit: Int) -> String? {
        trimmedNonEmpty.map { String($0.prefix(limit)) }?.trimmedNonEmpty
    }
}

extension Nutrition {
    /// Values outside what a meal can be are dropped rather than clamped: a wrong number is worse
    /// than no number.
    public func sanitized() -> Nutrition {
        func grams(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && Nutrition.gramRange.contains($0) ? $0 : nil }
        }
        let kept = Nutrition(
            calories: calories.flatMap { Nutrition.calorieRange.contains($0) ? $0 : nil },
            protein: grams(protein),
            carbohydrates: grams(carbohydrates),
            fat: grams(fat)
        )
        // An estimate stays marked as one; with nothing left there is nothing to mark.
        return kept.isEmpty ? kept : Nutrition(
            calories: kept.calories,
            protein: kept.protein,
            carbohydrates: kept.carbohydrates,
            fat: kept.fat,
            estimated: estimated
        )
    }
}

extension Meal {
    /// The meal as it may be stored, whoever wrote it: text trimmed and within `PlanLimits`,
    /// numbers within range. Nil when it has no name, because a meal with nothing to show is not
    /// a meal.
    public func sanitized() -> Meal? {
        guard let title = title.singleLine(limit: PlanLimits.mealTitleLength) else { return nil }
        var copy = self
        copy.title = title
        copy.dayIndex = min(max(dayIndex, 0), PlanSchedule.maximumLength - 1)
        copy.customTypeName = customTypeName?.singleLine(limit: PlanLimits.typeNameLength)
        copy.details = details?.bounded(limit: PlanLimits.detailsLength)
        copy.portion = portion?.singleLine(limit: PlanLimits.portionLength)
        copy.notes = notes?.bounded(limit: PlanLimits.notesLength)
        copy.nutrition = nutrition.sanitized()
        return copy
    }
}

extension MealPlan {
    /// The plan as it may be stored: every meal sanitized, meals without a name and meals repeating
    /// an id left out, and the length within what the schedule supports.
    public func sanitized() -> MealPlan {
        var copy = self
        copy.name = name.singleLine(limit: PlanLimits.planNameLength) ?? ""
        copy.schedule = PlanSchedule(
            kind: schedule.kind,
            startDay: schedule.startDay,
            length: min(schedule.length, PlanSchedule.maximumLength),
            repeats: schedule.repeats
        )
        var seen = Set<UUID>()
        copy.meals = meals
            .compactMap { $0.sanitized() }
            .filter { seen.insert($0.id).inserted }
        if copy.meals.count > PlanLimits.mealsPerPlan {
            copy.meals = Array(copy.meals.prefix(PlanLimits.mealsPerPlan))
        }
        return copy
    }
}
