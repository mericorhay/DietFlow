import Foundation
import Domain
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads free-form plan text with Apple's on-device language model, into the same payload every
/// other import path produces, for the same review. Optional: on a device without the model the
/// line reader is all there is, and nothing else in the app depends on this.
enum OnDevicePlanReader {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    static func payload(from text: String) async throws -> MealPlanPayload? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You turn a meal plan written in any language into structured data. \
            Copy meal names in their original language. \
            Use 24-hour times and leave a time empty when the plan does not give one. \
            Only give calories when the plan states them; otherwise use 0. Never estimate.
            """)
        let response = try await session.respond(to: text, generating: GeneratedPlan.self)
        let plan = response.content
        let days = plan.days.map { day in
            DayPayload(dayIndex: max(day.dayNumber, 1), meals: day.meals.map { meal in
                MealPayload(
                    time: meal.time.trimmedNonEmpty,
                    type: meal.type.trimmedNonEmpty,
                    title: meal.title.trimmedNonEmpty,
                    description: meal.details.trimmedNonEmpty,
                    calories: meal.calories > 0 ? Double(meal.calories) : nil
                )
            })
        }
        guard days.contains(where: { !$0.meals.isEmpty }) else { return nil }
        return MealPlanPayload(name: plan.name.trimmedNonEmpty, days: days)
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@Generable
struct GeneratedPlan {
    @Guide(description: "The plan's name if the text gives one, otherwise empty.")
    var name: String
    @Guide(description: "Every day of the plan in order. A plan without days is one day.")
    var days: [GeneratedDay]
}

@Generable
struct GeneratedDay {
    @Guide(description: "1 for the first day of the plan, 2 for the second, and so on.")
    var dayNumber: Int
    var meals: [GeneratedMeal]
}

@Generable
struct GeneratedMeal {
    @Guide(description: "24-hour time as HH:MM, or empty when the plan gives no time.")
    var time: String
    @Guide(description: "One of: breakfast, snack, lunch, dinner, other.")
    var type: String
    @Guide(description: "The meal's name as written in the plan.")
    var title: String
    @Guide(description: "Ingredients or portion as written, or empty.")
    var details: String
    @Guide(description: "Calories stated by the plan, or 0 when not stated.")
    var calories: Int
}
#endif
