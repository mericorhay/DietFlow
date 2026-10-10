import Foundation
import SwiftUI
import DesignSystem
import Domain

/// A new number of servings that is not written yet: what it costs, and what became of asking.
struct ServingsChange {
    let servings: Int
    let cost: AssistantCost?
    let isWorking: Bool
    let error: AssistantError?
    let onConfirm: () -> Void
    let onCancel: () -> Void
}

/// The first page of cook mode: what the dish is, how long it takes, what goes in it and what could
/// go in instead. Everything the assistant wrote is shown as written and marked as its work.
struct CookOverview: View {
    let recipe: Recipe
    let meal: Meal
    /// The servings shown in the stepper: the recipe's, or a new count waiting to be written.
    let servings: Int
    let change: ServingsChange?
    let isRewriting: Bool
    let avoiding: String?
    @Binding var checked: Set<Int>
    let onServings: (Int) -> Void
    let onSwaps: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 56

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                header
                chips
                if let change {
                    ServingsChangeCard(change: change)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Group {
                    if !recipe.ingredients.isEmpty {
                        ingredients
                    }
                    if !recipe.tips.isEmpty {
                        tips
                    }
                }
                .assistantShimmer(isRewriting)
            }
            .padding(.horizontal, AppSpacing.screenMargin)
            .padding(.top, AppSpacing.small)
            .padding(.bottom, AppSpacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animationAware(AppMotion.snappy, reduceMotion: reduceMotion, value: change?.servings)
        }
        .sensoryFeedback(.selection, trigger: checked)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .center) {
                MealGlyph(meal.type, size: glyphSize)
                Spacer(minLength: AppSpacing.small)
                AssistantMark(.written)
            }
            Text(verbatim: recipe.title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let summary = recipe.summary?.trimmedNonEmpty {
                Text(verbatim: summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Chips

    private var chips: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.xSmall) {
                    minutesChip
                    difficultyChip
                    ServingsStepper(servings: servings, isEnabled: !isRewriting, onChange: onServings)
                }
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    HStack(spacing: AppSpacing.xSmall) {
                        minutesChip
                        difficultyChip
                    }
                    ServingsStepper(servings: servings, isEnabled: !isRewriting, onChange: onServings)
                }
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    minutesChip
                    difficultyChip
                    ServingsStepper(servings: servings, isEnabled: !isRewriting, onChange: onServings)
                }
            }
            if let avoiding {
                CookChip(symbol: "hand.raised", isTinted: true) {
                    Text(String(localized: "cook.avoiding", defaultValue: "Avoiding: \(avoiding)", bundle: .module))
                        .lineLimit(3)
                }
            }
        }
    }

    private var minutesChip: some View {
        CookChip(symbol: "clock") {
            Text(String(localized: "cook.chip.minutes", defaultValue: "\(recipe.minutes) min", bundle: .module))
                .monospacedDigit()
        }
    }

    private var difficultyChip: some View {
        CookChip(symbol: "chart.bar") {
            Text(verbatim: recipe.difficulty.name)
        }
    }

    // MARK: Ingredients

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("cook.ingredients.title", bundle: .module)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AppSpacing.small)
                Text(String(localized: "cook.ingredients.progress", defaultValue: "\(checked.count) of \(recipe.ingredients.count) ready", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            VStack(spacing: 0) {
                ForEach(Array(recipe.ingredients.indices), id: \.self) { index in
                    if index > 0 {
                        Divider()
                            .padding(.leading, AppSpacing.medium)
                    }
                    IngredientRow(
                        ingredient: recipe.ingredients[index],
                        isChecked: checked.contains(index),
                        onToggle: { toggle(index) },
                        onSwaps: { onSwaps(index) }
                    )
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            SafetyLine()
                .padding(.top, AppSpacing.xxSmall)
        }
    }

    private func toggle(_ index: Int) {
        withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
            if checked.contains(index) {
                checked.remove(index)
            } else {
                checked.insert(index)
            }
        }
    }

    // MARK: Tips

    private var tips: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("cook.tips.title", bundle: .module)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(recipe.tips.indices), id: \.self) { index in
                Label {
                    Text(verbatim: recipe.tips[index])
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
            }
        }
    }
}

