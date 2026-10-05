import Foundation
import OSLog
import Domain

/// What a person hands over: a dietitian's list rarely arrives in a tidier form than one of these.
public enum PlanSource: Sendable {
    case text(String)
    /// A `.json` or `.mealplan` file.
    case file(Data)
    case image(Data)
    case pdf(Data)
}

public enum PlanReadingError: Error, Sendable {
    /// A photo or PDF held no text that could be read.
    case noTextFound
}

/// One entry point for every way a plan arrives. Whatever the source, the result is the same
/// `ImportedPlanDraft`, shown on the review screen before anything is saved. Everything runs on the
/// device: no plan text leaves the phone.
public struct MealPlanImportService: Sendable {
    private static let logger = Logger(subsystem: "com.orhay.dietflow", category: "Import")

    public init() {}

    public func importPlan(from source: PlanSource, defaults: ImportDefaults) async throws -> ImportedPlanDraft {
        switch source {
        case .text(let text):
            return try await importText(text, defaults: defaults)
        case .file(let data):
            return try await importFile(data, defaults: defaults)
        case .image(let data):
            return try await importText(try await TextRecognizer.text(inImage: data), defaults: defaults)
        case .pdf(let data):
            return try await importText(try await TextRecognizer.text(inPDF: data), defaults: defaults)
        }
    }

    /// A file: the interchange format, or a text file holding a plan.
    public func importFile(_ data: Data, defaults: ImportDefaults) async throws -> ImportedPlanDraft {
        if let payload = try? MealPlanPayload.decode(data), payload.days.contains(where: { !$0.meals.isEmpty }) {
            return try PlanImportNormalizer.draft(from: payload, defaults: defaults)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw PlanImportError.unreadable }
        return try await importText(text, defaults: defaults)
    }

    /// Pasted text: a JSON payload if it holds one, else the line reader, and when that finds
    /// nothing, Apple's on-device model where the device has it.
    public func importText(_ text: String, defaults: ImportDefaults) async throws -> ImportedPlanDraft {
        guard text.trimmedNonEmpty != nil else { throw PlanImportError.empty }

        if let payload = PastedPlanParser.parse(text, today: defaults.startDay) {
            return try PlanImportNormalizer.draft(from: payload, defaults: defaults)
        }

        if OnDevicePlanReader.isAvailable {
            do {
                if let payload = try await OnDevicePlanReader.payload(from: text) {
                    return try PlanImportNormalizer.draft(from: payload, defaults: defaults)
                }
            } catch {
                Self.logger.error("On-device reading failed: \(String(describing: error), privacy: .public)")
            }
        }
        throw PlanImportError.noMeals
    }

    /// Whether pasted text that the line reader cannot follow can still be read on this device.
    public static var canReadFreeFormText: Bool {
        OnDevicePlanReader.isAvailable
    }
}
