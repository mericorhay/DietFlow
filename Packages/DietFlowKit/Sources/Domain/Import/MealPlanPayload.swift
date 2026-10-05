import Foundation

/// The interchange format for a plan: what a `.mealplan` file holds, what ChatGPT or Claude is
/// asked to write, and what every import path — file, pasted text, photo, PDF, the on-device model,
/// a future MCP server — is turned into before review. Nothing past the review screen cares where
/// a plan came from.
///
/// Decoding is forgiving on purpose: models and people write "carbohydrates" for "carbs", numbers
/// as "510 kcal", and leave things out. What cannot be understood is reported on the review
/// screen, never silently guessed.
public struct MealPlanPayload: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int?
    public var name: String?
    /// "2026-10-06".
    public var startDate: String?
    /// "cycle" (Day 1, Day 2, …) or "fixedDates" (each day has a `date`).
    public var kind: String?
    public var repeatCycle: RepeatCyclePayload?
    public var days: [DayPayload]

    public init(schemaVersion: Int? = currentSchemaVersion, name: String? = nil, startDate: String? = nil, kind: String? = nil, repeatCycle: RepeatCyclePayload? = nil, days: [DayPayload]) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.startDate = startDate
        self.kind = kind
        self.repeatCycle = repeatCycle
        self.days = days
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, name, startDate, kind, repeatCycle, days
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleKey.self)
        schemaVersion = container.flexibleInt(["schemaVersion", "version"])
        name = container.flexibleString(["name", "planName", "title"])
        startDate = container.flexibleString(["startDate", "start", "startDay"])
        kind = container.flexibleString(["kind", "type", "planType"])
        repeatCycle = container.decodeFirst(RepeatCyclePayload.self, ["repeatCycle", "cycle", "repeat"])

        if let days = container.decodeFirst([DayPayload].self, ["days", "plan", "schedule"]) {
            self.days = days
        } else if let meals = container.decodeFirst([FlatMealPayload].self, ["meals"]) {
            // A flat list of meals, each saying which day it belongs to.
            let grouped = Dictionary(grouping: meals) { $0.day ?? 1 }
            self.days = grouped.keys.sorted().map { DayPayload(dayIndex: $0, meals: grouped[$0]?.map(\.meal) ?? []) }
        } else {
            self.days = []
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(repeatCycle, forKey: .repeatCycle)
        try container.encode(days, forKey: .days)
    }
}

public struct RepeatCyclePayload: Codable, Hashable, Sendable {
    public var lengthInDays: Int?
    public var repeats: Bool?

    public init(lengthInDays: Int? = nil, repeats: Bool? = nil) {
        self.lengthInDays = lengthInDays
        self.repeats = repeats
    }

    enum CodingKeys: String, CodingKey {
        case lengthInDays, repeats
    }

    public init(from decoder: any Decoder) throws {
        // Also accepts a bare number (`"repeatCycle": 14`) or a bare flag (`"repeatCycle": true`).
        if let single = try? decoder.singleValueContainer() {
            if let flag = try? single.decode(Bool.self) {
                self.init(lengthInDays: nil, repeats: flag)
                return
            }
            if let length = try? single.decode(Int.self) {
                self.init(lengthInDays: length, repeats: true)
                return
            }
        }
        let container = try decoder.container(keyedBy: FlexibleKey.self)
        self.init(
            lengthInDays: container.flexibleInt(["lengthInDays", "length", "days", "cycleLength"]),
            repeats: container.flexibleBool(["repeats", "repeat", "enabled", "loop"])
        )
    }
}

public struct DayPayload: Codable, Hashable, Sendable {
    /// One-based: the first day of the plan is 1.
    public var dayIndex: Int?
    /// For fixed-date plans: "2026-10-06".
    public var date: String?
    public var meals: [MealPayload]

    public init(dayIndex: Int? = nil, date: String? = nil, meals: [MealPayload]) {
        self.dayIndex = dayIndex
        self.date = date
        self.meals = meals
    }

    enum CodingKeys: String, CodingKey {
        case dayIndex, date, meals
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleKey.self)
        dayIndex = container.flexibleInt(["dayIndex", "day", "dayNumber", "index", "number"])
        date = container.flexibleString(["date", "calendarDate"])
        meals = container.decodeFirst([MealPayload].self, ["meals", "items", "entries"]) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(dayIndex, forKey: .dayIndex)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encode(meals, forKey: .meals)
    }
}

public struct MealPayload: Codable, Hashable, Sendable {
    /// "14:00" preferred; "2 PM", "14.00" and similar are understood.
    public var time: String?
    /// "breakfast", "snack", "lunch", "dinner", "other", or the plan's own word for it.
    public var type: String?
    public var title: String?
    public var description: String?
    public var portion: String?
    public var calories: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var notes: String?

