import Foundation
import Testing
import Domain

/// How the widget keeps itself current between visits to the app: enough moments to play back on
/// its own, and a request for more before they run out.
struct WidgetReloadTests {
    private let zone = TimeZone(secondsFromGMT: 0)!
    private let start = CalendarDay(year: 2026, month: 10, day: 5)

    private func snapshot(mealsPerDay: Int, generatedAt: Date) -> WidgetSnapshot {
        let meals = (0..<mealsPerDay).map { index in
            Meal(dayIndex: 0, type: .snack, time: TimeOfDay(minutesSinceMidnight: 6 * 60 + index * (16 * 60 / max(mealsPerDay, 1))), title: "Meal \(index)")
        }
        let plan = MealPlan(name: "Plan", schedule: PlanSchedule(startDay: start, length: 1, repeats: true), meals: meals)
        return WidgetSnapshot(plan: plan, states: [:], preferences: WidgetPreferences(), generatedAt: generatedAt, timeZone: zone)
    }

    @Test func anOrdinaryDayReachesWellPastTheNextReload() {
        let now = TimeOfDay(hour: 7, minute: 0).date(on: start, in: zone)
        let moments = WidgetTimelineBuilder.moments(for: snapshot(mealsPerDay: 5, generatedAt: now), from: now, timeZone: zone)
        let reload = WidgetTimelineBuilder.reloadDate(after: moments, from: now)

        #expect(moments.count < WidgetTimelineBuilder.momentLimit)
        #expect(reload == now.addingTimeInterval(WidgetTimelineBuilder.reloadInterval))
        // The moments cover the whole wait and more, so the widget never sits on a stale face.
        #expect(moments.last!.date > reload)
    }

    @Test func momentsAreInOrderAndStartNow() {
        let now = TimeOfDay(hour: 7, minute: 0).date(on: start, in: zone)
        let moments = WidgetTimelineBuilder.moments(for: snapshot(mealsPerDay: 5, generatedAt: now), from: now, timeZone: zone)
        #expect(moments.first?.date == now)
        #expect(zip(moments, moments.dropFirst()).allSatisfy { $0.date < $1.date })
        // No two neighbours look the same: each one is a change worth an entry.
        #expect(zip(moments, moments.dropFirst()).allSatisfy { $0.content != $1.content })
    }

    @Test func whenTheMomentsRunOutBeforeTheReloadItIsAskedForSooner() {
        let now = TimeOfDay(hour: 7, minute: 0).date(on: start, in: zone)
        // A cap low enough to be reached within the morning.
        let limit = 20
        let moments = WidgetTimelineBuilder.moments(for: snapshot(mealsPerDay: 5, generatedAt: now), from: now, timeZone: zone, limit: limit)
        let reload = WidgetTimelineBuilder.reloadDate(after: moments, from: now, limit: limit)

        #expect(moments.count == limit)
        #expect(moments.last!.date < now.addingTimeInterval(WidgetTimelineBuilder.reloadInterval))
        // Asked for again when the last moment comes up, not hours after it.
        #expect(reload == moments.last!.date)
    }

    @Test func evenACrowdedDayStaysUnderTheCap() {
        // A meal every sixteen minutes all day: far more than any plan, and still not enough
        // moments to hit the cap, because moments that look the same are merged.
        let now = TimeOfDay(hour: 5, minute: 0).date(on: start, in: zone)
        let moments = WidgetTimelineBuilder.moments(for: snapshot(mealsPerDay: 60, generatedAt: now), from: now, timeZone: zone)
        #expect(moments.count < WidgetTimelineBuilder.momentLimit)
        #expect(moments.last!.date > now.addingTimeInterval(WidgetTimelineBuilder.reloadInterval))
    }

    @Test func aReloadIsNeverAskedForWithinAQuarterOfAnHour() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let crowded = (0..<WidgetTimelineBuilder.momentLimit).map { WidgetMoment(date: now.addingTimeInterval(Double($0)), content: .noPlan) }
        #expect(WidgetTimelineBuilder.reloadDate(after: crowded, from: now) == now.addingTimeInterval(15 * 60))
    }

    @Test func withNoPlanThereIsOneMomentAndTheRegularReload() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let moments = WidgetTimelineBuilder.moments(for: nil, from: now, timeZone: zone)
        #expect(moments.map(\.content) == [.noPlan])
        #expect(WidgetTimelineBuilder.reloadDate(after: moments, from: now) == now.addingTimeInterval(WidgetTimelineBuilder.reloadInterval))
    }

    @Test func aMealMarkedDoneOnTheWidgetIsNoLongerInFront() {
        let now = TimeOfDay(hour: 7, minute: 0).date(on: start, in: zone)
        let open = snapshot(mealsPerDay: 3, generatedAt: now)
        guard case .active(let before) = WidgetTimelineBuilder.content(for: open, at: now, timeZone: zone), let first = before.primary else {
            Issue.record("expected an active day with a meal in front")
            return
        }
        // What the Done button writes: the same plan, with that meal's state recorded.
        let marked = WidgetSnapshot(plan: open.plan, states: [first.key: .completed], preferences: open.preferences, generatedAt: now, timeZone: zone)
        guard case .active(let after) = WidgetTimelineBuilder.content(for: marked, at: now, timeZone: zone) else {
            Issue.record("expected an active day")
            return
        }
        #expect(after.primary?.key != first.key)
        #expect(after.remainingCount == before.remainingCount - 1)
    }
}
