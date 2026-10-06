import Foundation
import Testing
import Domain

let utc = TimeZone(identifier: "UTC")!

func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> CalendarDay {
    CalendarDay(year: year, month: month, day: dayOfMonth)
}

func at(_ calendarDay: CalendarDay, _ hour: Int, _ minute: Int = 0, in timeZone: TimeZone = utc) -> Date {
    TimeOfDay(hour: hour, minute: minute).date(on: calendarDay, in: timeZone)
}

func meal(_ dayIndex: Int, _ type: MealType, _ hour: Int, _ minute: Int = 0, _ title: String) -> Meal {
    Meal(dayIndex: dayIndex, type: type, time: TimeOfDay(hour: hour, minute: minute), title: title)
}

/// Three meals a day on a two-day cycle starting Monday 5 October 2026.
func twoDayPlan(repeats: Bool = true, start: CalendarDay = day(2026, 10, 5)) -> MealPlan {
    MealPlan(
        name: "Keto",
        schedule: PlanSchedule(kind: .cycle, startDay: start, length: 2, repeats: repeats),
        meals: [
            meal(0, .dinner, 19, 0, "Steak salad"),
            meal(0, .breakfast, 10, 0, "Halloumi salad"),
            meal(0, .lunch, 14, 0, "Chicken Caesar"),
            meal(1, .breakfast, 10, 0, "Feta salad"),
            meal(1, .lunch, 14, 0, "Greek salad"),
            meal(1, .dinner, 19, 0, "Taco salad"),
        ]
    )
}

struct DayIndexTests {
    let fourteenDays = MealPlan(name: "14", schedule: PlanSchedule(startDay: day(2026, 10, 5), length: 14, repeats: true))

    @Test func countsCalendarDaysFromTheStart() {
        let schedule = MealSchedule(plan: fourteenDays, timeZone: utc)
        #expect(schedule.phase(on: day(2026, 10, 5)) == .active(dayIndex: 0, pass: 0))
        #expect(schedule.phase(on: day(2026, 10, 18)) == .active(dayIndex: 13, pass: 0))
    }

    @Test func fourteenDayPlanStartsOverAfterDayFourteen() {
        let schedule = MealSchedule(plan: fourteenDays, timeZone: utc)
        #expect(schedule.phase(on: day(2026, 10, 19)) == .active(dayIndex: 0, pass: 1))
        #expect(schedule.phase(on: day(2026, 11, 2)) == .active(dayIndex: 0, pass: 2))
        #expect(schedule.dayIndex(on: day(2026, 11, 8)) == 6)
    }

    @Test func planThatDoesNotRepeatEndsAfterItsLastDay() {
        var plan = fourteenDays
        plan.schedule.repeats = false
        let schedule = MealSchedule(plan: plan, timeZone: utc)
        #expect(schedule.phase(on: day(2026, 10, 18)) == .active(dayIndex: 13, pass: 0))
        #expect(schedule.phase(on: day(2026, 10, 19)) == .ended(lastDay: day(2026, 10, 18)))
        #expect(schedule.dayIndex(on: day(2026, 10, 19)) == nil)
    }

    @Test func nothingIsScheduledBeforeThePlanStarts() {
        let schedule = MealSchedule(plan: twoDayPlan(start: day(2026, 10, 6)), timeZone: utc)
        #expect(schedule.phase(on: day(2026, 10, 5)) == .notStarted(startsOn: day(2026, 10, 6)))
        #expect(schedule.meals(on: day(2026, 10, 5)).isEmpty)
    }

    @Test func fixedDatePlansNeverRepeat() {
        let schedule = PlanSchedule(kind: .fixedDates, startDay: day(2026, 10, 5), length: 3, repeats: true)
        #expect(schedule.repeats == false)
        #expect(schedule.lastDay == day(2026, 10, 7))
    }

