import Foundation
import Domain
import AIServices

/// What a person hands over: a dietitian's list rarely arrives in a tidier form than this.
public enum PlanSource: Sendable {
    case text(String)
    case image(Data)
    case pdf(Data)
}

public enum PlanImportError: Error, Sendable {
    /// The source was read but no meals could be found in it.
    case noMealsFound
    case assistantUnavailable
}

/// Turns a list in any of those forms into a plan the schedule can run.
public protocol PlanImporter: Sendable {
    func importPlan(from source: PlanSource) async throws -> MealPlan
}
