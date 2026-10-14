import Foundation
import Testing
import Domain

private func clockTime(_ hour: Int, _ minute: Int = 0) -> TimeOfDay {
    TimeOfDay(hour: hour, minute: minute)
}

/// What the widget draws beyond "what is next": the live line, the late start, the morning's
/// "I'm up", Smart Stack relevance and the day's header and footer.
struct WidgetLiveContentTests {
    let monday = day(2026, 10, 5)
    let tuesday = day(2026, 10, 6)

    func snapshot(_ plan: MealPlan = twoDayPlan(), states: OccurrenceStates = [:], preferences: WidgetPreferences = WidgetPreferences(), dayStarts: DayStarts = [:]) -> WidgetSnapshot {
        WidgetSnapshot(plan: plan, states: states, preferences: preferences, generatedAt: at(monday, 7), timeZone: utc, dayStarts: dayStarts)
    }

    func active(_ snapshot: WidgetSnapshot, at date: Date) throws -> WidgetDayContent {
        guard case .active(let day) = WidgetTimelineBuilder.content(for: snapshot, at: date, timeZone: utc) else {
            Issue.record("Expected an active plan")
            throw CancellationError()
        }
        return day
    }

    // MARK: Fewer entries

    @Test func aDayNeedsAHandfulOfMomentsPerMealNotOneEveryFiveMinutes() {
        let start = monday.startDate(in: utc)
        let moments = WidgetTimelineBuilder.moments(for: snapshot(), from: start, timeZone: utc, horizon: 24 * 3600)
        // Three meals: soon, a quarter of an hour before, its time and its end for each, plus the
        // morning's "I'm up" opening and closing. The five-minute countdown took 13 per meal more.
        #expect(moments.count <= 16)
        let dates = WidgetTimelineBuilder.transitionDates(for: snapshot(), from: start, timeZone: utc, horizon: 24 * 3600)
        for minutes in stride(from: 5, through: 55, by: 5) where minutes != 15 {
            #expect(!dates.contains(at(monday, 13, 60 - minutes)), "no countdown step \(minutes) minutes before lunch")
        }
    }

    @Test func aMealOnNowSaysWhenItGivesWay() throws {
        let lunch = try active(snapshot(), at: at(monday, 14, 10))
        #expect(lunch.lead == .now)
        #expect(lunch.primaryEnds == at(monday, 15))
        #expect(lunch.waitStarted == nil)

        // A longer window still gives way to the next meal.
        let long = try active(snapshot(preferences: WidgetPreferences(mealWindowMinutes: 240)), at: at(monday, 15))
        #expect(long.lead == .now)
        #expect(long.primaryEnds == at(monday, 18))
    }

    @Test func aMealAheadSaysWhenTheWaitForItBegan() throws {
        let beforeLunch = try active(snapshot(), at: at(monday, 12))
        #expect(beforeLunch.lead == .next)
        #expect(beforeLunch.primaryEnds == nil)
        #expect(beforeLunch.waitStarted == at(monday, 10), "since breakfast")

        let morning = try active(snapshot(), at: at(monday, 7))
        #expect(morning.waitStarted == at(monday, 5), "the first meal's wait starts in the morning")
    }

    @Test func soonIsTheLastHour() throws {
        #expect(try active(snapshot(), at: at(monday, 12)).isSoon == false)
        #expect(try active(snapshot(), at: at(monday, 13, 18)).isSoon)
        #expect(try active(snapshot(), at: at(monday, 14, 30)).isSoon == false, "on now, not soon")
    }

    // MARK: Smart Stack

    @Test func relevanceRisesAQuarterOfAnHourBeforeAMealUntilItGivesWay() throws {
        // One plan throughout: every call of twoDayPlan() makes meals with new ids.
        let plan = twoDayPlan()
        func score(_ hour: Int, _ minute: Int = 0, states: OccurrenceStates = [:]) -> Double {
            let date = at(monday, hour, minute)
            return WidgetTimelineBuilder.relevance(of: WidgetTimelineBuilder.content(for: snapshot(plan, states: states), at: date, timeZone: utc), at: date)
        }
        #expect(score(13, 30) == WidgetTimelineBuilder.Relevance.ordinary)
        #expect(score(13, 45) == WidgetTimelineBuilder.Relevance.mealtime)
        #expect(score(14, 30) == WidgetTimelineBuilder.Relevance.mealtime)
        #expect(score(15, 1) == WidgetTimelineBuilder.Relevance.ordinary)

        var all: OccurrenceStates = [:]
        for occurrence in MealSchedule(plan: plan, timeZone: utc).occurrences(on: monday) {
            all[occurrence.key] = .completed
        }
        #expect(score(20, states: all) == WidgetTimelineBuilder.Relevance.dayComplete)
        #expect(WidgetTimelineBuilder.relevance(of: .noPlan, at: at(monday, 14)) == WidgetTimelineBuilder.Relevance.none)
    }