    @Test func calendarDayOfAPlanDayIsTheNextTimeItComesAround() {
        let schedule = MealSchedule(plan: fourteenDays, timeZone: utc)
        #expect(schedule.calendarDay(forDayIndex: 2, onOrAfter: day(2026, 10, 5)) == day(2026, 10, 7))
        #expect(schedule.calendarDay(forDayIndex: 2, onOrAfter: day(2026, 10, 7)) == day(2026, 10, 7))
        #expect(schedule.calendarDay(forDayIndex: 2, onOrAfter: day(2026, 10, 20)) == day(2026, 10, 21))
    }
}

struct MealOrderTests {
    @Test func mealsComeBackInClockOrder() {
        let schedule = MealSchedule(plan: twoDayPlan(), timeZone: utc)
        #expect(schedule.meals(on: day(2026, 10, 5)).map(\.title) == ["Halloumi salad", "Chicken Caesar", "Steak salad"])
        #expect(schedule.meals(on: day(2026, 10, 7)).map(\.title) == ["Halloumi salad", "Chicken Caesar", "Steak salad"])
        #expect(schedule.meals(on: day(2026, 10, 8)).map(\.title) == ["Feta salad", "Greek salad", "Taco salad"])
    }

    @Test func mealsAtTheSameMinuteKeepAStableOrder() {
        let plan = MealPlan(
            name: "Same time",
            schedule: PlanSchedule(startDay: day(2026, 10, 5), length: 1, repeats: true),
            meals: [meal(0, .snack, 8, 0, "Coffee"), meal(0, .breakfast, 8, 0, "Eggs"), meal(0, .other, 8, 0, "Vitamins")]
        )
        let titles = MealSchedule(plan: plan, timeZone: utc).meals(on: day(2026, 10, 5)).map(\.title)
        #expect(titles == ["Eggs", "Coffee", "Vitamins"])
    }

    @Test func mealsBeyondThePlanLengthAreIgnored() {
        var plan = twoDayPlan()
        plan.meals.append(meal(5, .lunch, 12, 0, "Orphan"))
        let schedule = MealSchedule(plan: plan, timeZone: utc)
        #expect(!schedule.occurrences(from: day(2026, 10, 5), days: 10).contains { $0.meal.title == "Orphan" })
        #expect(plan.mealCount == 6)
    }
}

struct AgendaTests {
    let schedule = MealSchedule(plan: twoDayPlan(), timeZone: utc)
    let monday = day(2026, 10, 5)

    func roles(at hour: Int, _ minute: Int = 0, states: OccurrenceStates = [:]) -> [MealRole] {
        schedule.agenda(on: monday, states: states, now: at(monday, hour, minute)).items.map(\.role)
    }

    func key(_ index: Int, on calendarDay: CalendarDay? = nil) -> OccurrenceKey {
        let target = calendarDay ?? monday
        return schedule.occurrences(on: target)[index].key
    }

    @Test func lunchIsNextUntilItsMinuteThenCurrent() {
        let breakfastDone: OccurrenceStates = [key(0): .completed]
        #expect(roles(at: 13, 59, states: breakfastDone) == [.done, .next, .upcoming])
        #expect(roles(at: 14, 0, states: breakfastDone) == [.done, .current, .upcoming])
    }

    @Test func aCurrentMealLapsesAfterItsWindow() {
        // An hour after 14:00, with nothing marked: lunch gives way to dinner by itself.
        #expect(roles(at: 14, 59) == [.past, .current, .upcoming])
        #expect(roles(at: 15, 1) == [.past, .past, .next])
    }

    @Test func howLongAMealStaysInFrontCanBeChosen() {
        func roles(window minutes: Double, at hour: Int, _ minute: Int) -> [MealRole] {
            MealSchedule(plan: twoDayPlan(), timeZone: utc, currentWindow: minutes * 60)
                .agenda(on: monday, now: at(monday, hour, minute)).items.map(\.role)
        }
        #expect(roles(window: 30, at: 14, 29) == [.past, .current, .upcoming])
        #expect(roles(window: 30, at: 14, 31) == [.past, .past, .next])
        #expect(roles(window: 120, at: 15, 59) == [.past, .current, .upcoming])
        #expect(roles(window: 120, at: 16, 1) == [.past, .past, .next])
    }

