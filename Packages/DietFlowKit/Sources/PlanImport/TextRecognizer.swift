import Foundation
import CoreGraphics
import PDFKit
import UIKit
import Vision

/// Reads the text of a photographed or scanned plan, on the device.
enum TextRecognizer {
    /// Pages of a scanned PDF read at most; a meal plan is rarely longer.
    static let pageLimit = 12

    @concurrent
    static func text(inImage data: Data) async throws -> String {
        guard let image = UIImage(data: data)?.cgImage else { throw PlanReadingError.noTextFound }
        let text = try recognize(image)
        guard text.trimmedNonEmptyText != nil else { throw PlanReadingError.noTextFound }
        return text
    }

    /// The PDF's own text when it has some; otherwise each page is rendered and read like a photo.
    @concurrent
    static func text(inPDF data: Data) async throws -> String {
        guard let document = PDFDocument(data: data) else { throw PlanReadingError.noTextFound }
        if let embedded = document.string, embedded.trimmedNonEmptyText != nil {
            return embedded
        }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, pageLimit) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2000 / max(bounds.width, bounds.height, 1)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let image = page.thumbnail(of: size, for: .mediaBox).cgImage else { continue }
            pages.append(try recognize(image))
        }
        let text = pages.joined(separator: "\n")
        guard text.trimmedNonEmptyText != nil else { throw PlanReadingError.noTextFound }
        return text
    }

    /// Lines top to bottom, words within a line left to right.
    private static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])

        let observations = (request.results ?? []).compactMap { observation -> (box: CGRect, text: String)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (observation.boundingBox, candidate.string)
        }
        // Vision measures from the bottom left. Pieces whose vertical centres are close sit on one line.
        let sorted = observations.sorted { $0.box.midY > $1.box.midY }
        var lines: [[(box: CGRect, text: String)]] = []
        for piece in sorted {
            if let last = lines.last?.first, abs(last.box.midY - piece.box.midY) < min(last.box.height, piece.box.height) / 2 {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append([piece])
            }
        }
        return lines
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}

private extension String {
    var trimmedNonEmptyText: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
