import Foundation
import SwiftUI
import AppCore
import DesignSystem
import Domain

/// One meal on one day: what it is, when, what is in it, and what happened to it. Only fields the
/// plan actually gives are shown. One action is prominent at a time.
public struct MealDetailScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditing = false
    private let key: OccurrenceKey

    public init(route: MealRoute) {
        switch route {
        case .occurrence(let key):
            self.key = key
        }
    }

    public var body: some View {
        TimelineView(.everyMinute) { context in
            if let occurrence = store.occurrence(for: key) {
                content(occurrence, now: context.date)
            } else {
                ContentUnavailableView {
                    Label {
                        Text("meal.missing.title", bundle: .module)
                    } icon: {
                        Image(systemName: "fork.knife")
                    }
                } description: {
                    Text("meal.missing.message", bundle: .module)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.occurrence(for: key) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isEditing = true
                    } label: {
                        Text("meal.edit", bundle: .module)
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let meal = store.meal(id: key.mealID) {
                NavigationStack {
                    MealEditorScreen(mode: .edit(meal), onDeleted: { dismiss() })
                }
            }
        }
        .sensoryFeedback(trigger: store.occurrence(for: key)?.state) { _, new in
            new == .completed ? .success : nil
        }
    }

    private func content(_ occurrence: MealOccurrence, now: Date) -> some View {
        let meal = occurrence.meal
        let today = CalendarDay(now)
        return List {
            Section {
                header(occurrence, now: now, today: today)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: AppSpacing.xxSmall, leading: AppSpacing.xxSmall, bottom: AppSpacing.small, trailing: AppSpacing.xxSmall))
            }

            if meal.portion != nil || !meal.nutrition.isEmpty {
                Section {
                    nutritionRows(meal)
                } header: {
                    Text("meal.section.nutrition", bundle: .module)
                }
            }

            if let notes = meal.notes?.trimmedNonEmpty {
                Section {
                    Text(notes)
                } header: {
                    Text("meal.section.notes", bundle: .module)
                }
            }

            Section {
                reminderPicker(meal)
            } footer: {
                if !store.settings.remindersEnabled {
                    Text("meal.reminder.offFooter", bundle: .module)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            if occurrence.day <= today {
                actionBar(occurrence)
            }
        }
    }

    private func header(_ occurrence: MealOccurrence, now: Date, today: CalendarDay) -> some View {
        let meal = occurrence.meal
        let time = occurrence.date.formatted(.dateTime.hour().minute())
        let date = occurrence.day.middayDate().formatted(.dateTime.weekday(.wide).month(.wide).day())
        return VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            statusLine(occurrence, now: now, today: today)
            Text(meal.title)
                .font(.title.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(String(localized: "meal.meta", defaultValue: "\(meal.typeLabel) · \(time) · \(date)", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let details = meal.details?.trimmedNonEmpty {
                Text(details)
                    .font(.body)
                    .padding(.top, AppSpacing.xxSmall)
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ occurrence: MealOccurrence, now: Date, today: CalendarDay) -> some View {
        let role = store.agenda(on: occurrence.day, now: now)?.items.first { $0.id == occurrence.key }?.role
        switch occurrence.state {
        case .completed:
            Label {
                Text("meal.status.done", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.success)
            }
            .font(.subheadline.weight(.semibold))
        case .skipped:
            Label {
                Text("meal.status.skipped", bundle: .module)
            } icon: {
                Image(systemName: "minus.circle")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        case .pending:
            if occurrence.day == today, role == .current || role == .next {
                HStack(spacing: AppSpacing.xxSmall + 2) {
                    Text(role == .current ? String(localized: "meal.status.now", bundle: .module) : String(localized: "meal.status.next", bundle: .module))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.brandAccent)
                    if let relative = role == .current ? RelativeTimeText.since(occurrence.date, from: now) : RelativeTimeText.until(occurrence.date, from: now) {
                        Text(verbatim: "·").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(relative).foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func nutritionRows(_ meal: Meal) -> some View {
        if let portion = meal.portion?.trimmedNonEmpty {
            LabeledContent {
                Text(portion)
            } label: {
                Text("meal.nutrition.portion", bundle: .module)
            }
        }
        if let calories = meal.nutrition.calories {
            LabeledContent {
                Text(store.settings.energyUnit.format(kilocalories: calories))
            } label: {
                Text("meal.nutrition.energy", bundle: .module)
            }
        }
        if let protein = meal.nutrition.protein {
            LabeledContent {
                Text(NutritionFormat.grams(protein))
            } label: {
                Text("meal.nutrition.protein", bundle: .module)
            }
        }
        if let carbohydrates = meal.nutrition.carbohydrates {
            LabeledContent {
                Text(NutritionFormat.grams(carbohydrates))
            } label: {
                Text("meal.nutrition.carbohydrates", bundle: .module)
            }
        }
        if let fat = meal.nutrition.fat {
            LabeledContent {
                Text(NutritionFormat.grams(fat))
            } label: {
                Text("meal.nutrition.fat", bundle: .module)
            }
        }
    }

    private func reminderPicker(_ meal: Meal) -> some View {
        let defaultName = store.settings.defaultReminder.displayName
        return Picker(selection: Binding(
            get: { meal.reminder },
            set: { newValue in
                var updated = meal
                updated.reminder = newValue
                store.attempt { try store.updateMeal(updated) }
            }
        )) {
            Text(String(localized: "meal.reminder.default", defaultValue: "Default (\(defaultName))", bundle: .module))
                .tag(ReminderOffset?.none)
            ForEach(ReminderOffset.allCases, id: \.self) { offset in
                Text(offset.displayName).tag(ReminderOffset?.some(offset))
            }
        } label: {
            Text("meal.reminder.title", bundle: .module)
        }
    }

    private func actionBar(_ occurrence: MealOccurrence) -> some View {
        HStack(spacing: AppSpacing.small) {
            switch occurrence.state {
            case .pending:
                Button {
                    set(.skipped, occurrence)
                } label: {
                    Text("meal.action.skip", bundle: .module)
                        .padding(.horizontal, AppSpacing.xSmall)
                }
                .buttonStyle(.bordered)
                Button {
                    set(.completed, occurrence)
                } label: {
                    Label {
                        Text("meal.action.markDone", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brandAccent)
            case .completed:
                Button {
                    set(.pending, occurrence)
                } label: {
                    Text("meal.action.markNotDone", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            case .skipped:
                Button {
                    set(.pending, occurrence)
                } label: {
                    Text("meal.action.undoSkip", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, AppSpacing.screenMargin)
        .padding(.vertical, AppSpacing.small)
        .background(.bar)
    }

    private func set(_ state: OccurrenceState, _ occurrence: MealOccurrence) {
        withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
            store.attempt { try store.setState(state, for: occurrence.key) }
        }
    }
}
