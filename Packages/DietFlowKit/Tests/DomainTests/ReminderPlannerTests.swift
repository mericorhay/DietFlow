import Foundation
import Testing
import Domain

struct ReminderPlannerTests {
    let monday = day(2026, 10, 5)

    @Test func remindsBeforeEachOpenMealStillAhead() {
        let plan = twoDayPlan()
        let breakfast = MealSchedule(plan: plan, timeZone: utc).occurrences(on: monday)[0].key
        let requests = ReminderPlanner.requests(plan: plan, states: [breakfast: .completed], defaultOffset: .tenMinutes, now: at(monday, 9), timeZone: utc, days: 1)
        #expect(requests.map(\.fireDate) == [at(monday, 13, 50), at(monday, 18, 50)])
        #expect(requests.allSatisfy { $0.minutesBefore == 10 })
    }

    @Test func aMealsOwnSettingWins() {
        var plan = twoDayPlan()
        plan.meals = plan.meals.map { meal in
            var copy = meal
            if meal.type == .lunch { copy.reminder = .off }
            if meal.type == .dinner { copy.reminder = .oneHour }
            return copy
        }
        let requests = ReminderPlanner.requests(plan: plan, states: [:], defaultOffset: .atTime, now: at(monday, 11), timeZone: utc, days: 1)
        #expect(requests.map(\.fireDate) == [at(monday, 18)])
    }

    @Test func remindersOffMeansNone() {
        #expect(ReminderPlanner.requests(plan: twoDayPlan(), states: [:], defaultOffset: .off, now: at(monday, 9), timeZone: utc).isEmpty)
        #expect(ReminderPlanner.requests(plan: nil, states: [:], defaultOffset: .tenMinutes, now: at(monday, 9), timeZone: utc).isEmpty)
    }

    @Test func staysUnderTheSystemLimit() {
        let plan = MealPlan(
            name: "Many",
            schedule: PlanSchedule(startDay: monday, length: 1, repeats: true),
            meals: (0..<12).map { meal(0, .snack, 8 + $0, 0, "Meal \($0)") }
        )
        let requests = ReminderPlanner.requests(plan: plan, states: [:], defaultOffset: .atTime, now: at(monday, 7), timeZone: utc, days: 14)
        #expect(requests.count == ReminderPlanner.limit)
        #expect(requests.map(\.fireDate) == requests.map(\.fireDate).sorted())
        #expect(Set(requests.map(\.identifier)).count == requests.count)
    }
}
