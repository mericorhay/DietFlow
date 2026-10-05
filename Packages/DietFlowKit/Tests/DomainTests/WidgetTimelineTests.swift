import Foundation
import Testing
import Domain

struct WidgetTimelineTests {
    let monday = day(2026, 10, 5)
    let tuesday = day(2026, 10, 6)

    func snapshot(_ plan: MealPlan? = twoDayPlan(), states: OccurrenceStates = [:], at date: Date? = nil) -> WidgetSnapshot {
        WidgetSnapshot(plan: plan, states: states, preferences: WidgetPreferences(), generatedAt: date ?? at(monday, 9), timeZone: utc)
    }

    func active(_ content: WidgetContent) throws -> WidgetDayContent {
        guard case .active(let day) = content else {
            Issue.record("Expected an active plan, got \(content)")
            throw CancellationError()
        }
        return day
    }

    @Test func changesAtMealTimesWindowEndsCountdownsAndMidnight() {
        let dates = Set(WidgetTimelineBuilder.transitionDates(for: snapshot(), from: at(monday, 9), timeZone: utc))
        #expect(dates.contains(at(monday, 10)))
        #expect(dates.contains(at(monday, 11, 30)))
        #expect(dates.contains(at(monday, 13)))
        #expect(dates.contains(at(monday, 13, 55)))
        #expect(dates.contains(at(monday, 14)))
        #expect(dates.contains(at(monday, 15, 30)))
        #expect(dates.contains(at(monday, 19)))
        #expect(dates.contains(at(monday, 20, 30)))
        #expect(dates.contains(tuesday.startDate(in: utc)))
        #expect(dates.contains(at(tuesday, 10)))
        #expect(!dates.contains { $0 <= at(monday, 9) })
    }

    @Test func atThirteenFiftyNineLunchIsNextThenNowAtTwo() throws {
        let data = snapshot()

        let before = try active(WidgetTimelineBuilder.content(for: data, at: at(monday, 13, 59), timeZone: utc))
        #expect(before.lead == .next)
        #expect(before.primary?.title == "Chicken Caesar")
        #expect(before.minutesUntilPrimary == 1)

        let after = try active(WidgetTimelineBuilder.content(for: data, at: at(monday, 14), timeZone: utc))
        #expect(after.lead == .now)
        #expect(after.primary?.title == "Chicken Caesar")
        #expect(after.minutesUntilPrimary == nil)
        #expect(after.following?.title == "Steak salad")
        #expect(after.followingDay == nil)
    }

    @Test func countdownOnlyWithinTheHour() throws {
        let data = snapshot()
        let early = try active(WidgetTimelineBuilder.content(for: data, at: at(monday, 12), timeZone: utc))
        #expect(early.minutesUntilPrimary == nil)
        let close = try active(WidgetTimelineBuilder.content(for: data, at: at(monday, 13, 18), timeZone: utc))
        #expect(close.minutesUntilPrimary == 42)
    }

    @Test func afterDinnerTheWidgetShowsTomorrow() throws {
        let content = try active(WidgetTimelineBuilder.content(for: snapshot(), at: at(monday, 21), timeZone: utc))
        #expect(content.lead == .laterDay(tuesday))
        #expect(content.primary?.title == "Feta salad")
        #expect(content.following?.title == "Greek salad")
    }

    @Test func aCompletedMealMovesTheWidgetOn() throws {
        let plan = twoDayPlan()
        let lunch = MealSchedule(plan: plan, timeZone: utc).occurrences(on: monday)[1].key
        let content = try active(WidgetTimelineBuilder.content(for: snapshot(plan, states: [lunch: .completed]), at: at(monday, 14, 10), timeZone: utc))
        #expect(content.lead == .next)
        #expect(content.primary?.title == "Steak salad")
        #expect(content.schedule.map(\.role) == [.past, .done, .next])
    }

    @Test func dayCompleteIsReported() throws {
        let plan = twoDayPlan()
        let schedule = MealSchedule(plan: plan, timeZone: utc)
        var states: OccurrenceStates = [:]
        for occurrence in schedule.occurrences(on: monday) { states[occurrence.key] = .completed }
        let content = try active(WidgetTimelineBuilder.content(for: snapshot(plan, states: states), at: at(monday, 20), timeZone: utc))
        #expect(content.isDayComplete)
        #expect(content.remainingCount == 0)
        #expect(content.lead == .laterDay(tuesday))
    }

    @Test func aPlanThatStartsLaterSaysWhen() throws {
        let content = try active(WidgetTimelineBuilder.content(for: snapshot(twoDayPlan(start: day(2026, 10, 8))), at: at(monday, 9), timeZone: utc))
        #expect(content.lead == .planStarts(day(2026, 10, 8)))
        #expect(content.primary?.title == "Halloumi salad")
    }

