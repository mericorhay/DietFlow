import Foundation
import SwiftUI
import AppCore
import DesignSystem
import Domain

/// Cooking one meal, step by step: what goes in and what could go in instead, then one step at a
/// time with its timer, and at the end, marking the meal eaten. The assistant writes the recipe
/// (`MealAssistantModel.recipe`); a recipe written once opens again for free.
///
/// Shown over everything by the app, which owns its presentation so the Plus screen can be shown
/// on top of it when an allowance runs out.
public struct CookModeScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(MealAssistantModel.self) private var assistant
    private let key: OccurrenceKey
    private let onClose: () -> Void

    /// - Parameters:
    ///   - key: the meal, on the day it is being cooked for.
    ///   - onClose: closes the screen; called once, whichever way it ends.
    public init(occurrence key: OccurrenceKey, onClose: @escaping () -> Void) {
        self.key = key
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Text(verbatim: store.occurrence(for: key)?.meal.title ?? "")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(Text("cook.close", bundle: .module))
                    }
                }
        }
    }
}