    @Test func theTimelineCarriesRelevance() {
        let moments = WidgetTimelineBuilder.moments(for: snapshot(), from: at(monday, 13), timeZone: utc)
        let quarterBefore = moments.first(where: { $0.date == at(monday, 13, 45) })
        #expect(quarterBefore?.relevance == WidgetTimelineBuilder.Relevance.mealtime)
        #expect(moments.first?.relevance == WidgetTimelineBuilder.Relevance.ordinary)
    }

    // MARK: "I'm up"

    @Test func imUpIsOfferedFromFiveUntilTheMorningIsOver() throws {
        // Breakfast is at 10:00: offered from 05:00 until 14:00.
        #expect(try active(snapshot(), at: at(monday, 4, 59)).offersStartDay == false)
        #expect(try active(snapshot(), at: at(monday, 5)).offersStartDay)
        #expect(try active(snapshot(), at: at(monday, 11, 30)).offersStartDay)
        #expect(try active(snapshot(), at: at(monday, 14)).offersStartDay == false)
        let dates = Set(WidgetTimelineBuilder.transitionDates(for: snapshot(), from: monday.startDate(in: utc), timeZone: utc))
        #expect(dates.contains(at(monday, 5)))
        #expect(dates.contains(at(monday, 14)))
    }

    @Test func imUpGivesWayOnceTheDayHasBegun() throws {
        let plan = twoDayPlan()
        let breakfast = MealSchedule(plan: plan, timeZone: utc).occurrences(on: monday)[0].key
        #expect(try active(snapshot(plan, states: [breakfast: .completed]), at: at(monday, 8)).offersStartDay == false, "a meal is marked")
        let started = snapshot(dayStarts: [monday: .wokeUp(at: clockTime(7), source: .widget)])
        #expect(try active(started, at: at(monday, 8)).offersStartDay == false, "the day was started")
        let off = snapshot(preferences: WidgetPreferences(smartMealTimes: false))
        #expect(try active(off, at: at(monday, 8)).offersStartDay == false, "smart meal times are off")
    }

    // MARK: Late starts and estimates

    @Test func aMovedMealSaysHowFar() throws {
        let late = snapshot(dayStarts: [monday: DayStart(firstMeal: clockTime(12), source: .widget)])
        let day = try active(late, at: at(monday, 11))
        #expect(day.primary?.shiftMinutes == 120)
        #expect(day.primary?.isMoved == true)
        #expect(day.schedule.allSatisfy { $0.shiftMinutes >= 0 })

        let onTime = try active(snapshot(), at: at(monday, 9))
        #expect(onTime.schedule.allSatisfy { $0.shiftMinutes == 0 && !$0.isMoved })
    }

    @Test func anEstimatedEnergyKeepsItsMark() throws {
        var plan = twoDayPlan()
        let lunchIndex = try #require(plan.meals.firstIndex(where: { $0.title == "Chicken Caesar" }))
        plan.meals[lunchIndex].nutrition = Nutrition(calories: 510, estimated: true)
        let breakfastIndex = try #require(plan.meals.firstIndex(where: { $0.title == "Halloumi salad" }))
        plan.meals[breakfastIndex].nutrition = Nutrition(calories: 430)

        let day = try active(snapshot(plan), at: at(monday, 13))
        let lunch = try #require(day.primary)
        #expect(lunch.isEstimated)
        #expect(lunch.calories == 510)
        #expect(EnergyUnit.kilocalories.format(lunch.nutrition, locale: Locale(identifier: "en_US"))?.hasPrefix("≈") == true)
        #expect(day.schedule.first?.isEstimated == false)

        // Breakfast's time has gone by unmarked: it counts as planned, not eaten.
        #expect(day.energy == WidgetEnergy(eaten: 0, planned: 940, isEstimated: true))
    }

    @Test func noEnergyWithoutFigures() throws {
        #expect(try active(snapshot(), at: at(monday, 9)).energy == nil)
    }