// MARK: Pieces

/// A small fact about the recipe in a capsule: its time, how hard it is, what is avoided.
struct CookChip<Content: View>: View {
    let symbol: String
    var isTinted = false
    @ViewBuilder let content: Content

    var body: some View {
        Label {
            content
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(isTinted ? AppColors.brandAccent : Color.secondary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xSmall)
        .frame(minHeight: AppSpacing.minimumHitTarget)
        .background(isTinted ? AnyShapeStyle(AppColors.brandWash) : AnyShapeStyle(Color(.secondarySystemBackground)), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// How many servings, from 1 to 8. One adjustable element for VoiceOver; two buttons for the eye.
struct ServingsStepper: View {
    let servings: Int
    let isEnabled: Bool
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onChange(servings - 1)
            } label: {
                Image(systemName: "minus")
                    .frame(width: AppSpacing.minimumHitTarget, height: AppSpacing.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .disabled(!isEnabled || servings <= 1)
            Label {
                Text(countText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "person.2")
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            Button {
                onChange(servings + 1)
            } label: {
                Image(systemName: "plus")
                    .frame(width: AppSpacing.minimumHitTarget, height: AppSpacing.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .disabled(!isEnabled || servings >= 8)
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(AppColors.brandAccent)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("cook.servings.label", bundle: .module))
        .accessibilityValue(Text(countText))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: if servings < 8 { onChange(servings + 1) }
            case .decrement: if servings > 1 { onChange(servings - 1) }
            @unknown default: break
            }
        }
    }

    private var countText: String {
        String(localized: "cook.servings.count", defaultValue: "\(servings) servings", bundle: .module)
    }
}

/// A new number of servings is a new recipe: the card says so, and what asking costs, before
/// anything is asked.
struct ServingsChangeCard: View {
    let change: ServingsChange

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("cook.servings.newRecipe", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = change.error {
                Label {
                    Text(verbatim: CookWords.message(for: error))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: CookWords.symbol(for: error))
                        .foregroundStyle(.orange)
                }
                .font(.footnote)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppSpacing.small) {
                    rewriteButton
                    cancelButton
                }
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    rewriteButton
                    cancelButton
                }
            }
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private var rewriteButton: some View {
        AssistantButton(
            Text(String(localized: "cook.servings.rewrite", defaultValue: "Write It for \(change.servings) Servings", bundle: .module)),
            cost: change.cost,
            isWorking: change.isWorking,
            action: change.onConfirm
        )
    }

    private var cancelButton: some View {
        Button(action: change.onCancel) {
            Text("cook.servings.cancel", bundle: .module)
                .frame(minHeight: AppSpacing.minimumHitTarget)
        }
        .buttonStyle(.borderless)
        .tint(AppColors.brandAccent)
        .disabled(change.isWorking)
    }
}

/// One ingredient: tap to tick it off; its swaps, when it has any, one tap away.
struct IngredientRow: View {
    let ingredient: Recipe.Ingredient
    let isChecked: Bool
    let onToggle: () -> Void
    let onSwaps: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xSmall))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AppSpacing.small))
        layout {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isChecked ? AppColors.success : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: ingredient.name)
                            .font(.body)
                            .strikethrough(isChecked, color: Color.secondary)
                            .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let amount = ingredient.amount?.trimmedNonEmpty {
                            Text(verbatim: amount)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: AppSpacing.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isChecked ? Text("cook.ingredient.checked", bundle: .module) : Text(verbatim: ""))
            .accessibilityAddTraits(isChecked ? .isSelected : [])
            if !ingredient.substitutes.isEmpty {
                Button(action: onSwaps) {
                    Label {
                        Text(String(localized: "cook.ingredient.swaps", defaultValue: "\(ingredient.substitutes.count) swaps", bundle: .module))
                    } icon: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.brandAccent)
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.vertical, 6)
                    .background(AppColors.brandWash, in: Capsule())
                    .frame(minHeight: AppSpacing.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "cook.ingredient.swapsLabel", defaultValue: "Swaps for \(ingredient.name)", bundle: .module)))
                .padding(.leading, dynamicTypeSize.isAccessibilitySize ? AppSpacing.xLarge + AppSpacing.small : 0)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.xxSmall)
    }
}

