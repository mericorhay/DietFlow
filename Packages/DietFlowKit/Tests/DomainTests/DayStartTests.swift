import Foundation
import Testing
import Domain

private func clock(_ hour: Int, _ minute: Int = 0) -> TimeOfDay {
    TimeOfDay(hour: hour, minute: minute)
}

private func clocks(_ times: [TimeOfDay]) -> [String] {
    times.map(\.isoString)
}

/// Five meals, the way many dietitians write a day.
private let fiveMeals = [clock(8), clock(10, 30), clock(13), clock(16), clock(19)]

struct DayShiftTests {
    @Test func aDayThatStartsOnTimeOrEarlyIsLeftAsWritten() {
        #expect(DayShift.times(fiveMeals, firstMeal: clock(8)) == fiveMeals)
        #expect(DayShift.times(fiveMeals, firstMeal: clock(7, 10)) == fiveMeals)
        // Ten minutes late changes nothing worth changing.
        #expect(DayShift.times(fiveMeals, firstMeal: clock(8, 10)) == fiveMeals)
        #expect(DayShift.delay(fiveMeals, firstMeal: clock(8, 10)) == 0)
    }

    @Test func aLateMorningKeepsDinnerWhereItIsWhileTheDayHasRoom() {
        let shifted = DayShift.times(fiveMeals, firstMeal: clock(10, 10))
        #expect(shifted.first == clock(10, 10))
        #expect(shifted.last == clock(19))
        #expect(DayShift.delay(fiveMeals, firstMeal: clock(10, 10)) == 130)
    }

    @Test func aVeryLateStartMovesDinnerOnlyAsFarAsItMust() throws {
        let shifted = DayShift.times(fiveMeals, firstMeal: clock(13, 30))
        #expect(shifted.first == clock(13, 30))
        let dinner = try #require(shifted.last)
        #expect(dinner > clock(19))
        #expect(dinner <= clock(20, 30))
    }

    @Test func dinnerIsNeverPushedMoreThanAnHourAndAHalf() {
        let shifted = DayShift.times(fiveMeals, firstMeal: clock(17))
        #expect(shifted.last == clock(20, 30))
    }

    @Test(arguments: [clock(8, 30), clock(9, 45), clock(11), clock(12, 20), clock(14), clock(16, 30), clock(18, 30)])
    func mealsOnlyMoveLaterAndKeepTheirOrder(firstMeal: TimeOfDay) {
        let shifted = DayShift.times(fiveMeals, firstMeal: firstMeal)
        #expect(shifted.count == fiveMeals.count)
        for (planned, moved) in zip(fiveMeals, shifted) {
            #expect(moved >= planned, "\(moved.isoString) is earlier than \(planned.isoString)")
        }
        for (earlier, later) in zip(shifted, shifted.dropFirst()) {
            #expect(earlier <= later)
        }
        #expect(shifted.allSatisfy { $0 <= TimeOfDay(minutesSinceMidnight: DayShift.latestMeal) })
    }

    @Test func mealsStayThreeQuartersOfAnHourApartWhereTheDayAllowsIt() {
        let shifted = DayShift.times(fiveMeals, firstMeal: clock(16, 30)).map(\.minutesSinceMidnight)
        for (earlier, later) in zip(shifted, shifted.dropFirst()) {
            #expect(later - earlier >= DayShift.minimumGap - 5)
        }
    }

    @Test func aDayThatStartsAfterItsLastMealIsNotCrammedIntoTheNight() {
        #expect(DayShift.times(fiveMeals, firstMeal: clock(21, 30)) == fiveMeals)
        #expect(DayShift.delay(fiveMeals, firstMeal: clock(21, 30)) == 0)
    }

    @Test func nothingIsMovedPastHalfPastEleven() {
        let lateDinner = [clock(9), clock(22)]
        let shifted = DayShift.times(lateDinner, firstMeal: clock(14))
        #expect(shifted.last == clock(22))
        #expect(DayShift.times([clock(13)], firstMeal: clock(23, 50)) == [clock(23, 30)])
    }

    @Test func aSingleMealMovesWithTheDay() {
        #expect(DayShift.times([clock(13)], firstMeal: clock(15)) == [clock(15)])
    }

    @Test func wakingUpPutsBreakfastHalfAnHourLater() {
        let start = DayStart.wokeUp(at: clock(9, 41), source: .morning)
        #expect(start.firstMeal == clock(10, 10))
        #expect(start.wake == clock(9, 41))
        #expect(DayStart.wokeUp(at: clock(23, 20), source: .shortcut).firstMeal == clock(23, 30))
    }
}

struct LateStartScheduleTests {
    let monday = day(2026, 10, 5)
    let tuesday = day(2026, 10, 6)

