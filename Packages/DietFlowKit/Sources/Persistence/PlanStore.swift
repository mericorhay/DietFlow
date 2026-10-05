import Foundation
import Domain

public enum AppGroup {
    /// Must match the App Group in DietFlow.entitlements and DietFlowWidget.entitlements.
    public static let identifier = "group.com.orhay.dietflow"
}

/// The active plan as one JSON file. The app writes it, the widget reads it; the file lives in the
/// App Group container because that is the only place both processes can reach.
public struct PlanStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Nil when the App Group is not provisioned for this build.
    public static func shared() -> PlanStore? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            .map { PlanStore(fileURL: $0.appendingPathComponent("plan.json")) }
    }

    public func load() -> MealPlan? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MealPlan.self, from: data)
    }

    public func save(_ plan: MealPlan) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(plan).write(to: fileURL, options: .atomic)
    }
}