/// The line under every list of ingredients and swaps: the assistant does not know the person's
/// allergies or their dietitian's advice, so they check.
struct SafetyLine: View {
    var body: some View {
        Label {
            Text("cook.safety", bundle: .module)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

// MARK: Swaps

/// What could go in instead of one ingredient, each with what it changes, in a half-height sheet.
struct SwapsSheet: View {
    let ingredient: Recipe.Ingredient
    let energyUnit: EnergyUnit

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(ingredient.substitutes.indices), id: \.self) { index in
                        SwapRow(substitute: ingredient.substitutes[index], energyUnit: energyUnit)
                    }
                } header: {
                    Text(String(localized: "cook.swaps.instead", defaultValue: "Instead of \(original)", bundle: .module))
                        .textCase(nil)
                } footer: {
                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        if ingredient.substitutes.contains(where: { $0.kcalDelta != nil }) {
                            AssistantMark(.estimated)
                            Text("cook.swaps.footer", bundle: .module)
                        }
                        Text("cook.safety", bundle: .module)
                    }
                    .padding(.top, AppSpacing.xxSmall)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("cook.swaps.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("cook.swaps.done", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// "Chicken breast · 150 g", as the recipe wrote it.
    private var original: String {
        [ingredient.name, ingredient.amount?.trimmedNonEmpty].compactMap { $0 }.joined(separator: " · ")
    }
}

struct SwapRow: View {
    let substitute: Recipe.Substitute
    let energyUnit: EnergyUnit

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: substitute.name)
                    .font(.headline)
                if let amount = substitute.amount?.trimmedNonEmpty {
                    Text(verbatim: amount)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let note = substitute.note?.trimmedNonEmpty {
                    Text(verbatim: note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: AppSpacing.xSmall)
            if let delta = substitute.kcalDelta {
                KcalDeltaBadge(delta: delta, energyUnit: energyUnit)
            }
        }
        .padding(.vertical, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
    }
}

/// "−40 kcal" with a down arrow, "+120 kcal" with an up arrow: the sign and the arrow say which way,
/// the colour only helps.
struct KcalDeltaBadge: View {
    let delta: Int
    let energyUnit: EnergyUnit

    var body: some View {
        Label {
            Text(verbatim: shown)
                .monospacedDigit()
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, AppSpacing.xSmall)
        .padding(.vertical, AppSpacing.xxSmall)
        .background(tint.opacity(0.15), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var magnitude: String {
        // Bounded to ±2000 by `Recipe.Substitute`, so the magnitude cannot overflow.
        energyUnit.format(kilocalories: delta.magnitude > UInt(Int.max) ? 0 : Int(delta.magnitude))
    }

    private var shown: String {
        if delta < 0 { return "\u{2212}" + magnitude }
        if delta > 0 { return "+" + magnitude }
        return String(localized: "cook.swaps.same", bundle: .module)
    }

    private var spoken: String {
        if delta < 0 { return String(localized: "cook.swaps.kcalLess", defaultValue: "About \(magnitude) less", bundle: .module) }
        if delta > 0 { return String(localized: "cook.swaps.kcalMore", defaultValue: "About \(magnitude) more", bundle: .module) }
        return String(localized: "cook.swaps.kcalSame", bundle: .module)
    }

    private var symbol: String {
        delta < 0 ? "arrow.down" : delta > 0 ? "arrow.up" : "equal"
    }

    private var tint: Color {
        if delta < 0 { return Color.green }
        if delta > 0 { return Color.orange }
        return Color.gray
    }
}
