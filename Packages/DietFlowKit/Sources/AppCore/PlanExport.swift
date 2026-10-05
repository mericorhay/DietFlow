import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import Domain

extension UTType {
    /// A plan in the interchange format: JSON with its own extension, so a shared plan opens in
    /// the app. Declared in Config/DietFlow-Info.plist.
    public static let mealPlan = UTType(exportedAs: "com.orhay.dietflow.mealplan", conformingTo: .json)
}

/// A plan shared as a file in the interchange format. On a phone with the app it opens straight
/// into Import's review; anywhere else it is plain JSON.
public struct PlanExport: Transferable, Sendable {
    public let plan: MealPlan

    public init(plan: MealPlan) {
        self.plan = plan
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .mealPlan) { export in
            try MealPlanPayload(plan: export.plan).encodedJSON()
        }
        .suggestedFileName { export in
            "\(export.fileName).mealplan"
        }
    }

    /// The plan's name, safe as a file name.
    var fileName: String {
        let fallback = "Meal Plan"
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = (plan.name.trimmedNonEmpty ?? fallback)
            .components(separatedBy: unsafe)
            .joined(separator: "-")
            // A leading dot would hide the file; a name of only dots and dashes says nothing.
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        // File systems allow 255 bytes for a name; a plan name may be 80 characters of any script.
        return String(cleaned.prefix(60)).trimmedNonEmpty ?? fallback
    }
}
