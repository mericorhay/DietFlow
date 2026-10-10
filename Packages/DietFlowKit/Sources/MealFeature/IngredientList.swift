import Foundation
import Domain

/// A meal's description read as the foods it lists, when it is a list: "Chicken breast · romaine ·
/// parmesan" becomes three tidy rows. A description that reads as sentences stays as it was
/// written, because breaking a dietitian's instructions into rows would change what they say.
enum IngredientList {
    /// The foods `details` lists, or nil when it does not read as a list.
    static func items(in details: String) -> [String]? {
        var parts: [String] = []
        var current = ""
        let characters = Array(details)
        for index in characters.indices {
            let character = characters[index]
            if isSeparator(at: index, in: characters) {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)

        var items: [String] = []
        for part in parts {
            guard let item = cleaned(part) else { continue }
            // "Chicken breast, 150 g": the amount belongs to the food before it.
            if isAmountOnly(item), let last = items.popLast() {
                items.append(last + ", " + item)
            } else {
                items.append(item)
            }
        }
        guard items.count >= 2, items.allSatisfy({ readsAsFood($0) }) else { return nil }
        return items
    }

    /// Middle dots, bullets, semicolons and line breaks always separate; a comma does too, unless
    /// it sits between two digits ("1,5 su bardağı" is one amount).
    private static func isSeparator(at index: Int, in characters: [Character]) -> Bool {
        switch characters[index] {
        case "·", "•", ";", "\n", "\r", "\r\n":
            return true
        case ",":
            let before = index > 0 ? characters[index - 1] : " "
            let after = index + 1 < characters.count ? characters[index + 1] : " "
            return !(before.isNumber && after.isNumber)
        default:
            return false
        }
    }

    /// The part without surrounding space, list marks or a closing full stop; nil when nothing is left.
    private static func cleaned(_ part: String) -> String? {
        var text = part.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, "-–—*•+".contains(first) {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        if text.hasSuffix(".") && !text.hasSuffix("..") {
            text.removeLast()
        }
        return text.trimmedNonEmpty
    }

    /// "150 g", "2": a number and at most a short unit, with no food of its own.
    private static func isAmountOnly(_ item: String) -> Bool {
        guard let first = item.first, first.isNumber else { return false }
        let letters = item.filter(\.isLetter).count
        return letters <= 3 && item.split(separator: " ").count <= 2
    }

    /// Short, and not a sentence: what a food on a list looks like.
    private static func readsAsFood(_ item: String) -> Bool {
        item.count <= 60
            && item.split(separator: " ").count <= 9
            && !item.contains(". ")
            && !item.contains("? ")
            && !item.contains("! ")
    }
}