    @Test func eatenEnergyCountsMarkedMeals() throws {
        var plan = twoDayPlan()
        for index in plan.meals.indices {
            plan.meals[index].nutrition = Nutrition(calories: 500)
        }
        let breakfast = MealSchedule(plan: plan, timeZone: utc).occurrences(on: monday)[0].key
        let energy = try #require(try active(snapshot(plan, states: [breakfast: .completed]), at: at(monday, 12)).energy)
        #expect(energy.eaten == 500)
        #expect(energy.planned == 1500)
        #expect(!energy.isEstimated)
        #expect(abs(energy.fraction - 1.0 / 3.0) < 0.0001)
    }

    // MARK: Header and footer

    @Test func theHeaderKnowsTheDayOfThePlan() throws {
        let first = try active(snapshot(), at: at(monday, 9))
        #expect(first.dayIndex == 0)
        #expect(first.dayCount == 2)
        #expect(try active(snapshot(), at: at(tuesday, 9)).dayIndex == 1)
        let later = try active(snapshot(twoDayPlan(start: day(2026, 10, 8))), at: at(monday, 9))
        #expect(later.dayIndex == nil)
    }

    @Test func aFinishedDayPointsAtTomorrowsFirstMeal() throws {
        let evening = try active(snapshot(), at: at(monday, 21))
        #expect(evening.nextDayFirst?.title == "Feta salad")
        let lunchtime = try active(snapshot(), at: at(monday, 14))
        #expect(lunchtime.nextDayFirst == nil)
    }
}

struct WidgetPlateTests {
    @Test func aListOfFoodsIsAPlate() {
        #expect(WidgetPlate.items(in: "2 eggs, 5 olives, 1 slice of cheese") == ["2 eggs", "5 olives", "1 slice of cheese"])
        #expect(WidgetPlate.items(in: "Yoğurt + ceviz + bal") == ["Yoğurt", "ceviz", "bal"])
        #expect(WidgetPlate.items(in: "eggs, olives, and cheese") == ["eggs", "olives", "cheese"])
        #expect(WidgetPlate.items(in: "peynir, zeytin ve domates; salatalık") == ["peynir", "zeytin ve domates", "salatalık"])
    }

    @Test func aDecimalCommaIsNotASeparator() {
        #expect(WidgetPlate.items(in: "1,5 dilim ekmek, 2 yumurta, 10 zeytin") == ["1,5 dilim ekmek", "2 yumurta", "10 zeytin"])
    }

    @Test func aDishIsNotAPlate() {
        #expect(WidgetPlate.items(in: "Feta, cucumber and walnut salad").isEmpty)
        #expect(WidgetPlate.items(in: "Grilled Chicken Caesar Salad").isEmpty)
        #expect(WidgetPlate.items(in: "Soup, then a long walk around the park before the evening, salad").isEmpty, "a sentence is not a food")
    }

    @Test func theItemReadsItsTitle() {
        let meal = Meal(dayIndex: 0, type: .breakfast, time: clockTime(8), title: "2 eggs, 5 olives, 1 slice of cheese, tomato")
        let plan = MealPlan(name: "One", schedule: PlanSchedule(startDay: day(2026, 10, 5), length: 1, repeats: true), meals: [meal])
        let occurrence = MealSchedule(plan: plan, timeZone: utc).occurrences(on: day(2026, 10, 5))[0]
        #expect(WidgetMealItem(occurrence: occurrence, role: .next).plateItems.count == 4)
    }
}

struct WidgetPreferencesUpgradeTests {
    @Test func anOlderFileGetsTheNewDefaults() throws {
        let json = #"{"version":1,"generatedAt":0,"states":{},"preferences":{"showCalories":true}}"#
        let preferences = try WidgetSnapshot.decode(Data(json.utf8)).preferences
        #expect(preferences.smartMealTimes)
        #expect(preferences.hidesMealNamesWhenLocked == false)
        #expect(preferences.showDoneButton, "on by default, as in the app's settings")
        #expect(preferences.showCalories)
    }

