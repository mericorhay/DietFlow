import Foundation
import SwiftUI
import UIKit
import AppCore
import DesignSystem
import Domain

/// Adding or editing one meal of the plan, with native form controls. Only the name is required.
public struct MealEditorScreen: View {
    public enum Mode {
        /// A new meal on plan day `dayIndex` (zero-based).
        case new(dayIndex: Int)
        case edit(Meal)
    }

    @Environment(MealPlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: MealDraft
    @State private var confirmsDelete = false
    /// The time the form chose for a new meal. While the person has not changed it, picking a type
    /// moves the time to that type's usual hour.
    @State private var suggestedTime: Date?
    @FocusState private var focusedField: Field?
    private let mode: Mode
    private let onDeleted: () -> Void

    private enum Field: Hashable {
        case title
    }

    public init(mode: Mode, onDeleted: @escaping () -> Void = {}) {
        self.mode = mode
        self.onDeleted = onDeleted
        switch mode {
        case .new(let dayIndex):
            _draft = State(initialValue: MealDraft(dayIndex: dayIndex))
        case .edit(let meal):
            _draft = State(initialValue: MealDraft(meal))
        }
    }

    public var body: some View {
        Form {
            Section {
                Picker(selection: typeBinding) {
                    ForEach(MealType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                } label: {
                    Text("meal.editor.type", bundle: .module)
                }
                if draft.type == .other {
                    TextField(text: $draft.customTypeName) {
                        Text("meal.editor.customType", bundle: .module)
                    }
                }
                DatePicker(selection: $draft.time, displayedComponents: .hourAndMinute) {
                    Text("meal.editor.time", bundle: .module)
                }
                if let plan = store.activePlan, plan.schedule.length > 1 {
                    Picker(selection: $draft.dayIndex) {
                        ForEach(0..<plan.schedule.length, id: \.self) { index in
                            Text(dayLabel(index, plan: plan)).tag(index)
                        }
                    } label: {
                        Text("meal.editor.day", bundle: .module)
                    }
                }
            }

            Section {
                TextField(text: $draft.title) {
                    Text("meal.editor.title", bundle: .module)
                }
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
                TextField(text: $draft.details, axis: .vertical) {
                    Text("meal.editor.details", bundle: .module)
                }
                .lineLimit(1...5)
                TextField(text: $draft.portion) {
                    Text("meal.editor.portion", bundle: .module)
                }
            }

            Section {
                numberRow(label: "meal.nutrition.energy", unit: energySymbol, value: energyBinding, decimals: false)
                numberRow(label: "meal.nutrition.protein", unit: UnitMass.grams.symbol, value: $draft.protein, decimals: true)
                numberRow(label: "meal.nutrition.carbohydrates", unit: UnitMass.grams.symbol, value: $draft.carbohydrates, decimals: true)
                numberRow(label: "meal.nutrition.fat", unit: UnitMass.grams.symbol, value: $draft.fat, decimals: true)
            } header: {
                Text("meal.section.nutrition", bundle: .module)
            } footer: {
                Text("meal.editor.nutritionFooter", bundle: .module)
            }

            Section {
                Picker(selection: $draft.reminder) {
                    Text(String(localized: "meal.reminder.default", defaultValue: "Default (\(store.settings.defaultReminder.displayName))", bundle: .module))
                        .tag(ReminderOffset?.none)
                    ForEach(ReminderOffset.allCases, id: \.self) { offset in
                        Text(offset.displayName).tag(ReminderOffset?.some(offset))
                    }
                } label: {
                    Text("meal.reminder.title", bundle: .module)
                }
            }

            Section {
                TextField(text: $draft.notes, axis: .vertical) {
                    Text("meal.editor.notes", bundle: .module)
                }
                .lineLimit(2...6)
            }

            if case .edit = mode {
                Section {
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Text("meal.editor.delete", bundle: .module)
                    }
                }
            }
        }
        .navigationTitle(isNew ? Text("meal.editor.newTitle", bundle: .module) : Text("meal.editor.editTitle", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("meal.editor.cancel", bundle: .module)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    Text("meal.editor.save", bundle: .module)
                }
                .disabled(draft.title.trimmedNonEmpty == nil)
            }
        }
        .confirmationDialog(Text("meal.editor.deleteTitle", bundle: .module), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: delete) {
                Text("meal.editor.delete", bundle: .module)
            }
        } message: {
            Text("meal.editor.deleteMessage", bundle: .module)
        }
        .onAppear {
            guard isNew else { return }
            if suggestedTime == nil {
                // Open on the day's next sitting rather than always on lunch.
                let suggestion = MealSuggestion.next(after: store.activePlan?.meals(onDayIndex: draft.dayIndex) ?? [])
                draft.type = suggestion.type
                draft.time = suggestion.time.date(on: .today())
                suggestedTime = draft.time
            }
            focusedField = .title
        }
    }

    private var typeBinding: Binding<MealType> {
        Binding(
            get: { draft.type },
            set: { type in
                let timeFollowsType = isNew && draft.time == suggestedTime
                draft.type = type
                if timeFollowsType {
                    draft.time = type.typicalTime.date(on: .today())
                    suggestedTime = draft.time
                }
            }
        )
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private func numberRow(label: LocalizedStringKey, unit: String, value: Binding<Double?>, decimals: Bool) -> some View {
        LabeledContent {
            HStack(spacing: AppSpacing.xxSmall) {
                TextField(value: value, format: .number.precision(.fractionLength(decimals ? 0...1 : 0...0))) {
                    Text("meal.editor.optional", bundle: .module)
                }
                .keyboardType(decimals ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(label, bundle: .module)
        }
    }

    private var energySymbol: String {
        store.settings.energyUnit == .kilojoules ? UnitEnergy.kilojoules.symbol : UnitEnergy.kilocalories.symbol
    }

    /// Calories are stored in kilocalories; the field shows the person's unit.
    private var energyBinding: Binding<Double?> {
        let unit = store.settings.energyUnit
        return Binding(
            get: {
                guard let calories = draft.calories else { return nil }
                return unit == .kilojoules ? (Double(calories) * 4.184).rounded() : Double(calories)
            },
            set: { newValue in
                guard let newValue, newValue >= 0 else {
                    draft.calories = nil
                    return
                }
                let kilocalories = unit == .kilojoules ? newValue / 4.184 : newValue
                draft.calories = min(Int(kilocalories.rounded()), Nutrition.calorieRange.upperBound)
            }
        )
    }

    private func dayLabel(_ index: Int, plan: MealPlan) -> String {
        let schedule = MealSchedule(plan: plan)
        let day = schedule.calendarDay(forDayIndex: index, onOrAfter: .today())
        let date = day.middayDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if plan.schedule.kind == .fixedDates {
            return date
        }
        return String(localized: "meal.editor.dayLabel", defaultValue: "Day \(index + 1) · \(date)", bundle: .module)
    }

    private func save() {
        var original: Meal?
        if case .edit(let meal) = mode { original = meal }
        let meal = draft.meal(replacing: original)
        withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
            if isNew {
                store.attempt { try store.addMeal(meal) }
            } else {
                store.attempt { try store.updateMeal(meal) }
            }
        }
        dismiss()
    }

    private func delete() {
        guard case .edit(let meal) = mode else { return }
        withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
            store.attempt { try store.deleteMeal(id: meal.id) }
        }
        dismiss()
        onDeleted()
    }
}

