import Foundation
import SwiftData
import Domain

/// A plan as stored. The app's canonical copy; the widget never reads it directly.
@Model
final class MealPlanRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    /// "2026-10-05": a wall-calendar day, so the plan does not shift with time zones.
    var startDay: String
    var length: Int
    var repeats: Bool
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MealRecord.plan)
    var meals: [MealRecord] = []

    init(id: UUID, name: String, kindRaw: String, startDay: String, length: Int, repeats: Bool, isActive: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.kindRaw = kindRaw
        self.startDay = startDay
        self.length = length
        self.repeats = repeats
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One meal of a plan's template. What happened to it on a given day lives in
/// `MealCompletionRecord`, never here.
@Model
final class MealRecord {
    @Attribute(.unique) var id: UUID
    var plan: MealPlanRecord?
    var dayIndex: Int
    var typeRaw: String
    var customTypeName: String?
    var hour: Int
    var minute: Int
    var title: String
    var details: String?
    var portion: String?
    var calories: Int?
    var protein: Double?
    var carbohydrates: Double?
    var fat: Double?
    var notes: String?
    /// `ReminderOffset` raw value; nil follows the app-wide default.
    var reminderRaw: Int?

    init(id: UUID, dayIndex: Int, typeRaw: String, hour: Int, minute: Int, title: String) {
        self.id = id
        self.dayIndex = dayIndex
        self.typeRaw = typeRaw
        self.hour = hour
        self.minute = minute
        self.title = title
    }
}

/// What happened to one meal on one day: done or skipped. Pending is the absence of a record.
@Model
final class MealCompletionRecord {
    /// `OccurrenceKey.description`: "<meal id>@2026-10-05".
    @Attribute(.unique) var key: String
    var mealID: UUID
    var planID: UUID
    var occurrenceDay: String
    var stateRaw: String
    var updatedAt: Date

    init(key: String, mealID: UUID, planID: UUID, occurrenceDay: String, stateRaw: String, updatedAt: Date) {
        self.key = key
        self.mealID = mealID
        self.planID = planID
        self.occurrenceDay = occurrenceDay
        self.stateRaw = stateRaw
        self.updatedAt = updatedAt
    }
}

// MARK: - Between records and values

extension MealPlanRecord {
    func value() -> MealPlan {
        MealPlan(
            id: id,
            name: name,
            schedule: PlanSchedule(
                kind: PlanKind(rawValue: kindRaw) ?? .cycle,
                startDay: CalendarDay(startDay) ?? CalendarDay.today(),
                length: length,
                repeats: repeats
            ),
            meals: meals.map { $0.value() }
        )
    }

    func apply(_ plan: MealPlan, now: Date) {
        name = plan.name
        kindRaw = plan.schedule.kind.rawValue
        startDay = plan.schedule.startDay.description
        length = plan.schedule.length
        repeats = plan.schedule.repeats
        updatedAt = now
    }
}

extension MealRecord {
    convenience init(_ meal: Meal) {
        self.init(id: meal.id, dayIndex: meal.dayIndex, typeRaw: meal.type.rawValue, hour: meal.time.hour, minute: meal.time.minute, title: meal.title)
        apply(meal)
    }

    func value() -> Meal {
        Meal(
            id: id,
            dayIndex: dayIndex,
            type: MealType(rawValue: typeRaw) ?? .other,
            customTypeName: customTypeName,
            time: TimeOfDay(hour: hour, minute: minute),
            title: title,
            details: details,
            portion: portion,
            nutrition: Nutrition(calories: calories, protein: protein, carbohydrates: carbohydrates, fat: fat),
            notes: notes,
            reminder: reminderRaw.flatMap(ReminderOffset.init(rawValue:))
        )
    }

    func apply(_ meal: Meal) {
        dayIndex = meal.dayIndex
        typeRaw = meal.type.rawValue
        customTypeName = meal.customTypeName?.trimmedNonEmpty
        hour = meal.time.hour
        minute = meal.time.minute
        title = meal.title
        details = meal.details?.trimmedNonEmpty
        portion = meal.portion?.trimmedNonEmpty
        calories = meal.nutrition.calories
        protein = meal.nutrition.protein
        carbohydrates = meal.nutrition.carbohydrates
        fat = meal.nutrition.fat
        notes = meal.notes?.trimmedNonEmpty
        reminderRaw = meal.reminder?.rawValue
    }
}