    @Test func onlyTheDayThatStartedLateMoves() {
        let starts: DayStarts = [monday: DayStart(firstMeal: clock(12), source: .morning)]
        let schedule = MealSchedule(plan: twoDayPlan(), timeZone: utc, dayStarts: starts)
        let moved = schedule.occurrences(on: monday)
        #expect(moved.first?.date == at(monday, 12))
        #expect(moved.first?.time == clock(12))
        #expect(moved.first?.isMoved == true)
        #expect(moved.first?.meal.time == clock(10), "the plan itself is not edited")
        #expect(moved.last?.date == at(monday, 19), "dinner keeps its time while the day has room")
        #expect(schedule.occurrences(on: tuesday).first?.date == at(tuesday, 10))
        #expect(schedule.occurrences(on: tuesday).allSatisfy { !$0.isMoved })
        #expect(schedule.delay(on: monday) == 120)
        #expect(schedule.delay(on: tuesday) == 0)
    }

    @Test func theMealInFrontFollowsTheLateStart() throws {
        let starts: DayStarts = [monday: DayStart(firstMeal: clock(12), source: .reminder)]
        let schedule = MealSchedule(plan: twoDayPlan(), timeZone: utc, dayStarts: starts)
        // At 11:00 the plan's 10:00 breakfast would have been over; after the late start it is next.
        let focus = try #require(schedule.focus(now: at(monday, 11)))
        #expect(focus.kind == .next)
        #expect(focus.occurrence.meal.title == "Halloumi salad")
        #expect(focus.occurrence.date == at(monday, 12))
        let agenda = schedule.agenda(on: monday, now: at(monday, 12, 30))
        #expect(agenda.current?.occurrence.meal.title == "Halloumi salad")
    }

    @Test func remindersMoveWithTheDayAndTheFirstOneKnowsItIsFirst() {
        let plan = twoDayPlan()
        let starts: DayStarts = [monday: DayStart(firstMeal: clock(12), source: .morning)]
        let requests = ReminderPlanner.requests(plan: plan, states: [:], defaultOffset: .tenMinutes, now: at(monday, 7), timeZone: utc, days: 2, dayStarts: starts)
        let breakfast = requests.first { $0.occurrence.meal.title == "Halloumi salad" }
        #expect(breakfast?.fireDate == at(monday, 11, 50))
        #expect(breakfast?.isFirstOfDay == true)
        #expect(requests.filter(\.isFirstOfDay).count == 2)
        #expect(requests.first { $0.occurrence.meal.title == "Chicken Caesar" }?.isFirstOfDay == false)
    }

    @Test func theWidgetReadsTheLateStartFromItsSnapshot() throws {
        let starts: DayStarts = [monday: DayStart(firstMeal: clock(12), source: .firstMeal), day(2026, 9, 1): DayStart(firstMeal: clock(9), source: .morning)]
        let snapshot = WidgetSnapshot(plan: twoDayPlan(), states: [:], preferences: WidgetPreferences(), generatedAt: at(monday, 7), timeZone: utc, dayStarts: starts)
        #expect(snapshot.recordedDayStarts == [monday: DayStart(firstMeal: clock(12), source: .firstMeal)], "days outside the window are left out")
        let decoded = try WidgetSnapshot.decode(snapshot.encoded())
        #expect(decoded.recordedDayStarts == snapshot.recordedDayStarts)
        guard case .active(let content) = WidgetTimelineBuilder.content(for: decoded, at: at(monday, 11), timeZone: utc) else {
            Issue.record("expected an active plan")
            return
        }
        #expect(content.primary?.date == at(monday, 12))
        let dates = WidgetTimelineBuilder.transitionDates(for: decoded, from: at(monday, 7), timeZone: utc)
        #expect(dates.contains(at(monday, 12)))
        #expect(!dates.contains(at(monday, 10)))
    }

    @Test func aSnapshotWrittenBeforeLateStartsStillReads() throws {
        let json = #"{"version":1,"generatedAt":0,"states":{},"preferences":{}}"#
        let decoded = try WidgetSnapshot.decode(Data(json.utf8))
        #expect(decoded.dayStarts == nil)
        #expect(decoded.recordedDayStarts.isEmpty)
        let plain = WidgetSnapshot(plan: twoDayPlan(), states: [:], preferences: WidgetPreferences(), generatedAt: at(monday, 7), timeZone: utc)
        #expect(plain.dayStarts == nil, "nothing is written when no day started late")
    }

    @Test func aLateStartOnADaylightSavingDayKeepsWallClockTimes() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        // Clocks go back on Sunday 25 October 2026.
        let sunday = day(2026, 10, 25)
        let plan = MealPlan(name: "One day", schedule: PlanSchedule(startDay: sunday, length: 1, repeats: true), meals: [meal(0, .breakfast, 8, 0, "Eggs"), meal(0, .dinner, 19, 0, "Soup")])
        let schedule = MealSchedule(plan: plan, timeZone: berlin, dayStarts: [sunday: DayStart(firstMeal: clock(11), source: .morning)])
        let occurrences = schedule.occurrences(on: sunday)
        #expect(occurrences.first?.date == clock(11).date(on: sunday, in: berlin))
        #expect(occurrences.last?.date == clock(19).date(on: sunday, in: berlin))
    }
}

