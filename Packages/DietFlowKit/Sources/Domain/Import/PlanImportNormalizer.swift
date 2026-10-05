import Foundation

/// What the importing screen supplies for anything the source leaves out.
public struct ImportDefaults: Sendable {
    /// Used when the source names no plan. Localised by the caller.
    public var planName: String
    /// Used when the source gives no start date.
    public var startDay: CalendarDay

    public init(planName: String, startDay: CalendarDay) {
        self.planName = planName
        self.startDay = startDay
    }
}

/// Something about the source the person should see before saving. Never silently fixed.
public enum ImportIssue: Hashable, Sendable {
    /// `day` is one-based, as the person would say it.
    case timeMissing(day: Int, title: String, assigned: TimeOfDay)
    case timeUnreadable(day: Int, title: String, text: String, assigned: TimeOfDay)
    case untitledMealDropped(day: Int)
    case nutritionDropped(day: Int, title: String)
    case startDateUnreadable(text: String)
    case dayOutOfRange(day: Int)
    case newerFormat(version: Int)

    /// The one-based plan day the issue is about, if any.
    public var day: Int? {
        switch self {
        case .timeMissing(let day, _, _), .timeUnreadable(let day, _, _, _), .untitledMealDropped(let day), .nutritionDropped(let day, _), .dayOutOfRange(let day):
            day
        case .startDateUnreadable, .newerFormat:
            nil
        }
    }
}

public enum PlanImportError: Error, Hashable, Sendable {
    /// There was nothing to read.
    case empty
    /// The source was read, but no meals were found in it.
    case noMeals
    /// The file is not a plan this app can read.
    case unreadable
}

/// A plan ready for the review screen, and what the person should check first.
public struct ImportedPlanDraft: Hashable, Sendable {
    public var plan: MealPlan
    public var issues: [ImportIssue]

    public init(plan: MealPlan, issues: [ImportIssue]) {
        self.plan = plan
        self.issues = issues
    }

    /// Meals the review screen marks because their time was filled in.
    public var mealsWithAssignedTimes: Set<UUID> = []
}

/// Turns a payload from any source into a plan, reporting what had to be filled in or left out.
public enum PlanImportNormalizer {
    public static func draft(from payload: MealPlanPayload, defaults: ImportDefaults) throws -> ImportedPlanDraft {
        var issues: [ImportIssue] = []
        if let version = payload.schemaVersion, version > MealPlanPayload.currentSchemaVersion {
            issues.append(.newerFormat(version: version))
        }

        // Which kind of plan, and where it starts.
        let datedDays = payload.days.compactMap { $0.date.flatMap(Self.day(from:)) }
        let declaredFixed = payload.kind.map { $0.lowercased().contains("fixed") || $0.lowercased().contains("date") } ?? false
        let kind: PlanKind = declaredFixed || (!datedDays.isEmpty && payload.days.allSatisfy { $0.dayIndex == nil }) ? .fixedDates : .cycle

        var startDay = defaults.startDay
        if let text = payload.startDate {
            if let parsed = day(from: text) {
                startDay = parsed
            } else {
                issues.append(.startDateUnreadable(text: text))
                if kind == .fixedDates, let earliest = datedDays.min() { startDay = earliest }
            }
        } else if kind == .fixedDates, let earliest = datedDays.min() {
            startDay = earliest
        }

        // Each source day becomes a zero-based plan day.
        var meals: [Meal] = []
        var assignedTimes = Set<UUID>()
        var highestIndex = -1
        var position = 0
        for sourceDay in payload.days {
            let index: Int
            if kind == .fixedDates, let date = sourceDay.date.flatMap(Self.day(from:)) {
                index = startDay.days(to: date)
            } else if let oneBased = sourceDay.dayIndex {
                index = oneBased - 1
            } else {
                index = position
            }
            position = max(position, index) + 1

            guard index >= 0, index < PlanSchedule.maximumLength else {
                issues.append(.dayOutOfRange(day: index + 1))
                continue
            }

            for source in sourceDay.meals {
                guard let meal = meal(from: source, dayIndex: index, issues: &issues, assignedTimes: &assignedTimes) else { continue }
                meals.append(meal)
                highestIndex = max(highestIndex, index)
            }
        }

        guard !meals.isEmpty else { throw PlanImportError.noMeals }
        // More meals than a year of plan can hold is a wrong file, not a plan. Refused whole
        // rather than cut, because a plan silently missing its end is worse than no import.
        guard meals.count <= PlanLimits.mealsPerPlan else { throw PlanImportError.unreadable }

        let declaredLength = payload.repeatCycle?.lengthInDays ?? 0
        let length = min(max(declaredLength, highestIndex + 1, 1), PlanSchedule.maximumLength)
        let repeats = kind == .cycle ? (payload.repeatCycle?.repeats ?? true) : false

        let plan = MealPlan(
            name: payload.name?.trimmedNonEmpty ?? defaults.planName,
            schedule: PlanSchedule(kind: kind, startDay: startDay, length: length, repeats: repeats),
            meals: meals.sorted { lhs, rhs in
                lhs.dayIndex != rhs.dayIndex ? lhs.dayIndex < rhs.dayIndex : Meal.scheduleOrder(lhs, rhs)
            }
        )
        var draft = ImportedPlanDraft(plan: plan, issues: issues)
        draft.mealsWithAssignedTimes = assignedTimes
        return draft
    }