    @Test func theNewFieldsSurviveARoundTrip() throws {
        let original = WidgetSnapshot(
            plan: twoDayPlan(),
            states: [:],
            preferences: WidgetPreferences(showDoneButton: false, smartMealTimes: false, hidesMealNamesWhenLocked: true),
            generatedAt: at(day(2026, 10, 5), 9),
            timeZone: utc
        )
        let decoded = try WidgetSnapshot.decode(original.encoded())
        #expect(decoded == original)
        #expect(decoded.preferences.hidesMealNamesWhenLocked)
        #expect(decoded.preferences.smartMealTimes == false)
        #expect(decoded.preferences.showDoneButton == false)
    }

    @Test func theAppsDefaultsAndTheWidgetsAgree() {
        #expect(AppSettings().widgetPreferences.showDoneButton == WidgetPreferences().showDoneButton)
        #expect(AppSettings().widgetPreferences.typeface == WidgetPreferences().typeface)
    }

    @Test func anOlderFileKeepsTheStandardType() throws {
        let json = #"{"version":1,"generatedAt":0,"states":{},"preferences":{"accent":"blue"}}"#
        let preferences = try WidgetSnapshot.decode(Data(json.utf8)).preferences
        #expect(preferences.typeface == .standard)
        #expect(preferences.accent == .blue)
    }

    @Test func aTypefaceThisVersionDoesNotKnowFallsBack() throws {
        let json = #"{"version":1,"generatedAt":0,"states":{},"preferences":{"typeface":"script","accent":"gold"}}"#
        let preferences = try WidgetSnapshot.decode(Data(json.utf8)).preferences
        #expect(preferences.typeface == .standard)
        #expect(preferences.accent == .gold)
    }

    @Test func theBlackAndGoldLookReachesTheWidget() throws {
        var settings = AppSettings()
        settings.widgetAccent = .gold
        settings.widgetBackground = .dark
        settings.widgetTypeface = .serif
        let reread = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(reread.widgetTypeface == .serif)
        let preferences = reread.widgetPreferences
        #expect(preferences.accent == .gold)
        #expect(preferences.background == .dark)
        #expect(preferences.typeface == .serif)
    }

    @Test func settingsSavedBeforeTheFontPickerKeepTheStandardType() throws {
        let json = #"{"widgetAccent":"green","widgetBackground":"soft"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.widgetTypeface == .standard)
        #expect(settings.widgetAccent == .green)
    }
}

/// Every word drawn in the person's colour reads at 4.5:1 or better, on every background it can
/// be drawn on, in Light and Dark Mode.
struct WidgetPaletteTests {
    static let minimum = 4.5

    @Test(arguments: WidgetAccent.allCases)
    func accentWordsReadOnSystemAndSoft(_ accent: WidgetAccent) {
        let palette = accent.palette
        let wash = WidgetPalette.washOpacity
        let light = WidgetPalette.lightBackground
        let soft = palette.light.over(light, opacity: wash)
        for background in [light, soft, palette.light.over(soft, opacity: wash)] {
            #expect(palette.inkLight.contrast(with: background) >= Self.minimum, "\(accent) ink in Light Mode")
        }

        let dark = WidgetPalette.darkBackground
        let softDark = palette.dark.over(dark, opacity: wash)
        let darkStyle = WidgetPalette.darkStyleBackground
        for background in [dark, softDark, palette.dark.over(softDark, opacity: wash), darkStyle, palette.dark.over(darkStyle, opacity: wash)] {
            #expect(palette.inkDark.contrast(with: background) >= Self.minimum, "\(accent) ink in Dark Mode")
        }
    }

    @Test(arguments: WidgetAccent.allCases)
    func whiteWordsReadOnBold(_ accent: WidgetAccent) {
        let palette = accent.palette
        let white = WidgetRGB.white
        #expect(white.contrast(with: palette.boldTop) >= Self.minimum, "\(accent) Bold, top")
        #expect(white.contrast(with: palette.boldBottom) >= Self.minimum, "\(accent) Bold, bottom")
        #expect(white.over(palette.boldTop, opacity: WidgetPalette.boldSecondaryOpacity).contrast(with: palette.boldTop) >= Self.minimum, "\(accent) Bold, secondary words")
        #expect(white.contrast(with: WidgetRGB.black.over(palette.boldTop, opacity: WidgetPalette.boldShadeOpacity)) >= Self.minimum, "\(accent) Bold, chip")
    }

    @Test func contrastIsMeasuredTheWCAGWay() {
        #expect(abs(WidgetRGB.white.contrast(with: .black) - 21) < 0.01)
        #expect(abs(WidgetRGB.white.contrast(with: .white) - 1) < 0.0001)
    }
}
