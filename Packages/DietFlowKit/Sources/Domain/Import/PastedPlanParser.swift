import Foundation

/// Reads a plan pasted as text — from ChatGPT, Claude, a dietitian's message or a note — into a
/// payload for review. It understands the shapes plans are usually written in:
///
///     14-Day Keto Plan
///     Day 1
///     10:00 Breakfast: Halloumi, olives and avocado salad (430 kcal)
///     14:00 Lunch - Grilled Chicken Caesar Salad
///     Dinner (19:00): Steak salad
///
///     2. Gün
///     Kahvaltı:
///     - 2 yumurta
///     - Avokado
///
/// A JSON payload anywhere in the text (a model's fenced code block) wins over all of that.
/// Nothing is invented: a meal without a time is passed on without one, and the review screen
/// says so.
public enum PastedPlanParser {
    public static func parse(_ text: String, today: CalendarDay = .today()) -> MealPlanPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let payload = embeddedJSON(in: trimmed), payload.days.contains(where: { !$0.meals.isEmpty }) {
            return payload
        }

        var reader = LineReader()
        for line in trimmed.components(separatedBy: .newlines) {
            reader.read(line)
        }
        return reader.payload(today: today)
    }

    /// A JSON object somewhere in the text, as models often wrap it in prose or a code fence.
    static func embeddedJSON(in text: String) -> MealPlanPayload? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        let candidate = String(text[open...close])
        return try? MealPlanPayload.decode(Data(candidate.utf8))
    }
}

// MARK: - Line by line

private struct LineReader {
    private var name: String?
    private var dayOrder: [Int] = []
    private var mealsByDay: [Int: [MealPayload]] = [:]
    private var currentDay = 1
    private var sawDayHeader = false
    private var sawWeekdayHeader = false
    /// A "Breakfast:" line whose items follow on the next lines.
    private var group: (type: String, time: String?, items: [String])?
    /// The previous line was a meal, so a bullet straight after it adds detail to it.
    private var lastLineWasMeal = false

    mutating func read(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else {
            lastLineWasMeal = false
            return
        }
        let isBullet = line.first.map { "-*•–—·>".contains($0) } ?? false
        let cleaned = Self.stripMarkup(line)
        guard !cleaned.isEmpty else { return }

        if let header = Self.dayHeader(in: cleaned) {
            closeGroup()
            sawDayHeader = true
            if header.isWeekday { sawWeekdayHeader = true }
            currentDay = header.number
            lastLineWasMeal = false
            if let rest = header.rest, !rest.isEmpty { readMeal(rest, isBullet: false) }
            return
        }
        readMeal(cleaned, isBullet: isBullet)
    }

    private mutating func readMeal(_ text: String, isBullet: Bool) {
        var rest = text
        var time = Self.takeLeadingTime(&rest)
        var typeText: String?

        // "Breakfast: …", "Breakfast (08:00): …", "Lunch - …", "Breakfast 08:00 - …"
        if let separated = Self.splitAtSeparator(rest) {
            var head = separated.head
            let inner = Self.takeParenthesizedTime(&head)
            let trailing = Self.takeTrailingTime(&head)
            if MealTypeParser.type(of: head) != nil {
                typeText = head
                rest = separated.tail
                time = time ?? inner ?? trailing
            }
        } else {
            var whole = rest
            let inner = Self.takeParenthesizedTime(&whole)
            let trailing = Self.takeTrailingTime(&whole)
            if MealTypeParser.exactType(of: whole) != nil {
                // A type on its own: its items follow on the next lines.
                closeGroup()
                group = (whole, time ?? inner ?? trailing, [])
                lastLineWasMeal = false
                return
            }
            if let split = Self.splitLeadingTypeWord(rest) {
                typeText = split.type
                var remainder = split.title
                time = time ?? Self.takeLeadingTime(&remainder)
                rest = remainder
            }
        }

        if typeText == nil, time == nil {
            // Neither a time nor a type: an item of the open group, a detail of the meal above,
            // the plan's name, or prose to ignore.
            if group != nil {
                group?.items.append(text)
            } else if isBullet, lastLineWasMeal {
                appendDetail(text)
            } else if name == nil, mealsByDay.isEmpty, !sawDayHeader, Self.looksLikePlanName(text) {
                name = text
            }
            return
        }

        closeGroup()
        let (rawTitle, nutrition) = Self.extractNutrition(from: rest)
        guard let title = rawTitle.trimmedNonEmpty else {
            // "Lunch (13:00)" with the items below.
            group = (typeText ?? "", time, [])
            lastLineWasMeal = false
            return
        }
        add(MealPayload(time: time, type: typeText, title: title, calories: nutrition.calories, protein: nutrition.protein, carbs: nutrition.carbs, fat: nutrition.fat))
        lastLineWasMeal = true
    }

