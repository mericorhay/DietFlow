import AppIntents
import Foundation
import Persistence

/// Hands pasted plan text to the app, which opens it for review. Never saves on its own: every
/// import is reviewed first.
struct ImportPlanIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "intent.importPlan.title"
    nonisolated static var description: IntentDescription { IntentDescription("intent.importPlan.description") }
    nonisolated static let openAppWhenRun = true

    @Parameter(title: "intent.parameter.planText", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try PendingImportInbox.put(text)
        return .result()
    }
}

/// The phrases Siri and Spotlight offer without any setup.
nonisolated struct DietFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowNextMealIntent(),
            phrases: [
                "What's my next meal in \(.applicationName)",
                "Show my next meal in \(.applicationName)",
            ],
            shortTitle: "shortcut.nextMeal",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: MarkMealDoneIntent(),
            phrases: [
                "Mark my meal done in \(.applicationName)",
                "I ate my meal in \(.applicationName)",
            ],
            shortTitle: "shortcut.markDone",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: AddMealIntent(),
            phrases: [
                "Add a meal in \(.applicationName)",
            ],
            shortTitle: "shortcut.addMeal",
            systemImageName: "plus.circle"
        )
    }
}