struct EstimateAndRecipeTests {
    @Test func anEstimateStaysMarkedThroughSanitizingAndTheWidgetCopy() throws {
        var lunch = meal(0, .lunch, 13, 0, "Lentil soup")
        lunch.nutrition = Nutrition(calories: 320, protein: 18, estimated: true)
        let kept = try #require(lunch.sanitized())
        #expect(kept.nutrition.isEstimated)
        let plan = MealPlan(name: "p", schedule: PlanSchedule(startDay: day(2026, 10, 5), length: 1, repeats: true), meals: [kept])
        #expect(plan.trimmedForWidget().meals.first?.nutrition.isEstimated == true)
        // A figure the plan gives is not an estimate, and nothing left means nothing to mark.
        #expect(!Nutrition(calories: 320).isEstimated)
        #expect(Nutrition(calories: 99_999, estimated: true).sanitized().isEmpty)
        #expect(Nutrition(calories: 99_999, estimated: true).sanitized().estimated == nil)
    }

    @Test func estimatesTravelThroughAnExportedPlanAndBack() throws {
        var lunch = meal(0, .lunch, 13, 0, "Lentil soup")
        lunch.nutrition = Nutrition(calories: 320, estimated: true)
        let plan = MealPlan(name: "p", schedule: PlanSchedule(startDay: day(2026, 10, 5), length: 1, repeats: true), meals: [lunch, meal(0, .dinner, 19, 0, "Fish")])
        let payload = try MealPlanPayload.decode(MealPlanPayload(plan: plan).encodedJSON())
        let draft = try PlanImportNormalizer.draft(from: payload, defaults: importDefaults)
        let soup = try #require(draft.plan.meals.first { $0.title == "Lentil soup" })
        #expect(soup.nutrition.isEstimated)
        #expect(soup.nutrition.calories == 320)
        #expect(draft.plan.meals.first { $0.title == "Fish" }?.nutrition.isEstimated == false)
    }

    @Test func aRecipeReadsWhatTheServerWritesAndForgivesWhatItDoesNot() throws {
        let json = #"""
        {"title":"Menemen","servings":2,"minutes":15,"difficulty":"easy",
         "ingredients":[{"name":"Eggs","amount":"4","substitutes":[{"name":"Tofu","amount":"300 g","note":"vegan"}]}],
         "steps":[{"text":"Chop.","kind":"chop"},{"text":"Cook.","minutes":8,"kind":"sauté"},{"text":"Serve.","minutes":0}],
         "tips":["Ripe tomatoes."]}
        """#
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        #expect(recipe.steps.map(\.kind) == [.chop, .other, .other])
        #expect(recipe.steps.map(\.minutes) == [nil, 8, nil])
        #expect(recipe.timedSteps == 1)
        #expect(recipe.ingredients.first?.substitutes.first?.note == "vegan")
        #expect(recipe.servings == 2)
    }

    @Test func theSameMealAsksForTheSameRecipe() {
        var lunch = meal(0, .lunch, 13, 0, "Lentil soup")
        lunch.details = "1 cup lentils"
        let one = RecipeRequest(meal: lunch, servings: 1, language: "Turkish")
        var copy = lunch
        copy.id = UUID()
        copy.time = clock(14)
        #expect(RecipeRequest(meal: copy, servings: 1, language: "Turkish").cacheKey == one.cacheKey, "a repeating meal on another day is the same recipe")
        #expect(RecipeRequest(meal: lunch, servings: 2, language: "Turkish").cacheKey != one.cacheKey)
        #expect(RecipeRequest(meal: lunch, servings: 1, language: "English").cacheKey != one.cacheKey)
        #expect(RecipeRequest(meal: lunch, servings: 99, language: "Turkish").servings == 8)
    }

    @Test func theNewAssistantUsesAreCountedOnBothTiers() throws {
        var ledger = UsageLedger(period: "2026-10")
        for point in [AccessPoint.aiNutrition, .aiRecipe] {
            #expect(!AccessPolicy.isPlusOnly(point))
            #expect(point.meterKey == point.rawValue)
            let free = try #require(AccessPolicy.limit(point, tier: .free))
            let plus = try #require(AccessPolicy.limit(point, tier: .plus))
            #expect(plus > free)
            for _ in 0..<free { ledger.record(point) }
            #expect(AccessPolicy.decide(point, tier: .free, ledger: ledger) == .limitReached(limit: free))
            #expect(AccessPolicy.decide(point, tier: .plus, ledger: ledger) == .allowed)
        }
        #expect(ledger.used(.aiPlan) == 0, "each use is counted under its own name")
    }

    @Test func settingsFromBeforeSmartTimesTurnThemOn() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"remindersEnabled":true}"#.utf8))
        #expect(decoded.smartMealTimes)
        #expect(decoded.remindersEnabled)
        #expect(!decoded.hasAskedForReview)
    }
}