    private mutating func closeGroup() {
        guard let open = group else { return }
        group = nil
        let items = open.items.map { Self.stripMarkup($0) }.compactMap(\.trimmedNonEmpty)
        guard !items.isEmpty else { return }
        let joined = items.joined(separator: ", ")
        let (title, nutrition) = Self.extractNutrition(from: joined)
        add(MealPayload(time: open.time, type: open.type.trimmedNonEmpty, title: String((title.trimmedNonEmpty ?? joined).prefix(200)), calories: nutrition.calories, protein: nutrition.protein, carbs: nutrition.carbs, fat: nutrition.fat))
    }

    private mutating func add(_ meal: MealPayload) {
        if mealsByDay[currentDay] == nil { dayOrder.append(currentDay) }
        mealsByDay[currentDay, default: []].append(meal)
    }

    private mutating func appendDetail(_ text: String) {
        guard var meals = mealsByDay[currentDay], var last = meals.popLast() else { return }
        let detail = Self.stripMarkup(text)
        last.description = [last.description, detail].compactMap { $0?.trimmedNonEmpty }.joined(separator: ", ")
        meals.append(last)
        mealsByDay[currentDay] = meals
    }

    mutating func payload(today: CalendarDay) -> MealPlanPayload? {
        closeGroup()
        let days = dayOrder.map { DayPayload(dayIndex: $0, meals: mealsByDay[$0] ?? []) }
        guard days.contains(where: { !$0.meals.isEmpty }) else { return nil }

        if sawWeekdayHeader {
            // Monday is day 1, so the plan starts on the Monday of this week and repeats weekly.
            let back = (today.weekday + 5) % 7
            return MealPlanPayload(name: name, startDate: today.adding(days: -back).description, kind: PlanKind.cycle.rawValue, repeatCycle: RepeatCyclePayload(lengthInDays: 7, repeats: true), days: days)
        }
        if !sawDayHeader {
            // One day of meals: the same every day.
            return MealPlanPayload(name: name, kind: PlanKind.cycle.rawValue, repeatCycle: RepeatCyclePayload(lengthInDays: 1, repeats: true), days: days)
        }
        return MealPlanPayload(name: name, kind: PlanKind.cycle.rawValue, days: days)
    }

    // MARK: Pieces

