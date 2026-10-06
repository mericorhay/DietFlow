#if DEBUG
import Foundation
import AIServices
import AppCore
import Domain
import Purchases

/// Launch arguments that open the app in a known state, so every screen can be checked — in every
/// language, in dark mode, at large text sizes — without tapping through. Debug builds only; CI
/// uses them for screenshots (scripts/ci-screenshots.sh).
///
///     -DebugSeed sample|now|empty|onboarding
///                                          in-memory data: the sample plan; a day built around the
///                                          current time (one meal done, one on now, one next); nothing;
///                                          or first run
///     -DebugTab today|plan|widgets
///     -DebugSheet settings|import|newMeal|newPlan|plus|plusIntro
///     -DebugMeal next                      opens the meal in front on Today
///     -DebugOnboardingPage 0…2
///     -DebugPlus monthly|trial|yearly|lifetime
///                                          as if that were held, for Settings' Plus section
///     -DebugWidgetLook <colour>.<tone>     e.g. blue.bold, green.soft: the widget's colour and tone
enum DebugLaunch {
    /// The Plus screen without the App Store: the prices as set in App Store Connect, in dollars.
    static func standInStore(entitlement: PlusEntitlement?) -> PlusStore {
        PlusStore(
            standInOffers: [
                .init(id: PlusStore.monthlyID, kind: .monthly, displayPrice: "$3.99", trial: entitlement == nil ? BillingCycle.Span(value: 7, unit: .day) : nil),
                .init(id: PlusStore.yearlyID, kind: .yearly, displayPrice: "$24.99", pricePerMonth: "$2.08"),
                .init(id: PlusStore.lifetimeID, kind: .lifetime, displayPrice: "$34.99"),
            ],
            yearlySavingPercent: 48,
            entitlement: entitlement
        )
    }

    static func seededEntitlement(now: Date = .now) -> PlusEntitlement? {
        let started = now.addingTimeInterval(-3 * 86_400)
        switch value("DebugPlus") {
        case "monthly":
            return PlusEntitlement(kind: .monthly, periodStart: started, periodEnd: BillingCycle.date(byAdding: .init(value: 1, unit: .month), to: started), willRenew: true, isTrial: false)
        case "trial":
            return PlusEntitlement(kind: .monthly, periodStart: started, periodEnd: BillingCycle.date(byAdding: .init(value: 7, unit: .day), to: started), willRenew: true, isTrial: true)
        case "yearly":
            return PlusEntitlement(kind: .yearly, periodStart: started, periodEnd: BillingCycle.date(byAdding: .init(value: 1, unit: .year), to: started), willRenew: false, isTrial: false)
        case "lifetime":
            return PlusEntitlement(kind: .lifetime, periodStart: started, periodEnd: nil, willRenew: false, isTrial: false)
        default:
            return nil
        }
    }

    /// An assistant that is there to be shown and reaches nothing: its rows appear in screenshots.
    static func standInAssistant() -> PlanAssistantClient? {
        guard let url = URL(string: "https://assistant.invalid") else { return nil }
        return PlanAssistantClient(endpoint: AssistantEndpoint(url: url, appToken: ""), installID: "debug")
    }

    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-\(name)"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// A store holding only what the seed asks for, or nil for the real one. Seeded stores live in
    /// memory and never touch the person's data, settings or widget.
    static func seededStore() -> MealPlanStore? {
        let store: MealPlanStore
        switch value("DebugSeed") {
        case "sample":
            store = .preview(withSample: true, settings: AppSettings(hasCompletedOnboarding: true))
        case "now":
            store = storeAroundNow()
        case "empty":
            store = .preview(withSample: false, settings: AppSettings(hasCompletedOnboarding: true))
        case "onboarding":
            store = .preview(withSample: false, settings: AppSettings())
        default:
            return nil
        }
        if let look = value("DebugWidgetLook")?.split(separator: ".").map(String.init), look.count == 2 {
            store.updateSettings { settings in
                settings.widgetAccent = WidgetAccent(rawValue: look[0]) ?? settings.widgetAccent
                settings.widgetBackground = WidgetBackgroundStyle(rawValue: look[1]) ?? settings.widgetBackground
            }
        }
        return store
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
