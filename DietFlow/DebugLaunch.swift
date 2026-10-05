#if DEBUG
import Foundation
import AppCore
import Domain

/// Launch arguments that open the app in a known state, so every screen can be checked — in every
/// language, in dark mode, at large text sizes — without tapping through. Debug builds only; CI
/// uses them for screenshots (scripts/ci-screenshots.sh).
///
///     -DebugSeed sample|now|empty|onboarding
///                                          in-memory data: the sample plan; a day built around the
///                                          current time (one meal done, one on now, one next); nothing;
///                                          or first run
///     -DebugTab today|plan|widgets
///     -DebugSheet settings|import|newMeal|newPlan
///     -DebugMeal next                      opens the meal in front on Today
///     -DebugOnboardingPage 0…2
enum DebugLaunch {
    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-\(name)"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// A store holding only what the seed asks for, or nil for the real one. Seeded stores live in
    /// memory and never touch the person's data, settings or widget.
    static func seededStore() -> MealPlanStore? {
        switch value("DebugSeed") {
        case "sample":
            return .preview(withSample: true, settings: AppSettings(hasCompletedOnboarding: true))
        case "now":
            return storeAroundNow()
        case "empty":
            return .preview(withSample: false, settings: AppSettings(hasCompletedOnboarding: true))
        case "onboarding":
            return .preview(withSample: false, settings: AppSettings())
        default:
            return nil
        }
    }

    /// Today's meals placed around the current time, so the screens show every state at once:
    /// breakfast done, lunch on now, a snack next, dinner later.
    private static func storeAroundNow(now: Date = .now) -> MealPlanStore {
        let store = MealPlanStore.preview(withSample: false, settings: AppSettings(hasCompletedOnboarding: true))
        let minutes = Calendar.current.dateComponents([.hour, .minute], from: now)
        let current = (minutes.hour ?? 12) * 60 + (minutes.minute ?? 0)
        func at(_ offset: Int) -> TimeOfDay { TimeOfDay(minutesSinceMidnight: current + offset) }
        let sample = SamplePlan.keto(startingOn: .today())
        let firstDay = sample.meals.filter { $0.dayIndex == 0 }.sorted { $0.time < $1.time }
        let offsets = [-180, -20, 40, 240]
        var plan = sample
        plan.meals = sample.meals.filter { $0.dayIndex != 0 }
        for (meal, offset) in zip(firstDay, offsets) {
            var moved = meal
            moved.time = at(offset)
            plan.meals.append(moved)
        }
        store.attempt { try store.createPlan(plan) }
        if let first = firstDay.first {
            store.attempt { try store.markMealCompleted(OccurrenceKey(mealID: first.id, day: .today())) }
        }
        return store
    }
}
#endif