    /// Drops list bullets, Markdown emphasis and heading marks.
    static func stripMarkup(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        while let first = text.first, "#-*•–—·>".contains(first) {
            text.removeFirst()
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    struct DayHeader {
        var number: Int
        var isWeekday: Bool
        var rest: String?
    }

    static let weekdays: [[String]] = [
        ["monday", "pazartesi", "lunes"],
        ["tuesday", "sali", "martes"],
        ["wednesday", "carsamba", "miercoles"],
        ["thursday", "persembe", "jueves"],
        ["friday", "cuma", "viernes"],
        ["saturday", "cumartesi", "sabado"],
        ["sunday", "pazar", "domingo"],
    ]

    static func dayHeader(in line: String) -> DayHeader? {
        let folded = MealTypeParser.fold(line)

        // "Day 3", "Gün 3", "Día 3", with whatever follows: "Day 3 – Wednesday".
        if let match = folded.firstMatch(of: /^(?:day|gun|dia|tag|jour|giorno|dag|dzien)\s*(\d{1,3})(?<rest>.*)$/),
           let number = Int(match.output.1), number >= 1 {
            return DayHeader(number: number, isWeekday: false, rest: remainder(of: line, afterFolded: match.output.rest))
        }
        // "3. Gün", "3rd day", "3 day".
        if let match = folded.firstMatch(of: /^(\d{1,3})\s*(?:\.|\)|st|nd|rd|th)?\s*(?:day|gun|dia|tag|jour|giorno|dag)\b(?<rest>.*)$/),
           let number = Int(match.output.1), number >= 1 {
            return DayHeader(number: number, isWeekday: false, rest: remainder(of: line, afterFolded: match.output.rest))
        }
        // "Monday", "Pazartesi:", "Lunes (5 Oct)": a weekday standing alone.
        for (index, names) in weekdays.enumerated() {
            for name in names where folded == name || folded.hasPrefix(name + " ") {
                let tail = folded.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                let looksLikeMeal = tail.contains(":") && tail.count > 12
                if !looksLikeMeal, takeLeadingTimeText(tail) == nil {
                    return DayHeader(number: index + 1, isWeekday: true, rest: nil)
                }
            }
        }
        return nil
    }

    /// The original-case text after a header, matched by length from the end of the folded form.
    private static func remainder(of line: String, afterFolded rest: Substring) -> String? {
        let tail = rest.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—.,|·").union(.whitespaces))
        guard tail.count >= 3 else { return nil }
        // Only meals are worth reading from the rest of a header line; a weekday name is not.
        guard takeLeadingTimeText(tail) != nil || MealTypeParser.type(of: String(tail.split(separator: ":").first ?? "")) != nil else { return nil }
        return String(line.suffix(tail.count))
    }

    private static func takeLeadingTimeText(_ text: String) -> String? {
        var copy = text
        return takeLeadingTime(&copy)
    }

    /// Removes and returns a clock time at the start: "10:00 …", "8am …", "8:30 p.m. – …".
    static func takeLeadingTime(_ text: inout String) -> String? {
        guard let match = text.firstMatch(of: /^\s*(?:at\s+|@\s*)?(?<time>\d{1,2}(?:[:.]\d{2})\s*(?:[ap]\.?\s?m\.?)?|\d{1,2}\s*[ap]\.?\s?m\.?)(?=\s|$|[-–—:|·),])\s*[-–—:|·,]?\s*/.ignoresCase()) else {
            return nil
        }
        let time = String(match.output.time)
        guard TimeParser.parse(time) != nil else { return nil }
        text = String(text[match.range.upperBound...])
        return time
    }

    /// Removes and returns a time at the end: "Breakfast 08:00", "Lunch at 1pm".
    static func takeTrailingTime(_ text: inout String) -> String? {
        guard let match = text.firstMatch(of: /\s+(?:at\s+|@\s*)?(?<time>\d{1,2}(?:[:.]\d{2})\s*(?:[ap]\.?\s?m\.?)?|\d{1,2}\s*[ap]\.?\s?m\.?)\s*$/.ignoresCase()) else {
            return nil
        }
        let time = String(match.output.time)
        guard TimeParser.parse(time) != nil else { return nil }
        text = String(text[..<match.range.lowerBound])
        return time
    }

