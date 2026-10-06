import Foundation
import SwiftUI
import AIServices
import DesignSystem
import Domain

/// Asking the assistant for a new plan: how many days, how many meals a day, and whatever the
/// person wants to say about how they eat. What comes back is shown for review like any import.
struct AssistantPlanScreen: View {
    let onContinue: (PlanWishes) -> Void
    @State private var wishes = PlanWishes()
    @FocusState private var isWritingWishes: Bool

    var body: some View {
        Form {
            Section {
                Stepper(value: $wishes.days, in: PlanWishes.dayRange) {
                    LabeledContent {
                        Text(String(localized: "import.assistant.create.daysValue", defaultValue: "\(wishes.days) days", bundle: .module))
                            .monospacedDigit()
                    } label: {
                        Text("import.assistant.create.days", bundle: .module)
                    }
                }
                Stepper(value: $wishes.mealsPerDay, in: PlanWishes.mealRange) {
                    LabeledContent {
                        Text(String(localized: "import.assistant.create.mealsValue", defaultValue: "\(wishes.mealsPerDay) a day", bundle: .module))
                            .monospacedDigit()
                    } label: {
                        Text("import.assistant.create.meals", bundle: .module)
                    }
                }
            }

            Section {
                TextField(text: $wishes.wishes, axis: .vertical) {
                    Text("import.assistant.create.wishes.placeholder", bundle: .module)
                }
                .lineLimit(4...10)
                .focused($isWritingWishes)
            } header: {
                Text("import.assistant.create.wishes.header", bundle: .module)
            } footer: {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    if wishes.wishes.count > PlanWishes.wishesLimit {
                        Text(String(localized: "import.assistant.create.wishes.tooLong", defaultValue: "This is \(wishes.wishes.count) characters; up to \(PlanWishes.wishesLimit) are read.", bundle: .module))
                            .foregroundStyle(.red)
                    }
                    // A plan written by a model is everyday meal planning, and says so before it is asked for.
                    Text("import.assistant.create.disclaimer", bundle: .module)
                }
            }
        }
        .navigationTitle(Text("import.assistant.create.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    isWritingWishes = false
                    onContinue(wishes)
                } label: {
                    Text("import.assistant.create.continue", bundle: .module)
                }
                .disabled(wishes.wishes.count > PlanWishes.wishesLimit)
            }
        }
    }
}