    @Test func anEndedPlanSaysSo() {
        let content = WidgetTimelineBuilder.content(for: snapshot(twoDayPlan(repeats: false)), at: at(day(2026, 10, 9), 9), timeZone: utc)
        #expect(content == .planEnded(planName: "Keto", lastDay: tuesday))
    }

    @Test func noSnapshotOrNoPlanMeansNoPlan() {
        #expect(WidgetTimelineBuilder.content(for: nil, at: at(monday, 9), timeZone: utc) == .noPlan)
        #expect(WidgetTimelineBuilder.content(for: snapshot(nil), at: at(monday, 9), timeZone: utc) == .noPlan)
        #expect(WidgetTimelineBuilder.moments(for: nil, from: at(monday, 9), timeZone: utc).count == 1)
    }

    @Test func aSnapshotFromANewerAppAsksForARefresh() {
        var newer = snapshot()
        newer.version = WidgetSnapshot.currentVersion + 1
        #expect(WidgetTimelineBuilder.content(for: newer, at: at(monday, 9), timeZone: utc) == .needsRefresh)
    }

    @Test func momentsStartNowAreOrderedAndChange() {
        let now = at(monday, 9, 7)
        let moments = WidgetTimelineBuilder.moments(for: snapshot(), from: now, timeZone: utc)
        #expect(moments.first?.date == now)
        #expect(moments.map(\.date) == moments.map(\.date).sorted())
        #expect(moments.count > 10)
        #expect(moments.last.map { $0.date <= now.addingTimeInterval(WidgetTimelineBuilder.horizon) } == true)
        for (earlier, later) in zip(moments, moments.dropFirst()) {
            #expect(earlier.content != later.content)
        }
    }
}

struct WidgetSnapshotTests {
    let monday = day(2026, 10, 5)

    @Test func survivesARoundTrip() throws {
        let plan = SamplePlan.keto(startingOn: monday)
        let schedule = MealSchedule(plan: plan, timeZone: utc)
        let first = schedule.occurrences(on: monday)[0].key
        let original = WidgetSnapshot(plan: plan, states: [first: .completed], preferences: WidgetPreferences(showCalories: true), generatedAt: at(monday, 12), timeZone: utc)
        let decoded = try WidgetSnapshot.decode(original.encoded())
        #expect(decoded == original)
        #expect(decoded.occurrenceStates[first] == .completed)
        #expect(decoded.preferences.showCalories)
    }

    @Test func keepsOnlyWhatTheWidgetDraws() {
        var plan = SamplePlan.keto(startingOn: monday)
        plan.meals[0].notes = "Long private note"
        plan.meals[0].nutrition.protein = 30
        let snapshot = WidgetSnapshot(plan: plan, states: [:], preferences: WidgetPreferences(), generatedAt: at(monday, 12), timeZone: utc)
        #expect(snapshot.plan?.meals[0].notes == nil)
        #expect(snapshot.plan?.meals[0].nutrition.protein == nil)
        #expect(snapshot.plan?.meals[0].nutrition.calories == plan.meals[0].nutrition.calories)
    }

    @Test func dropsPendingAndFarAwayStates() {
        let mealID = UUID()
        let states: OccurrenceStates = [
            OccurrenceKey(mealID: mealID, day: monday): .completed,
            OccurrenceKey(mealID: mealID, day: monday.adding(days: 1)): .pending,
            OccurrenceKey(mealID: mealID, day: monday.adding(days: -30)): .completed,
            OccurrenceKey(mealID: mealID, day: monday.adding(days: 30)): .skipped,
        ]
        let snapshot = WidgetSnapshot(plan: nil, states: states, preferences: WidgetPreferences(), generatedAt: at(monday, 12), timeZone: utc)
        #expect(snapshot.states.count == 1)
    }

    @Test func corruptDataIsRejected() {
        #expect(throws: (any Error).self) { try WidgetSnapshot.decode(Data("not json".utf8)) }
        #expect(throws: (any Error).self) { try WidgetSnapshot.decode(Data("{\"version\": 1}".utf8)) }
    }

    @Test func preferencesFromAnOlderFileGetDefaults() throws {
        let json = #"{"version":1,"generatedAt":0,"states":{},"preferences":{"showCalories":true}}"#
        let decoded = try WidgetSnapshot.decode(Data(json.utf8))
        #expect(decoded.preferences.showCalories)
        #expect(decoded.preferences.showFollowingMeal)
        #expect(decoded.plan == nil)
    }

    @Test func occurrenceKeysReadBack() throws {
        let key = OccurrenceKey(mealID: UUID(), day: monday)
        #expect(OccurrenceKey(key.description) == key)
        #expect(OccurrenceKey("nonsense") == nil)
    }
}
