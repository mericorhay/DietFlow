import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import Domain

/// A plan shared as a file in the interchange format, readable by Import File on another phone.
public struct PlanExport: Transferable, Sendable {
    public let plan: MealPlan

    public init(plan: MealPlan) {
        self.plan = plan
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            try MealPlanPayload(plan: export.plan).encodedJSON()
        }
        .suggestedFileName { export in
            let name = export.plan.name.trimmedNonEmpty ?? "Meal plan"
            return "\(name).json"
        }
    }
}
