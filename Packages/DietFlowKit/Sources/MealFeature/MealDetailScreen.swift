import Foundation
import SwiftUI
import UIKit
import AppCore
import DesignSystem
import Domain

/// What the meal screen asks the app to do. The app decides where it leads.
public struct MealActions {
    /// Opens cook mode for the meal on that day; nil in a build without the assistant.
    public var cook: ((OccurrenceKey) -> Void)?
    /// Opens the DietFlow Plus screen, from an offer on this screen.
    public var showPlus: () -> Void

    public init(cook: ((OccurrenceKey) -> Void)? = nil, showPlus: @escaping () -> Void = {}) {
        self.cook = cook
        self.showPlus = showPlus
    }
}

/// One meal on one day: what it is, when, what is in it, how to make it, and what happened to it.
/// Only what the plan actually gives is shown, plus what the assistant can add, always marked as
/// the assistant's. One action is prominent at a time.
public struct MealDetailScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(MealAssistantModel.self) private var assistant
    @Environment(AccessModel.self) private var access
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditing = false
    /// The consent alert, before the first estimate sends anything.
    @State private var asksConsent = false
    /// Why the last estimate came back empty; cleared when the person asks again.
    @State private var estimateFailure: AssistantError?
    /// Counts estimates that filled something in, for the success haptic.
    @State private var estimatesLanded = 0
    /// Drives the entrance: the screen's parts settle in one after another.
    @State private var hasAppeared = false
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 60
    private let key: OccurrenceKey
    private let actions: MealActions

    public init(route: MealRoute, actions: MealActions = MealActions()) {
        switch route {
        case .occurrence(let key):
            self.key = key
        }
        self.actions = actions
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
        // The meal's own actions sit at the bottom; the tabs would only compete with them.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if store.occurrence(for: key) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    reminderMenu
                }
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
        .assistantConsent(isPresented: $asksConsent) {
            assistant.allowSharing()
            estimateNutrition()
        }
        .sensoryFeedback(trigger: store.occurrence(for: key)?.state) { _, new in
            guard let new else { return nil }
            switch new {
            case .completed: return .success
            case .skipped: return .impact(weight: .light)
            case .pending: return .selection
            }
        }
        .sensoryFeedback(.success, trigger: estimatesLanded)
        .onAppear { hasAppeared = true }
    }

    private func content(_ occurrence: MealOccurrence, now: Date) -> some View {
        let meal = occurrence.meal
        let today = CalendarDay(now)
        let canMark = occurrence.day <= today
        // "Mark as Eaten" leads while it is on screen; otherwise "How to Make It" may.
        let cookLeads = !(canMark && occurrence.state == .pending)
        return ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                header(occurrence, now: now, today: today)
                    .entrance(0, isShown: hasAppeared, reduceMotion: reduceMotion)
                if showsNutrition(meal) {
                    nutritionCard(meal)
                        .entrance(1, isShown: hasAppeared, reduceMotion: reduceMotion)
                }
                if actions.cook != nil {
                    cookCard(occurrence, leads: cookLeads)
                        .entrance(2, isShown: hasAppeared, reduceMotion: reduceMotion)
                }
                if let details = meal.details?.trimmedNonEmpty {
                    detailsSection(details, type: meal.type)
                        .entrance(3, isShown: hasAppeared, reduceMotion: reduceMotion)
                }
                if let notes = meal.notes?.trimmedNonEmpty {
                    notesSection(notes)
                        .entrance(4, isShown: hasAppeared, reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, AppSpacing.screenMargin)
            .padding(.top, AppSpacing.xSmall)
            .padding(.bottom, AppSpacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if canMark {
                actionBar(occurrence)
            }
        }
    }

    // MARK: Header

    private func header(_ occurrence: MealOccurrence, now: Date, today: CalendarDay) -> some View {
        let meal = occurrence.meal
        return VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .center, spacing: AppSpacing.small) {
                MealGlyph(meal.type, size: min(glyphSize, 96))
                    .symbolEffect(.bounce, value: occurrence.state)
                statusLine(occurrence, now: now, today: today)
            }
            Text(verbatim: meal.title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            metaRow(occurrence)
            if occurrence.isMoved {
                movedLine(occurrence, today: today)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statusLine(_ occurrence: MealOccurrence, now: Date, today: CalendarDay) -> some View {
        let role = store.agenda(on: occurrence.day, now: now)?.items.first { $0.id == occurrence.key }?.role
        switch occurrence.state {
        case .completed:
            Label {
                Text("meal.status.done", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
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
            if occurrence.day == today, let role, role == .current || role == .next || role == .upcoming {
                pendingStatus(role, occurrence: occurrence, now: now)
            } else if occurrence.day < today || role == .past {
                Label {
                    Text("meal.status.missed", bundle: .module)
                } icon: {
                    Image(systemName: "circle.dashed")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    /// "Now · 20 min ago", "Next · in 40 min", "Later today · in 3 hr".
    private func pendingStatus(_ role: MealRole, occurrence: MealOccurrence, now: Date) -> some View {
        let isLead = role == .current || role == .next
        let relative = role == .current
            ? RelativeTimeText.since(occurrence.date, from: now)
            : RelativeTimeText.until(occurrence.date, from: now)
        return HStack(spacing: AppSpacing.xxSmall + 2) {
            Group {
                switch role {
                case .current: Text("meal.status.now", bundle: .module)
                case .next: Text("meal.status.next", bundle: .module)
                default: Text("meal.status.later", bundle: .module)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isLead ? AnyShapeStyle(AppColors.brandAccent) : AnyShapeStyle(.secondary))
            if let relative {
                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(relative)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    /// The time it is at on this day, its sitting and the date, as chips that stack when the text
    /// is large.
    private func metaRow(_ occurrence: MealOccurrence) -> some View {
        let meal = occurrence.meal
        let tint = MealGlyph.tint(meal.type)
        let date = occurrence.day.middayDate().formatted(.dateTime.weekday(.wide).month(.wide).day())
        let time = DetailChip(symbol: "clock", tint: tint) {
            Text(occurrence.date, format: .dateTime.hour().minute())
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        let sitting = DetailChip(symbol: meal.type.symbolName, tint: tint) {
            Text(verbatim: meal.typeLabel)
        }
        let day = Text(verbatim: date)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.xSmall) {
                time
                sitting
                day
            }
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                HStack(spacing: AppSpacing.xSmall) {
                    time
                    sitting
                }
                day
            }
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                time
                sitting
                day
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The day started late, so this meal moved: from when, in the plan.
    private func movedLine(_ occurrence: MealOccurrence, today: CalendarDay) -> some View {
        let planned = occurrence.meal.time.date(on: occurrence.day).formatted(.dateTime.hour().minute())
        let text = occurrence.day == today
            ? String(localized: "meal.header.movedToday", defaultValue: "Moved from \(planned) today", bundle: .module)
            : String(localized: "meal.header.moved", defaultValue: "Moved from \(planned)", bundle: .module)
        return Label {
            Text(text)
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(AppColors.brandAccent)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    // MARK: Nutrition

    private func showsNutrition(_ meal: Meal) -> Bool {
        !meal.nutrition.isEmpty
            || meal.portion?.trimmedNonEmpty != nil
            || (meal.lacksNutrition && assistant.isAvailable)
    }

    private func nutritionCard(_ meal: Meal) -> some View {
        let nutrition = meal.nutrition
        let isEstimating = assistant.estimatingMeals.contains(meal.id)
        return VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                Text("meal.section.nutrition", bundle: .module)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AppSpacing.xSmall)
                if nutrition.isEstimated {
                    AssistantMark(.estimated)
                }
            }

            if isEstimating {
                // What is about to arrive, behind the assistant's shimmer.
                NutritionFigures(energy: "≈ 000 kcal", macros: Macro.placeholders)
                    .assistantShimmer(true)
            } else if !nutrition.isEmpty {
                NutritionFigures(energy: store.settings.energyUnit.format(nutrition), macros: Macro.all(in: nutrition))
            }

            if let portion = meal.portion?.trimmedNonEmpty {
                portionChip(portion)
            }

            if nutrition.isEstimated {
                Text("meal.nutrition.estimatedFootnote", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if meal.lacksNutrition, assistant.isAvailable, !isEstimating {
                estimatePrompt
            }
        }
        .detailCard()
        .animation(AppMotion.animation(AppMotion.snappy, reduceMotion: reduceMotion), value: nutrition)
        .animation(AppMotion.animation(AppMotion.settle, reduceMotion: reduceMotion), value: isEstimating)
    }

    private func portionChip(_ portion: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
            Text("meal.nutrition.portion", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label {
                Text(verbatim: portion)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "scalemass")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xxSmall + 2)
            .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    /// The plan gives no figures: the assistant can work them out, at the cost shown.
    private var estimatePrompt: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("meal.nutrition.missing", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AssistantButton(
                Text("meal.nutrition.estimate", bundle: .module),
                cost: AssistantCost.caption(remaining: assistant.remaining(.aiNutrition), tier: access.tier)
            ) {
                estimateNutrition()
            }
            if let estimateFailure {
                Label {
                    Text(failureMessage(estimateFailure))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
        }
    }

    private func estimateNutrition() {
        guard let meal = store.meal(id: key.mealID), meal.lacksNutrition else { return }
        // A used-up allowance opens the Plus screen straight away, rather than first asking to share.
        guard assistant.canAsk(.aiNutrition) else {
            access.check(.aiNutrition)
            return
        }
        estimateFailure = nil
        Task {
            switch await assistant.estimate(meal) {
            case .success(let filled):
                if filled > 0 { estimatesLanded += 1 }
            case .needsConsent:
                asksConsent = true
            case .failed(let error):
                withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                    estimateFailure = error
                }
            case .refused, .unavailable:
                // The app shows the Plus screen or the "comes back on" alert; nothing to add here.
                break
            }
        }
    }

    private func failureMessage(_ error: AssistantError) -> String {
        switch error {
        case .offline:
            String(localized: "meal.estimate.failed.offline", bundle: .module)
        case .busy:
            String(localized: "meal.estimate.failed.busy", bundle: .module)
        case .dailyLimit:
            String(localized: "meal.estimate.failed.dailyLimit", bundle: .module)
        case .tooLong, .noPlan, .unavailable:
            String(localized: "meal.estimate.failed.other", bundle: .module)
        }
    }

    // MARK: How to make it

    private func cookCard(_ occurrence: MealOccurrence, leads: Bool) -> some View {
        let isReady = assistant.cachedRecipe(for: occurrence.meal) != nil
        return AssistantCard(
            title: Text("meal.cook.title", bundle: .module),
            subtitle: isReady ? Text("meal.cook.readySubtitle", bundle: .module) : Text("meal.cook.subtitle", bundle: .module),
            badge: cookBadge(isReady: isReady),
            style: leads ? .prominent : .quiet
        ) {
            openCook(occurrence.key, isReady: isReady)
        }
    }

    /// What opening the recipe costs: nothing once it is written, otherwise the allowance left.
    private func cookBadge(isReady: Bool) -> Text? {
        if isReady {
            return Text("meal.cook.ready", bundle: .module)
        }
        switch AssistantCost.caption(remaining: assistant.remaining(.aiRecipe), tier: access.tier) {
        case .left(let count):
            return Text(String(localized: "meal.cook.usesLeft", defaultValue: "\(count) AI uses left this month", bundle: .module))
        case .plus:
            return Text("meal.cook.plusBadge", bundle: .module)
        case nil:
            return nil
        }
    }

    private func openCook(_ occurrence: OccurrenceKey, isReady: Bool) {
        guard let cook = actions.cook else { return }
        // A recipe still to be written with nothing left to write it: the Plus screen says so,
        // instead of an empty cook mode.
        if !isReady, !assistant.canAsk(.aiRecipe) {
            access.check(.aiRecipe)
            return
        }
        cook(occurrence)
    }

    // MARK: Ingredients and notes

    private func detailsSection(_ details: String, type: MealType) -> some View {
        let items = IngredientList.items(in: details)
        return VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            if let items {
                sectionTitle("meal.section.ingredients")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Divider()
                        }
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(MealGlyph.tint(type))
                                .accessibilityHidden(true)
                            Text(verbatim: item)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, AppSpacing.small - 2)
                    }
                }
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.xxSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                Label {
                    Text("meal.ingredients.safety", bundle: .module)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "allergens")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppSpacing.xxSmall)
            } else {
                sectionTitle("meal.section.description")
                Text(verbatim: details)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .detailCard()
            }
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            sectionTitle("meal.section.notes")
            Text(verbatim: notes)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .detailCard()
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key, bundle: .module)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, AppSpacing.xxSmall)
    }

    // MARK: Reminder

    /// The meal's reminder, in the toolbar: a bell that says whether one will come.
    @ViewBuilder
    private var reminderMenu: some View {
        if let meal = store.meal(id: key.mealID) {
            let settings = store.settings
            let rings = settings.remindersEnabled && (meal.reminder ?? settings.defaultReminder) != .off
            let defaultName = settings.defaultReminder.displayName
            let defaultLabel = String(localized: "meal.reminder.default", defaultValue: "Default (\(defaultName))", bundle: .module)
            Menu {
                Picker(selection: reminderBinding(meal)) {
                    Text(defaultLabel)
                        .tag(ReminderOffset?.none)
                    ForEach(ReminderOffset.allCases, id: \.self) { offset in
                        Text(offset.displayName).tag(ReminderOffset?.some(offset))
                    }
                } label: {
                    Text("meal.reminder.title", bundle: .module)
                }
                .pickerStyle(.inline)
                if !settings.remindersEnabled {
                    Section {
                        Text("meal.reminder.offFooter", bundle: .module)
                    }
                }
            } label: {
                Label {
                    Text("meal.reminder.title", bundle: .module)
                } icon: {
                    Image(systemName: rings ? "bell" : "bell.slash")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .accessibilityValue(Text(meal.reminder?.displayName ?? defaultLabel))
        }
    }

    private func reminderBinding(_ meal: Meal) -> Binding<ReminderOffset?> {
        Binding(
            get: { store.meal(id: meal.id)?.reminder ?? meal.reminder },
            set: { newValue in
                guard var updated = store.meal(id: meal.id) else { return }
                updated.reminder = newValue
                store.attempt { try store.updateMeal(updated) }
            }
        )
    }

    // MARK: Actions

    /// "Mark as Eaten" leads, Skip beside it; stacked when the text is large. Once marked, the
    /// result and a way back.
    @ViewBuilder
    private func actionBar(_ occurrence: MealOccurrence) -> some View {
        Group {
            switch occurrence.state {
            case .pending:
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.small) {
                        skipButton(occurrence, fills: false)
                        eatenButton(occurrence)
                    }
                    VStack(spacing: AppSpacing.xSmall) {
                        eatenButton(occurrence)
                        skipButton(occurrence, fills: true)
                    }
                }
            case .completed:
                markedBar(occurrence) {
                    Label {
                        Text("meal.status.done", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                            .symbolEffect(.bounce, value: occurrence.state)
                    }
                } undo: {
                    Label {
                        Text("meal.action.markNotDone", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
            case .skipped:
                markedBar(occurrence) {
                    Label {
                        Text("meal.status.skipped", bundle: .module)
                    } icon: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                } undo: {
                    Label {
                        Text("meal.action.undoSkip", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
            }
        }
        .controlSize(.large)
        .padding(.horizontal, AppSpacing.screenMargin)
        .padding(.vertical, AppSpacing.small)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .animation(AppMotion.animation(AppMotion.snappy, reduceMotion: reduceMotion), value: occurrence.state)
    }

    private func eatenButton(_ occurrence: MealOccurrence) -> some View {
        Button {
            set(.completed, occurrence)
        } label: {
            Label {
                Text("meal.action.markDone", bundle: .module)
            } icon: {
                Image(systemName: "checkmark")
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.brandAccent)
        .accessibilityLabel(Text("meal.action.markDoneLabel", bundle: .module))
    }

    private func skipButton(_ occurrence: MealOccurrence, fills: Bool) -> some View {
        Button {
            set(.skipped, occurrence)
        } label: {
            Text("meal.action.skip", bundle: .module)
                .padding(.horizontal, AppSpacing.xSmall)
                .frame(maxWidth: fills ? .infinity : nil)
        }
        .buttonStyle(.bordered)
    }

    /// What was recorded, and the button that takes it back.
    private func markedBar<Status: View, Undo: View>(
        _ occurrence: MealOccurrence,
        @ViewBuilder status: () -> Status,
        @ViewBuilder undo: () -> Undo
    ) -> some View {
        let statusView = status()
            .font(.headline)
        let undoLabel = undo()
        let undoButton = Button {
            set(.pending, occurrence)
        } label: {
            undoLabel
        }
        .buttonStyle(.bordered)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.small) {
                statusView
                Spacer(minLength: AppSpacing.xSmall)
                undoButton
            }
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                statusView
                undoButton
            }
        }
    }

    private func set(_ state: OccurrenceState, _ occurrence: MealOccurrence) {
        withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
            store.attempt { try store.setState(state, for: occurrence.key) }
        }
    }
}

// MARK: Parts

/// A small capsule in the header: a tinted symbol and a short value.
private struct DetailChip<Content: View>: View {
    private let symbol: String
    private let tint: Color
    private let content: Content

    init(symbol: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        HStack(spacing: AppSpacing.xxSmall + 2) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .imageScale(.small)
                .accessibilityHidden(true)
            content
                .foregroundStyle(.primary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, AppSpacing.small - 2)
        .padding(.vertical, AppSpacing.xxSmall + 2)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// One macronutrient as the nutrition card draws it.
private struct Macro: Identifiable {
    enum Kind: Hashable {
        case protein
        case carbohydrates
        case fat

        /// Energy per gram, for each one's share of the meal's energy.
        var kilocaloriesPerGram: Double {
            switch self {
            case .protein, .carbohydrates: 4
            case .fat: 9
            }
        }

        var name: Text {
            switch self {
            case .protein: Text("meal.nutrition.protein", bundle: .module)
            case .carbohydrates: Text("meal.nutrition.carbohydrates", bundle: .module)
            case .fat: Text("meal.nutrition.fat", bundle: .module)
            }
        }

        /// System colours, beside the name and the grams, never instead of them.
        var tint: Color {
            switch self {
            case .protein: .teal
            case .carbohydrates: .orange
            case .fat: .purple
            }
        }
    }

    let kind: Kind
    let grams: Double
    /// Its share of the energy the three give, 0...1; nil unless all three are known, because a
    /// share of a partial total would mislead.
    let share: Double?

    var id: Kind { kind }

    static func all(in nutrition: Nutrition) -> [Macro] {
        let known: [(Kind, Double?)] = [
            (.protein, nutrition.protein),
            (.carbohydrates, nutrition.carbohydrates),
            (.fat, nutrition.fat),
        ]
        var total = 0.0
        var complete = true
        for item in known {
            if let grams = item.1 {
                total += grams * item.0.kilocaloriesPerGram
            } else {
                complete = false
            }
        }
        var result: [Macro] = []
        for item in known {
            guard let grams = item.1 else { continue }
            let share: Double? = complete && total > 0 ? grams * item.0.kilocaloriesPerGram / total : nil
            result.append(Macro(kind: item.0, grams: grams, share: share))
        }
        return result
    }

    /// Stand-ins drawn under the shimmer while an estimate runs.
    static var placeholders: [Macro] {
        [
            Macro(kind: .protein, grams: 30, share: 0.3),
            Macro(kind: .carbohydrates, grams: 30, share: 0.3),
            Macro(kind: .fat, grams: 18, share: 0.4),
        ]
    }
}

/// The big energy figure and the three macronutrients as bars with their grams printed.
private struct NutritionFigures: View {
    let energy: String?
    let macros: [Macro]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The bars grow from nothing once, when the card first shows.
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            if let energy {
                VStack(alignment: .leading, spacing: 2) {
                    Text(energy)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("meal.nutrition.energy", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if !macros.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    ForEach(macros) { macro in
                        row(macro)
                    }
                }
                if macros.contains(where: { $0.share != nil }) {
                    Text("meal.nutrition.barsFootnote", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
                isRevealed = true
            }
        }
    }

    private func row(_ macro: Macro) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall + 2) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                macro.kind.name
                    .font(.subheadline)
                Spacer(minLength: AppSpacing.xSmall)
                Text(NutritionFormat.grams(macro.grams))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let share = macro.share {
                    Text(share.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            if let share = macro.share {
                Capsule()
                    .fill(macro.kind.tint.opacity(0.18))
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(macro.kind.tint)
                                .frame(width: max(proxy.size.width * CGFloat(isRevealed ? share : 0), 8))
                        }
                    }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// The screen's cards: the system's secondary background, rounded like the assistant's cards.
    func detailCard() -> some View {
        padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    /// A gentle entrance: each part fades and rises into place a moment after the one above it.
    /// Under Reduce Motion it only fades.
    func entrance(_ order: Int, isShown: Bool, reduceMotion: Bool) -> some View {
        opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 14)
            .animation(AppMotion.animation(AppMotion.settle, reduceMotion: reduceMotion).delay(Double(order) * 0.06), value: isShown)
    }
}