    @Test func theDayMovesOnWithoutAnythingBeingMarked() throws {
        // Nobody taps anything all day.
        let titles = try [(10, 30), (12, 0), (14, 30), (16, 0), (19, 30), (21, 0)].map { hour, minute in
            try #require(schedule.focus(now: at(monday, hour, minute))).occurrence.meal.title
        }
        #expect(titles == ["Halloumi salad", "Chicken Caesar", "Chicken Caesar", "Steak salad", "Steak salad", "Feta salad"])
    }

    @Test func currentWindowStopsAtTheNextMeal() {
        let plan = MealPlan(
            name: "Close meals",
            schedule: PlanSchedule(startDay: monday, length: 1, repeats: true),
            meals: [meal(0, .lunch, 14, 0, "Lunch"), meal(0, .snack, 14, 30, "Snack")]
        )
        let close = MealSchedule(plan: plan, timeZone: utc)
        #expect(close.agenda(on: monday, now: at(monday, 14, 31)).items.map(\.role) == [.past, .current])
    }

    @Test func doneAndSkippedMealsAreNeverNext() {
        let states: OccurrenceStates = [key(0): .completed, key(1): .skipped]
        #expect(roles(at: 9, 0, states: states) == [.done, .skipped, .next])
        let agenda = schedule.agenda(on: monday, states: states, now: at(monday, 9))
        #expect(agenda.next?.occurrence.meal.title == "Steak salad")
        #expect(agenda.remainingCount == 1)
    }

    @Test func aDayIsCompleteWhenEveryMealIsMarked() {
        let states: OccurrenceStates = [key(0): .completed, key(1): .completed, key(2): .skipped]
        let agenda = schedule.agenda(on: monday, states: states, now: at(monday, 21))
        #expect(agenda.isComplete)
        #expect(agenda.remainingCount == 0)
    }

    @Test func otherDaysHaveNoNextOrCurrent() {
        let tuesday = day(2026, 10, 6)
        let future = schedule.agenda(on: tuesday, now: at(monday, 12)).items.map(\.role)
        #expect(future == [.upcoming, .upcoming, .upcoming])
        let past = schedule.agenda(on: monday, now: at(tuesday, 12)).items.map(\.role)
        #expect(past == [.past, .past, .past])
    }

    @Test func markingADayDoesNotMarkTheSameMealNextCycle() {
        let states: OccurrenceStates = [key(1): .completed]
        let nextPass = day(2026, 10, 7)
        #expect(schedule.occurrences(on: nextPass, states: states)[1].state == .pending)
        #expect(schedule.occurrences(on: monday, states: states)[1].state == .completed)
    }
}

struct FocusTests {
    let schedule = MealSchedule(plan: twoDayPlan(), timeZone: utc)
    let monday = day(2026, 10, 5)
    let tuesday = day(2026, 10, 6)

    @Test func nextMealLaterToday() throws {
        let focus = try #require(schedule.focus(now: at(monday, 12)))
        #expect(focus.kind == .next)
        #expect(focus.occurrence.meal.title == "Chicken Caesar")
        #expect(focus.occurrence.date == at(monday, 14))
        #expect(focus.following?.meal.title == "Steak salad")
    }

    @Test func currentMealIsInFront() throws {
        let focus = try #require(schedule.focus(now: at(monday, 14, 20)))
        #expect(focus.kind == .now)
        #expect(focus.occurrence.meal.title == "Chicken Caesar")
    }