    /// Removes and returns a time in brackets: "Breakfast (08:00)".
    static func takeParenthesizedTime(_ text: inout String) -> String? {
        guard let match = text.firstMatch(of: /\s*[(\[]\s*(?<time>[^)\]]{1,12})\s*[)\]]\s*$/) else { return nil }
        let time = String(match.output.time)
        guard TimeParser.parse(time) != nil else { return nil }
        text = String(text[..<match.range.lowerBound])
        return time
    }

    /// "Breakfast: eggs" → ("Breakfast", "eggs"). Splits on the earliest colon or spaced dash,
    /// never on the colon inside a clock time.
    static func splitAtSeparator(_ text: String) -> (head: String, tail: String)? {
        var candidates: [Range<String.Index>] = []
        for separator in [" - ", " – ", " — ", " | ", " · "] {
            if let range = text.range(of: separator) { candidates.append(range) }
        }
        var index = text.startIndex
        while index < text.endIndex {
            let after = text.index(after: index)
            if text[index] == ":" {
                let digitBefore = index > text.startIndex && text[text.index(before: index)].isNumber
                let digitAfter = after < text.endIndex && text[after].isNumber
                if !(digitBefore && digitAfter) {
                    candidates.append(index..<after)
                    break
                }
            }
            index = after
        }
        for range in candidates.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let head = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let tail = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            // A head of more than four words is a sentence, not a label.
            guard !head.isEmpty, head.split(separator: " ").count <= 4 else { continue }
            return (head, tail)
        }
        return nil
    }

    /// "Lunch Grilled chicken" → ("Lunch", "Grilled chicken"), when the first one or two words
    /// are exactly a type's name.
    static func splitLeadingTypeWord(_ text: String) -> (type: String, title: String)? {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        for count in [2, 1] where words.count > count {
            let head = words.prefix(count).joined(separator: " ")
            if MealTypeParser.exactType(of: head) != nil {
                return (head, words.dropFirst(count).joined(separator: " "))
            }
        }
        return nil
    }

    /// A short title-like first line — "14-Day Keto Plan" — rather than an introduction such as
    /// "Here is your plan:".
    static func looksLikePlanName(_ text: String) -> Bool {
        guard text.count <= 60, text.split(separator: " ").count <= 8 else { return false }
        guard let last = text.last, !":.!?".contains(last) else { return false }
        return true
    }

    struct FoundNutrition {
        var calories: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
    }

    /// Pulls "(430 kcal)", "430 cal", "30 g protein", "protein: 30g" out of a title.
    static func extractNutrition(from text: String) -> (String, FoundNutrition) {
        var title = text
        var found = FoundNutrition()

        if let match = title.firstMatch(of: /[\s(\[,–—-]*(?<value>\d{2,5}(?:[.,]\d+)?)\s*(?:kcal|kkal|kalori|calories|calorías|calorias|cal)\b[)\],]*/.ignoresCase()) {
            found.calories = NumberScanner.leadingNumber(in: String(match.output.value))
            title.removeSubrange(match.range)
        }

        let nutrients: [(WritableKeyPath<FoundNutrition, Double?>, String)] = [
            (\.protein, "protein|proteína|proteina|prot"),
            (\.carbs, "carbs|carbohydrates|carbohidratos|karbonhidrat|carb"),
            (\.fat, "fat|grasa|grasas|yağ|yag"),
        ]
        for (keyPath, words) in nutrients {
            let after = "[\\s(\\[,]*(\\d{1,4}(?:[.,]\\d+)?)\\s*g\\s*(?:\(words))\\b[)\\],]*"
            let before = "[\\s(\\[,]*(?:\(words))\\s*:?\\s*(\\d{1,4}(?:[.,]\\d+)?)\\s*g\\b[)\\],]*"
            for pattern in [after, before] {
                guard let regex = try? Regex(pattern).ignoresCase(), let match = title.firstMatch(of: regex) else { continue }
                if let value = match.output[1].substring.flatMap({ NumberScanner.leadingNumber(in: String($0)) }) {
                    found[keyPath: keyPath] = value
                    title.removeSubrange(match.range)
                    break
                }
            }
        }

        let cleaned = title
            .replacingOccurrences(of: "()", with: "")
            .replacingOccurrences(of: "[]", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;-–—|·:").union(.whitespaces))
        return (cleaned, found)
    }
}