/// The form's working copy of a meal.
struct MealDraft {
    var type: MealType = .lunch
    var customTypeName = ""
    var time: Date
    var dayIndex: Int
    var title = ""
    var details = ""
    var portion = ""
    var calories: Int?
    var protein: Double?
    var carbohydrates: Double?
    var fat: Double?
    var notes = ""
    var reminder: ReminderOffset?

    init(dayIndex: Int) {
        self.dayIndex = dayIndex
        self.time = TimeOfDay(hour: 13, minute: 0).date(on: .today())
    }

    init(_ meal: Meal) {
        type = meal.type
        customTypeName = meal.customTypeName ?? ""
        time = meal.time.date(on: .today())
        dayIndex = meal.dayIndex
        title = meal.title
        details = meal.details ?? ""
        portion = meal.portion ?? ""
        calories = meal.nutrition.calories
        protein = meal.nutrition.protein
        carbohydrates = meal.nutrition.carbohydrates
        fat = meal.nutrition.fat
        notes = meal.notes ?? ""
        reminder = meal.reminder
    }

    func meal(replacing original: Meal?) -> Meal {
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        func grams(_ value: Double?) -> Double? {
            value.flatMap { Nutrition.gramRange.contains($0) ? $0 : nil }
        }
        return Meal(
            id: original?.id ?? UUID(),
            dayIndex: dayIndex,
            type: type,
            customTypeName: type == .other ? customTypeName.trimmedNonEmpty : nil,
            time: TimeOfDay(hour: clock.hour ?? 12, minute: clock.minute ?? 0),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details.trimmedNonEmpty,
            portion: portion.trimmedNonEmpty,
            nutrition: Nutrition(calories: calories, protein: grams(protein), carbohydrates: grams(carbohydrates), fat: grams(fat)),
            notes: notes.trimmedNonEmpty,
            reminder: reminder
        )
    }
}
