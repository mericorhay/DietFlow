import Foundation
import Testing
import Domain

struct CalendarDayTests {
    @Test func readsAndWritesTheStoredForm() {
        #expect(CalendarDay("2026-10-05") == day(2026, 10, 5))
        #expect(day(2026, 3, 8).description == "2026-03-08")
        #expect(CalendarDay("2026-02-30") == nil)
        #expect(CalendarDay("2026-13-01") == nil)
        #expect(CalendarDay("yesterday") == nil)
        #expect(CalendarDay("2028-02-29") == day(2028, 2, 29))
    }

    @Test func arithmeticCrossesMonthsAndYears() {
        #expect(day(2026, 12, 31).adding(days: 1) == day(2027, 1, 1))
        #expect(day(2026, 3, 1).adding(days: -1) == day(2026, 2, 28))
        #expect(day(2026, 10, 5).days(to: day(2026, 10, 19)) == 14)
        #expect(day(2026, 10, 19).days(to: day(2026, 10, 5)) == -14)
    }

    @Test func countsWholeDaysAcrossDaylightSaving() {
        // 8 March 2026 is 23 hours long in New York; it still counts as one day.
        #expect(day(2026, 3, 7).days(to: day(2026, 3, 9)) == 2)
        #expect(day(2026, 10, 31).days(to: day(2026, 11, 2)) == 2)
    }

    @Test func weekStartsWhereTheCalendarSays() {
        let wednesday = day(2026, 10, 7)
        #expect(wednesday.weekday == 4)
        #expect(wednesday.week(startingOn: 2).first == day(2026, 10, 5))
        #expect(wednesday.week(startingOn: 1).first == day(2026, 10, 4))
        #expect(wednesday.week(startingOn: 7).first == day(2026, 10, 3))
        #expect(wednesday.week(startingOn: 2).count == 7)
    }

    @Test(arguments: ["America/New_York", "Europe/Istanbul", "Asia/Tokyo", "America/Santiago", "Australia/Lord_Howe", "Pacific/Kiritimati"])
    func everyDayStartsOnItself(zoneIdentifier: String) throws {
        let zone = try #require(TimeZone(identifier: zoneIdentifier))
        var current = day(2026, 1, 1)
        for _ in 0..<366 {
            let start = current.startDate(in: zone)
            #expect(CalendarDay(start, in: zone) == current)
            #expect(CalendarDay(start.addingTimeInterval(-1), in: zone) == current.adding(days: -1))
            current = current.adding(days: 1)
        }
    }
}

struct DaylightSavingTests {
    let newYork = TimeZone(identifier: "America/New_York")!

    @Test func aMealInTheSkippedHourMovesPastTheJump() {
        // Clocks go from 02:00 to 03:00 on 8 March 2026.
        let date = TimeOfDay(hour: 2, minute: 30).date(on: day(2026, 3, 8), in: newYork)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        #expect(CalendarDay(date, in: newYork) == day(2026, 3, 8))
        #expect(calendar.component(.hour, from: date) == 3)
    }

    @Test func mealsOnTheShortDayKeepTheirClockTimes() {
        let date = TimeOfDay(hour: 10, minute: 0).date(on: day(2026, 3, 8), in: newYork)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        #expect(calendar.component(.hour, from: date) == 10)
        // Midnight to ten o'clock is nine hours long that day.
        #expect(date.timeIntervalSince(day(2026, 3, 8).startDate(in: newYork)) == 9 * 3600)
    }

    @Test func aMealInTheRepeatedHourUsesItsFirstPass() {
        // 01:30 happens twice on 1 November 2026; the first is still daylight time, UTC-4.
        let date = TimeOfDay(hour: 1, minute: 30).date(on: day(2026, 11, 1), in: newYork)
        #expect(date == at(day(2026, 11, 1), 5, 30, in: utc))
    }

    @Test func theScheduleRunsThroughTheJump() throws {
        let plan = MealPlan(
            name: "Daily",
            schedule: PlanSchedule(startDay: day(2026, 3, 1), length: 1, repeats: true),
            meals: [meal(0, .breakfast, 8, 0, "Eggs"), meal(0, .dinner, 19, 0, "Fish")]
        )
        let schedule = MealSchedule(plan: plan, timeZone: newYork)
        let jumpDay = day(2026, 3, 8)
        let late = try #require(schedule.focus(now: at(jumpDay, 22, 0, in: newYork)))
        #expect(late.occurrence.day == day(2026, 3, 9))
        let early = try #require(schedule.focus(now: at(jumpDay, 3, 30, in: newYork)))
        #expect(early.occurrence.meal.title == "Eggs")
        #expect(early.occurrence.day == jumpDay)
    }
}

struct TimeZoneChangeTests {
    @Test func theSameInstantIsADifferentPlanDayInAnotherZone() throws {
        let plan = twoDayPlan(start: day(2026, 10, 5))
        // 23:30 UTC on 5 October: Monday evening in Los Angeles, Tuesday morning in Tokyo.
        let instant = at(day(2026, 10, 5), 23, 30, in: utc)
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(MealSchedule(plan: plan, timeZone: utc).dayIndex(on: CalendarDay(instant, in: utc)) == 0)
        #expect(MealSchedule(plan: plan, timeZone: tokyo).dayIndex(on: CalendarDay(instant, in: tokyo)) == 1)
        #expect(MealSchedule(plan: plan, timeZone: losAngeles).dayIndex(on: CalendarDay(instant, in: losAngeles)) == 0)

        let inTokyo = try #require(MealSchedule(plan: plan, timeZone: tokyo).focus(now: instant))
        #expect(inTokyo.occurrence.meal.title == "Feta salad")
        let inLosAngeles = try #require(MealSchedule(plan: plan, timeZone: losAngeles).focus(now: instant))
        #expect(inLosAngeles.occurrence.meal.title == "Steak salad")
    }

    @Test func mealTimesFollowTheLocalClock() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let lunch = TimeOfDay(hour: 14, minute: 0)
        let inTokyo = lunch.date(on: day(2026, 10, 5), in: tokyo)
        let inUTC = lunch.date(on: day(2026, 10, 5), in: utc)
        #expect(inUTC.timeIntervalSince(inTokyo) == 9 * 3600)
    }
}

struct TimeOfDayTests {
    @Test func clampsAndWraps() {
        #expect(TimeOfDay(hour: 25, minute: 70) == TimeOfDay(hour: 23, minute: 59))
        #expect(TimeOfDay(minutesSinceMidnight: 1500) == TimeOfDay(hour: 1, minute: 0))
        #expect(TimeOfDay(minutesSinceMidnight: -30) == TimeOfDay(hour: 23, minute: 30))
        #expect(TimeOfDay(hour: 9, minute: 5).isoString == "09:05")
    }
}
