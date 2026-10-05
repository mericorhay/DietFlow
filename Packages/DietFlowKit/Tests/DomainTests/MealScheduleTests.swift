import Foundation
import Testing
import Domain

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func meal(_ slot: MealSlot, _ hour: Int, _ title: String) -> Meal {
    Meal(slot: slot, time: TimeOfDay(hour: hour, minute: 0), title: title)
}

/// Two-day cycle starting 5 October: eggs and fish on odd days, yogurt and chicken on even days.
private let plan = MealPlan(
    name: "Keto",
    startDate: date(5, 0),
    days: [
        DayPlan(meals: [meal(.dinner, 19, "Fish"), meal(.breakfast, 8, "Eggs")]),
        DayPlan(meals: [meal(.breakfast, 8, "Yogurt"), meal(.dinner, 19, "Chicken")]),
    ]
)
private let schedule = MealSchedule(plan: plan, calendar: utc)

@Test func mealsComeBackInClockOrder() {
    #expect(schedule.meals(on: date(5, 12)).map(\.meal.title) == ["Eggs", "Fish"])
}

@Test func cycleRepeats() {
    #expect(schedule.meals(on: date(6, 12)).map(\.meal.title) == ["Yogurt", "Chicken"])
    #expect(schedule.meals(on: date(7, 12)).map(\.meal.title) == ["Eggs", "Fish"])
}

@Test func nextMealIsLaterToday() {
    let next = schedule.next(after: date(5, 12))
    #expect(next?.meal.title == "Fish")
    #expect(next?.date == date(5, 19))
}

@Test func afterTheLastMealNextIsTomorrowsFirst() {
    let next = schedule.next(after: date(5, 21))
    #expect(next?.meal.title == "Yogurt")
    #expect(next?.date == date(6, 8))
}

@Test func nothingIsScheduledBeforeThePlanStarts() {
    #expect(schedule.meals(on: date(4, 12)).isEmpty)
}

@Test func anEmptyPlanSchedulesNothing() {
    let empty = MealSchedule(plan: MealPlan(name: "Empty", startDate: date(5, 0), days: []), calendar: utc)
    #expect(empty.next(after: date(5, 12)) == nil)
}
