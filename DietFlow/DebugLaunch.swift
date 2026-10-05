#if DEBUG
import Foundation
import AppCore
import Domain

/// Launch arguments that open the app in a known state, so every screen can be checked — in every
/// language, in dark mode, at large text sizes — without tapping through. Debug builds only; CI
/// uses them for screenshots (scripts/ci-screenshots.sh).
///
///     -DebugSeed sample|empty|onboarding   in-memory data: the sample plan, nothing, or first run
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
        case "empty":
            return .preview(withSample: false, settings: AppSettings(hasCompletedOnboarding: true))
        case "onboarding":
            return .preview(withSample: false, settings: AppSettings())
        default:
            return nil
        }
    }
}
#endif