    private static func meal(from source: MealPayload, dayIndex: Int, issues: inout [ImportIssue], assignedTimes: inout Set<UUID>) -> Meal? {
        var details = source.description?.trimmedNonEmpty
        let title: String
        if let given = source.title?.trimmedNonEmpty {
            title = given
        } else if let fromDetails = details {
            title = fromDetails
            details = nil
        } else {
            issues.append(.untitledMealDropped(day: dayIndex + 1))
            return nil
        }

        let parsedTime = source.time.flatMap(TimeParser.parse)
        let (type, customName) = MealTypeParser.resolve(source.type, time: parsedTime)

        let id = UUID()
        let time: TimeOfDay
        if let parsedTime {
            time = parsedTime
        } else {
            time = type.typicalTime
            assignedTimes.insert(id)
            if let text = source.time?.trimmedNonEmpty {
                issues.append(.timeUnreadable(day: dayIndex + 1, title: title, text: text, assigned: time))
            } else {
                issues.append(.timeMissing(day: dayIndex + 1, title: title, assigned: time))
            }
        }

        var droppedNutrition = false
        func grams(_ value: Double?) -> Double? {
            guard let value else { return nil }
            guard Nutrition.gramRange.contains(value) else {
                droppedNutrition = true
                return nil
            }
            return (value * 10).rounded() / 10
        }
        var calories: Int?
        if let value = source.calories {
            if Nutrition.calorieRange.contains(Int(value.rounded())) {
                calories = Int(value.rounded())
            } else {
                droppedNutrition = true
            }
        }
        let nutrition = Nutrition(calories: calories, protein: grams(source.protein), carbohydrates: grams(source.carbs), fat: grams(source.fat))
        if droppedNutrition {
            issues.append(.nutritionDropped(day: dayIndex + 1, title: title))
        }

        // The title was checked above, so sanitizing only trims and bounds the text.
        let meal = Meal(
            id: id,
            dayIndex: dayIndex,
            type: type,
            customTypeName: customName,
            time: time,
            title: title,
            details: details,
            portion: source.portion?.trimmedNonEmpty,
            nutrition: nutrition,
            notes: source.notes?.trimmedNonEmpty
        )
        return meal.sanitized()
    }

    /// "2026-10-06", also with a time after it ("2026-10-06T00:00:00Z").
    static func day(from text: String) -> CalendarDay? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarDay(trimmed) ?? CalendarDay(String(trimmed.prefix(10)))
    }
}
