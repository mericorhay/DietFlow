import Foundation
import SwiftUI
import AppCore
import DesignSystem
import Domain

/// Creating a plan, or changing an existing plan's name and when it runs.
public struct PlanSetupScreen: View {
    public enum Mode {
        case new
        case edit(MealPlan)
    }

    @Environment(MealPlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name: String
    @State private var kind: PlanKind
    @State private var startDate: Date
    @State private var length: Int
    @State private var repeats: Bool
    @State private var confirmsShortening = false
    private let mode: Mode
    private let onSaved: () -> Void

    public init(mode: Mode, onSaved: @escaping () -> Void = {}) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _kind = State(initialValue: .cycle)
            _startDate = State(initialValue: CalendarDay.today().middayDate())
            _length = State(initialValue: 7)
            _repeats = State(initialValue: true)
        case .edit(let plan):
            _name = State(initialValue: plan.name)
            _kind = State(initialValue: plan.schedule.kind)
            _startDate = State(initialValue: plan.schedule.startDay.middayDate())
            _length = State(initialValue: plan.schedule.length)
            _repeats = State(initialValue: plan.schedule.repeats)
        }
    }

    public var body: some View {
        Form {
            Section {
                TextField(text: $name) {
                    Text("planSetup.name", bundle: .module)
                }
            }

            Section {
                Picker(selection: $kind) {
                    Text("planSetup.kind.cycle", bundle: .module).tag(PlanKind.cycle)
                    Text("planSetup.kind.fixedDates", bundle: .module).tag(PlanKind.fixedDates)
                } label: {
                    Text("planSetup.kind", bundle: .module)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                DatePicker(selection: $startDate, displayedComponents: .date) {
                    Text("planSetup.start", bundle: .module)
                }

                Stepper(value: $length, in: 1...PlanSchedule.maximumLength) {
                    LabeledContent {
                        Text(String(localized: "planSetup.lengthValue", defaultValue: "\(length) days", bundle: .module))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } label: {
                        Text("planSetup.length", bundle: .module)
                    }
                }

                if kind == .cycle {
                    Toggle(isOn: $repeats) {
                        Text("planSetup.repeats", bundle: .module)
                    }
                }
            } footer: {
                Text(footer)
            }
        }
        .animation(AppMotion.animation(AppMotion.snappy, reduceMotion: reduceMotion), value: kind)
        .navigationTitle(isNew ? Text("planSetup.newTitle", bundle: .module) : Text("planSetup.editTitle", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("planSetup.cancel", bundle: .module)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: attemptSave) {
                    Text("planSetup.save", bundle: .module)
                }
            }
        }
        .confirmationDialog(Text("planSetup.shorten.title", bundle: .module), isPresented: $confirmsShortening, titleVisibility: .visible) {
            Button(role: .destructive, action: save) {
                Text("planSetup.shorten.confirm", bundle: .module)
            }
        } message: {
            Text(String(localized: "planSetup.shorten.message", defaultValue: "Meals after day \(length) will be deleted.", bundle: .module))
        }
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private var footer: String {
        switch kind {
        case .fixedDates:
            return String(localized: "planSetup.footer.fixedDates", bundle: .module)
        case .cycle:
            if repeats {
                return String(localized: "planSetup.footer.repeats", defaultValue: "After day \(length), the plan starts again from day 1.", bundle: .module)
            }
            return String(localized: "planSetup.footer.once", defaultValue: "The plan ends after day \(length).", bundle: .module)
        }
    }

    private func attemptSave() {
        if case .edit(let plan) = mode, plan.meals.contains(where: { $0.dayIndex >= length }) {
            confirmsShortening = true
        } else {
            save()
        }
    }

    private func save() {
        let schedule = PlanSchedule(kind: kind, startDay: CalendarDay(startDate), length: length, repeats: repeats)
        let fallbackName = String(localized: "planSetup.defaultName", bundle: .module)
        withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
            switch mode {
            case .new:
                let plan = MealPlan(name: name.trimmedNonEmpty ?? fallbackName, schedule: schedule)
                _ = try? store.createPlan(plan)
            case .edit(var plan):
                plan.name = name.trimmedNonEmpty ?? plan.name
                plan.schedule = schedule
                plan.meals = plan.meals.filter { $0.dayIndex < schedule.length }
                _ = try? store.replacePlan(plan)
            }
        }
        dismiss()
        onSaved()
    }
}