    public init(time: String? = nil, type: String? = nil, title: String? = nil, description: String? = nil, portion: String? = nil, calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil, notes: String? = nil) {
        self.time = time
        self.type = type
        self.title = title
        self.description = description
        self.portion = portion
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case time, type, title, description, portion, calories, protein, carbs, fat, notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleKey.self)
        time = container.flexibleString(["time", "at", "scheduledTime", "hour"])
        type = container.flexibleString(["type", "mealType", "meal", "slot", "category"])
        title = container.flexibleString(["title", "name", "dish", "food"])
        description = container.flexibleString(["description", "details", "detail", "ingredients", "items"])
        portion = container.flexibleString(["portion", "serving", "amount", "quantity"])
        calories = container.flexibleNumber(["calories", "kcal", "energy", "cal"])
        protein = container.flexibleNumber(["protein", "proteins", "proteinGrams"])
        carbs = container.flexibleNumber(["carbs", "carbohydrates", "carbohydrate", "carbGrams"])
        fat = container.flexibleNumber(["fat", "fats", "fatGrams"])
        notes = container.flexibleString(["notes", "note", "comment", "tips"])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(portion, forKey: .portion)
        try container.encodeIfPresent(calories, forKey: .calories)
        try container.encodeIfPresent(protein, forKey: .protein)
        try container.encodeIfPresent(carbs, forKey: .carbs)
        try container.encodeIfPresent(fat, forKey: .fat)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

/// `{"day": 2, "time": "14:00", …}` in a flat `meals` list.
private struct FlatMealPayload: Decodable {
    var day: Int?
    var meal: MealPayload

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleKey.self)
        day = container.flexibleInt(["day", "dayIndex", "dayNumber"])
        meal = try MealPayload(from: decoder)
    }
}

// MARK: - Building a payload from a plan (export)

extension MealPlanPayload {
    public init(plan: MealPlan) {
        let schedule = plan.schedule
        let days = (0..<schedule.length).compactMap { index -> DayPayload? in
            let meals = plan.meals(onDayIndex: index)
            guard !meals.isEmpty else { return nil }
            let date = schedule.kind == .fixedDates ? schedule.startDay.adding(days: index).description : nil
            return DayPayload(dayIndex: index + 1, date: date, meals: meals.map(MealPayload.init(meal:)))
        }
        self.init(
            schemaVersion: Self.currentSchemaVersion,
            name: plan.name,
            startDate: schedule.startDay.description,
            kind: schedule.kind.rawValue,
            repeatCycle: RepeatCyclePayload(lengthInDays: schedule.length, repeats: schedule.repeats),
            days: days
        )
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> MealPlanPayload {
        try JSONDecoder().decode(MealPlanPayload.self, from: data)
    }
}

extension MealPayload {
    public init(meal: Meal) {
        self.init(
            time: meal.time.isoString,
            type: meal.type == .other ? (meal.customTypeName?.trimmedNonEmpty ?? MealType.other.rawValue) : meal.type.rawValue,
            title: meal.title,
            description: meal.details,
            portion: meal.portion,
            calories: meal.nutrition.calories.map(Double.init),
            protein: meal.nutrition.protein,
            carbs: meal.nutrition.carbohydrates,
            fat: meal.nutrition.fat,
            notes: meal.notes
        )
    }
}

// MARK: - Forgiving keyed decoding

struct FlexibleKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where Key == FlexibleKey {
    /// The container's key matching `name`, ignoring case, underscores and dashes.
    private func key(matching names: [String]) -> FlexibleKey? {
        let wanted = Set(names.map(Self.normalized))
        return allKeys.first { wanted.contains(Self.normalized($0.stringValue)) }
    }

    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0 != "_" && $0 != "-" && $0 != " " }
    }

    func decodeFirst<T: Decodable>(_ type: T.Type, _ names: [String]) -> T? {
        guard let key = key(matching: names) else { return nil }
        return try? decode(T.self, forKey: key)
    }

    func flexibleString(_ names: [String]) -> String? {
        guard let key = key(matching: names) else { return nil }
        if let text = try? decode(String.self, forKey: key) { return text.trimmedNonEmpty }
        if let number = try? decode(Double.self, forKey: key) {
            return number.rounded() == number ? String(Int(number)) : String(number)
        }
        if let list = try? decode([String].self, forKey: key) {
            return list.compactMap(\.trimmedNonEmpty).joined(separator: ", ").trimmedNonEmpty
        }
        return nil
    }

    func flexibleNumber(_ names: [String]) -> Double? {
        guard let key = key(matching: names) else { return nil }
        if let number = try? decode(Double.self, forKey: key) { return number.isFinite ? number : nil }
        if let text = try? decode(String.self, forKey: key) { return NumberScanner.leadingNumber(in: text) }
        return nil
    }

    func flexibleInt(_ names: [String]) -> Int? {
        flexibleNumber(names).flatMap { $0.isFinite && abs($0) < 1_000_000 ? Int($0.rounded()) : nil }
    }

    func flexibleBool(_ names: [String]) -> Bool? {
        guard let key = key(matching: names) else { return nil }
        if let flag = try? decode(Bool.self, forKey: key) { return flag }
        if let text = try? decode(String.self, forKey: key) {
            switch text.lowercased().trimmingCharacters(in: .whitespaces) {
            case "true", "yes", "on", "1", "evet", "sí", "si": return true
            case "false", "no", "off", "0", "hayır", "hayir": return false
            default: return nil
            }
        }
        if let number = try? decode(Int.self, forKey: key) { return number != 0 }
        return nil
    }
}

enum NumberScanner {
    /// The first number in `text`: "510 kcal" → 510, "12,5 g" → 12.5, "~30g" → 30.
    static func leadingNumber(in text: String) -> Double? {
        var digits = ""
        var seenSeparator = false
        var started = false
        for character in text {
            if character.isASCII, character.isNumber {
                digits.append(character)
                started = true
            } else if started, !seenSeparator, character == "." || character == "," {
                digits.append(".")
                seenSeparator = true
            } else if started {
                break
            }
        }
        if digits.hasSuffix(".") { digits.removeLast() }
        return Double(digits)
    }
}
