import Foundation

/// Reads the ways people and models write a clock time.
public enum TimeParser {
    /// "14:00", "14.00", "1400", "14h", "14h30", "2 PM", "2:30pm", "7 a.m.", "08:00:00".
    public static func parse(_ text: String) -> TimeOfDay? {
        let lowered = text.lowercased()
            .replacingOccurrences(of: ".m.", with: "m")
            .replacingOccurrences(of: "a.m", with: "am")
            .replacingOccurrences(of: "p.m", with: "pm")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = lowered.firstMatch(of: pattern) else { return nil }

        guard var hour = Int(match.output.hour) else { return nil }
        var minute = match.output.minute.flatMap { Int($0) } ?? 0

        // "1400"
        if match.output.minute == nil, match.output.hour.count >= 3, let packed = Int(match.output.hour) {
            hour = packed / 100
            minute = packed % 100
        }

        if let meridiem = match.output.meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "am" { hour = hour == 12 ? 0 : hour }
            if meridiem == "pm" { hour = hour == 12 ? 12 : hour + 12 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return TimeOfDay(hour: hour, minute: minute)
    }

    nonisolated(unsafe) private static let pattern = /^(?<hour>\d{1,4})(?:\s*[:.h]\s*(?<minute>\d{2})?)?(?::\d{2})?\s*(?<meridiem>am|pm)?$/
}

/// Reads meal names in the languages the app ships in, plus the common ones a pasted plan uses.
public enum MealTypeParser {
    private static let synonyms: [(MealType, [String])] = [
        (.breakfast, ["breakfast", "brekkie", "morning meal", "kahvalti", "sabah", "desayuno", "fruhstuck", "petit dejeuner", "petit-dejeuner", "colazione", "cafe da manha", "ontbijt", "sniadanie"]),
        (.lunch, ["lunch", "midday meal", "ogle yemegi", "ogle", "oglen", "almuerzo", "comida", "mittagessen", "dejeuner", "pranzo", "almoco", "lunchen", "obiad"]),
        (.dinner, ["dinner", "supper", "evening meal", "aksam yemegi", "aksam", "cena", "abendessen", "diner", "jantar", "avondeten", "kolacja"]),
        (.snack, ["snack", "snacks", "ara ogun", "ara", "merienda", "tentempie", "colacion", "zwischenmahlzeit", "collation", "gouter", "spuntino", "merenda", "lanche", "tussendoortje", "przekaska"]),
    ]

    /// The type `text` is exactly the name of — "Lunch", "Öğle yemeği" — or nil.
    public static func exactType(of text: String) -> MealType? {
        let folded = fold(text)
        guard !folded.isEmpty else { return nil }
        for (type, words) in synonyms where words.contains(folded) {
            return type
        }
        if ["other", "diger", "otro", "otra"].contains(folded) { return .other }
        return nil
    }

    /// The type `text` names, also when the name is followed or preceded by more words
    /// ("Morning snack", "Lunch (light)"), or nil.
    public static func type(of text: String) -> MealType? {
        if let exact = exactType(of: text) { return exact }
        let folded = fold(text)
        guard !folded.isEmpty else { return nil }
        // "Morning snack", "Lunch (light)", "Öğle yemeği:" — a known word at the start.
        for (type, words) in synonyms {
            for word in words where folded.hasPrefix(word + " ") || folded.hasSuffix(" " + word) {
                return type
            }
        }
        if ["other", "diger", "otro", "otra"].contains(folded) { return .other }
        return nil
    }

    /// A type for an imported meal: the named one, or `.other` keeping the plan's own word
    /// ("Pre-workout"), or — when nothing is named — a guess from the time of day.
    static func resolve(_ text: String?, time: TimeOfDay?) -> (MealType, String?) {
        if let text = text?.trimmedNonEmpty {
            if let known = type(of: text) { return (known, nil) }
            return (.other, String(text.prefix(40)).capitalizedFirstLetter)
        }
        guard let time else { return (.other, nil) }
        return (MealType.suggested(for: time), nil)
    }

    /// Lowercased, accents and Turkish dotted/dotless i folded away, punctuation trimmed.
    static func fold(_ text: String) -> String {
        text
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted.union(.whitespacesAndNewlines))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