    @Test func afterTheLastMealItIsTomorrowsFirst() throws {
        let focus = try #require(schedule.focus(now: at(monday, 21)))
        #expect(focus.kind == .laterDay)
        #expect(focus.occurrence.meal.title == "Feta salad")
        #expect(focus.occurrence.day == tuesday)
        #expect(focus.following?.meal.title == "Greek salad")
    }

    @Test func midnightMovesToTheNextDay() throws {
        let beforeMidnight = try #require(schedule.focus(now: at(monday, 23, 59)))
        #expect(beforeMidnight.kind == .laterDay)
        let afterMidnight = try #require(schedule.focus(now: tuesday.startDate(in: utc)))
        #expect(afterMidnight.kind == .next)
        #expect(afterMidnight.occurrence.day == tuesday)
        #expect(afterMidnight.occurrence.meal.title == "Feta salad")
    }

    @Test func followingMealOfTheLastMealIsTomorrows() throws {
        let focus = try #require(schedule.focus(now: at(monday, 18)))
        #expect(focus.occurrence.meal.title == "Steak salad")
        #expect(focus.following?.day == tuesday)
    }

    @Test func aDayWithoutMealsIsSkipped() throws {
        let plan = MealPlan(
            name: "Gap",
            schedule: PlanSchedule(startDay: monday, length: 3, repeats: true),
            meals: [meal(0, .lunch, 13, 0, "Day one"), meal(2, .lunch, 13, 0, "Day three")]
        )
        let gap = MealSchedule(plan: plan, timeZone: utc)
        #expect(gap.agenda(on: tuesday, now: at(tuesday, 9)).items.isEmpty)
        let focus = try #require(gap.focus(now: at(tuesday, 9)))
        #expect(focus.occurrence.meal.title == "Day three")
        #expect(focus.occurrence.day == day(2026, 10, 7))
    }

    @Test func aPlanStartingTomorrowShowsItsFirstMeal() throws {
        let later = MealSchedule(plan: twoDayPlan(start: tuesday), timeZone: utc)
        let focus = try #require(later.focus(now: at(monday, 12)))
        #expect(focus.kind == .laterDay)
        #expect(focus.occurrence.day == tuesday)
        #expect(focus.occurrence.meal.title == "Halloumi salad")
    }

    @Test func anEndedPlanHasNothingInFront() {
        let ended = MealSchedule(plan: twoDayPlan(repeats: false), timeZone: utc)
        #expect(ended.focus(now: at(day(2026, 10, 7), 9)) == nil)
        #expect(ended.focus(now: at(tuesday, 21)) == nil)
    }

    @Test func anEmptyPlanHasNothingInFront() {
        let empty = MealSchedule(plan: MealPlan(name: "Empty", schedule: PlanSchedule(startDay: monday, length: 7, repeats: true)), timeZone: utc)
        #expect(empty.focus(now: at(monday, 12)) == nil)
        #expect(empty.nextDayWithMeals(after: monday) == nil)
    }

    @Test func tenMealsADayStayInOrder() throws {
        let times = [(7, 0), (8, 0), (10, 0), (12, 0), (13, 30), (15, 0), (16, 30), (18, 0), (20, 0), (21, 30)]
        let plan = MealPlan(
            name: "Ten",
            schedule: PlanSchedule(startDay: monday, length: 1, repeats: true),
            meals: times.enumerated().reversed().map { index, time in meal(0, .snack, time.0, time.1, "Meal \(index + 1)") }
        )
        let ten = MealSchedule(plan: plan, timeZone: utc)
        let agenda = ten.agenda(on: monday, now: at(monday, 12, 10))
        #expect(agenda.items.map(\.occurrence.meal.title) == (1...10).map { "Meal \($0)" })
        #expect(agenda.current?.occurrence.meal.title == "Meal 4")
        #expect(agenda.remainingCount == 7)
        let focus = try #require(ten.focus(now: at(monday, 12, 10)))
        #expect(focus.following?.meal.title == "Meal 5")
    }
}
