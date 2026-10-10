import Foundation
import SwiftUI
import UIKit
import AppCore
import DesignSystem
import Domain

// MARK: Moments

/// A short word on screen after something worth one, with its haptic: a meal eaten, the day moved.
/// Plain values, so they compare and trigger feedback anywhere.
nonisolated struct TodayToast: Equatable {
    nonisolated enum Kind: Equatable {
        /// A meal was marked eaten.
        case done
        /// A late start moved the day's meals by this many minutes.
        case shifted(minutes: Int)
        /// The person is up and the day stays as planned.
        case onTime
        /// The person chose to keep the plan's times after a late start.
        case kept
        /// A moved day follows the plan again.
        case undone

        /// Eating is the moment that earns a success; the rest is a light touch.
        var feedback: SensoryFeedback {
            switch self {
            case .done: .success
            case .shifted: .impact(weight: .medium)
            case .onTime, .kept, .undone: .impact(weight: .light)
            }
        }
    }

    let kind: Kind
    /// Two toasts of the same kind in a row are still two moments.
    let id = UUID()
}

extension TodayToast.Kind {
    var text: String {
        switch self {
        case .done:
            String(localized: "today.toast.done", bundle: .module)
        case .shifted(let minutes):
            String(localized: "today.shift.banner", defaultValue: "Day moved \(TodayFormat.duration(minutes: minutes)) later", bundle: .module)
        case .onTime:
            String(localized: "today.toast.onTime", bundle: .module)
        case .kept:
            String(localized: "today.toast.kept", bundle: .module)
        case .undone:
            String(localized: "today.toast.undone", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .shifted: "clock.arrow.circlepath"
        case .onTime: "sun.max.fill"
        case .kept: "checkmark.circle"
        case .undone: "arrow.uturn.backward.circle"
        }
    }

    var tint: Color {
        switch self {
        case .done: AppColors.success
        case .shifted: AppColors.brandAccent
        case .onTime: Color.orange
        case .kept, .undone: Color.secondary
        }
    }
}

/// The toast itself: a symbol that bounces once and a few words, on a material capsule above the
/// tab bar. VoiceOver hears it as an announcement instead.
struct TodayToastView: View {
    let toast: TodayToast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: toast.kind.symbol)
                .font(.title3)
                .foregroundStyle(toast.kind.tint)
                .symbolEffect(.bounce, value: hasAppeared)
            Text(toast.kind.text)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        .accessibilityHidden(true)
        .onAppear {
            if !reduceMotion { hasAppeared = true }
        }
    }
}

// MARK: Planned today

/// What a day's meals add up to, as the plan gives it and as far as it has been eaten. Skipped
/// meals are left out. Nil when no meal of the day has any figure.
nonisolated struct DayNutrition: Equatable {
    nonisolated struct Figure: Equatable {
        var planned: Double
        var eaten: Double

        var fraction: Double { planned > 0 ? min(max(eaten / planned, 0), 1) : 0 }
    }

    var energy: Figure?
    var protein: Figure?
    var carbohydrates: Figure?
    var fat: Figure?
    /// Any figure counted is the assistant's estimate.
    var isEstimated: Bool
    var mealsWithFigures: Int
    var mealCount: Int

    init?(items: [AgendaItem]) {
        let counted = items.map(\.occurrence).filter { $0.state != .skipped }
        energy = Self.figure(counted) { nutrition in nutrition.calories.map { Double($0) } }
        protein = Self.figure(counted) { $0.protein }
        carbohydrates = Self.figure(counted) { $0.carbohydrates }
        fat = Self.figure(counted) { $0.fat }
        isEstimated = counted.contains { $0.meal.nutrition.isEstimated && !$0.meal.nutrition.isEmpty }
        mealsWithFigures = counted.filter { !$0.meal.nutrition.isEmpty }.count
        mealCount = counted.count
        if energy == nil, protein == nil, carbohydrates == nil, fat == nil { return nil }
    }

    private static func figure(_ meals: [MealOccurrence], _ value: (Nutrition) -> Double?) -> Figure? {
        var planned = 0.0
        var eaten = 0.0
        var found = false
        for meal in meals {
            guard let amount = value(meal.meal.nutrition) else { continue }
            found = true
            planned += amount
            if meal.state == .completed { eaten += amount }
        }
        return found ? Figure(planned: planned, eaten: eaten) : nil
    }

    /// How far the day has been eaten: by energy when the plan gives it, else by protein.
    var eatenFraction: Double {
        (energy ?? protein ?? carbohydrates ?? fat)?.fraction ?? 0
    }
}

/// "Planned today": what the day's meals add up to, a ring and bars that fill in solid as meals
/// are eaten. It describes the plan; it is never a budget to stay under, and estimates carry "≈".
struct PlannedTodayCard: View {
    let nutrition: DayNutrition
    let energyUnit: EnergyUnit
    let isToday: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var ringSize: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.medium) {
                ring
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppSpacing.xSmall) {
                        Text(LocalizedStringKey(isToday ? "today.planned.title" : "today.planned.titleDay"), bundle: .module)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if nutrition.isEstimated {
                            AssistantMark(.estimated)
                        }
                    }
                    if let energy = nutrition.energy {
                        Text(verbatim: energyText(energy.planned))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if energy.eaten > 0 {
                            Text(String(localized: "today.planned.eaten", defaultValue: "\(energyText(energy.eaten)) eaten so far", bundle: .module))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            macros
            if nutrition.mealsWithFigures < nutrition.mealCount {
                Text(String(localized: "today.planned.partial", defaultValue: "From \(nutrition.mealsWithFigures) of \(nutrition.mealCount) meals; the others have no figures.", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.medium)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .animationAware(AppMotion.settle, reduceMotion: reduceMotion, value: nutrition)
        .accessibilityElement(children: .combine)
    }

    private var ring: some View {
        let size = min(ringSize, 88)
        let fraction = nutrition.eatenFraction
        return ZStack {
            Circle()
                .stroke(AppColors.brandAccent.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(AppColors.brandAccent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "fork.knife")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.brandAccent)
        }
        .frame(width: size, height: size)
        .padding(4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var macros: some View {
        let figures = macroFigures
        if !figures.isEmpty {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.small))
                : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.medium))
            layout {
                ForEach(figures) { item in
                    macro(item.name, item.figure)
                }
            }
        }
    }

    private nonisolated struct MacroItem: Identifiable {
        let name: String
        let figure: DayNutrition.Figure
        var id: String { name }
    }

    private var macroFigures: [MacroItem] {
        var figures: [MacroItem] = []
        if let protein = nutrition.protein {
            figures.append(MacroItem(name: String(localized: "today.planned.protein", bundle: .module), figure: protein))
        }
        if let carbohydrates = nutrition.carbohydrates {
            figures.append(MacroItem(name: String(localized: "today.planned.carbohydrates", bundle: .module), figure: carbohydrates))
        }
        if let fat = nutrition.fat {
            figures.append(MacroItem(name: String(localized: "today.planned.fat", bundle: .module), figure: fat))
        }
        return figures
    }

    private func macro(_ name: String, _ figure: DayNutrition.Figure) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Capsule()
                .fill(AppColors.brandAccent.opacity(0.18))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(AppColors.brandAccent)
                            .frame(width: proxy.size.width * CGFloat(figure.fraction))
                    }
                }
                .accessibilityHidden(true)
            Text(verbatim: gramsText(figure))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var approximate: String { nutrition.isEstimated ? "≈\u{2009}" : "" }

    private func energyText(_ kilocalories: Double) -> String {
        energyUnit.format(Nutrition(calories: Int(kilocalories.rounded()), estimated: nutrition.isEstimated))
            ?? energyUnit.format(kilocalories: Int(kilocalories.rounded()))
    }

    /// "≈ 42 g of 118 g" once some is eaten, else "≈ 118 g".
    private func gramsText(_ figure: DayNutrition.Figure) -> String {
        let planned = NutritionFormat.grams(figure.planned.rounded())
        guard figure.eaten > 0 else { return approximate + planned }
        let eaten = NutritionFormat.grams(figure.eaten.rounded())
        return approximate + String(localized: "today.planned.gramsOf", defaultValue: "\(eaten) of \(planned)", bundle: .module)
    }
}

// MARK: Estimate

/// The assistant's offer to fill in the nutrition the plan does not give, then how it is going.
/// One use of the allowance for the whole plan, shown before the tap; figures it adds are marked
/// as estimates and never replace the plan's own.
struct EstimateCard: View {
    @Environment(MealAssistantModel.self) private var assistant
    @Environment(AccessModel.self) private var access
    @Environment(MealPlanStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var asksConsent = false

    var body: some View {
        content
            .assistantConsent(isPresented: $asksConsent) {
                assistant.allowSharing()
                run()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch assistant.planEstimate {
        case .some(.running(let dishes)):
            running(dishes)
        case .some(.finished(let meals)):
            finished(meals)
        case .some(.failed):
            failed
        case .none:
            offer
        }
    }

    private var offer: some View {
        let count = assistant.dishesNeedingEstimates
        return VStack(alignment: .trailing, spacing: 0) {
            AssistantCard(
                symbol: "sparkles",
                title: Text(String(localized: "today.estimate.title", defaultValue: "Add nutrition to your \(count) meals", bundle: .module)),
                subtitle: Text("today.estimate.subtitle", bundle: .module),
                badge: badge,
                action: { run() }
            )
            Button {
                withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                    store.updateSettings { $0.hasDismissedEstimateCard = true }
                }
            } label: {
                Text("today.estimate.notNow", bundle: .module)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: AppSpacing.minimumHitTarget)
            }
            .buttonStyle(.borderless)
            .tint(Color.secondary)
        }
    }

    /// What the tap costs, said before it: one use and how many are left, or that it is part of Plus.
    private var badge: Text? {
        switch AssistantCost.caption(remaining: assistant.remaining(.aiNutrition), tier: access.tier) {
        case .some(.left(let left)):
            Text(String(localized: "today.estimate.cost", defaultValue: "One AI use · \(left) left this month", bundle: .module))
        case .some(.plus):
            Text("today.estimate.plus", bundle: .module)
        case .none:
            nil
        }
    }

    private func running(_ dishes: Int) -> some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "sparkles")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColors.brandAccent)
                .symbolEffect(.pulse, isActive: !reduceMotion)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(String(localized: "today.estimate.running", defaultValue: "Working out \(dishes) dishes…", bundle: .module))
                    .font(.headline)
                Text(verbatim: "≈ 000 kcal · 00 g · 00 g · 00 g")
                    .font(.subheadline)
                    .assistantShimmer(true)
            }
            Spacer(minLength: 0)
        }
        .modifier(AssistantSurface())
    }

    private func finished(_ meals: Int) -> some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(AppColors.success)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(String(localized: "today.estimate.finished", defaultValue: "Nutrition added to \(meals) meals", bundle: .module))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                AssistantMark(.estimated)
            }
            Spacer(minLength: 0)
            Button {
                withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                    assistant.dismissPlanEstimate()
                }
            } label: {
                Text("today.estimate.ok", bundle: .module)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(AppColors.brandAccent)
        }
        .accessibilityElement(children: .combine)
        .modifier(AssistantSurface())
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Label {
                Text("today.estimate.failed.title", bundle: .module)
                    .font(.headline)
            } icon: {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            }
            Text("today.estimate.failed.message", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AppSpacing.small) {
                Button {
                    run()
                } label: {
                    Text("today.estimate.retry", bundle: .module)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(AppColors.brandAccent)
                Button {
                    // "Not now" here means the offer too: without this the card would turn
                    // straight back into the offer it just failed on.
                    withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                        assistant.dismissPlanEstimate()
                        store.updateSettings { $0.hasDismissedEstimateCard = true }
                    }
                } label: {
                    Text("today.estimate.notNow", bundle: .module)
                }
                .buttonStyle(.borderless)
                .tint(Color.secondary)
            }
        }
        .modifier(AssistantSurface())
    }

    private func run() {
        Task {
            let outcome = await assistant.estimateActivePlan()
            if case .needsConsent = outcome {
                asksConsent = true
            }
            // Refused: the app is already showing what Plus adds. Failed: the card says so and
            // offers to try again. Nothing else to do here.
        }
    }
}

/// The assistant's surface for a card that is not a button: the same fill and edge as
/// `AssistantCard`.
private struct AssistantSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .strokeBorder(AppColors.assistantGradient.opacity(0.6), lineWidth: 1)
            }
    }
}

// MARK: Plus

/// One plain card about DietFlow Plus, for someone on the free tier who has used the app on at
/// least two days. It says what Plus adds and that everything else stays free; no price (that is
/// for StoreKit's screen), no countdown, and closed once it never comes back.
struct PlusCard: View {
    let onShow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .top, spacing: AppSpacing.xSmall) {
                Label {
                    Text(String(localized: "today.plus.title", defaultValue: "\(AppBrand.displayName) Plus", bundle: .module))
                        .font(.headline)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AppColors.brandAccent)
                }
                .padding(.top, AppSpacing.small)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: AppSpacing.minimumHitTarget, height: AppSpacing.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("today.plus.dismiss", bundle: .module))
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onShow) {
                Text("today.plus.show", bundle: .module)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(AppColors.brandAccent)
            .padding(.top, AppSpacing.xxSmall)
        }
        .padding([.leading, .bottom], AppSpacing.medium)
        .padding(.trailing, AppSpacing.xxSmall)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    /// The allowances come from the one table that decides them, so the card cannot promise more
    /// than Plus gives.
    private var message: String {
        let recipes = AccessPolicy.limit(.aiRecipe, tier: .plus) ?? 0
        let estimates = AccessPolicy.limit(.aiNutrition, tier: .plus) ?? 0
        let plans = AccessPolicy.limit(.aiPlan, tier: .plus) ?? 0
        return String(
            localized: "today.plus.message",
            defaultValue: "More from the assistant every month: \(recipes) recipes, \(estimates) nutrition estimates and \(plans) written plans, and room for more than one plan. Your plan, widgets and reminders stay free either way.",
            bundle: .module
        )
    }
}

// MARK: End of the day

/// After the day's last meal: tomorrow's first one, calmly, instead of in the "Now" style.
struct TomorrowCard: View {
    let occurrence: MealOccurrence
    let today: CalendarDay

    var body: some View {
        ZStack {
            // Hidden, as on the timeline: a visible link in a List row would add the system's
            // chevron next to the card's own.
            NavigationLink(value: MealRoute.occurrence(occurrence.key)) { EmptyView() }
                .opacity(0)
                .accessibilityHidden(true)
            HStack(spacing: AppSpacing.small) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.indigo)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("today.tomorrow.message", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(dayName) · \(occurrence.date.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(occurrence.meal.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(occurrence.meal.typeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.medium)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }

    private var dayName: String {
        if occurrence.day == today.adding(days: 1) {
            return String(localized: "today.hero.tomorrow", bundle: .module)
        }
        return occurrence.day.middayDate().formatted(.dateTime.weekday(.wide))
    }
}

/// Meals that went by unmarked, folded into one line so the meals still ahead come first. The
/// timeline runs through it like any other row.
struct EarlierMealsRow: View {
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void

    @ScaledMetric(relativeTo: .body) private var timeColumn: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: AppSpacing.xSmall) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Color.clear.frame(width: timeColumn, height: 1)
                }
                MealStatusSymbol(.missed)
                    .frame(width: AppSpacing.minimumHitTarget, height: AppSpacing.minimumHitTarget)
                    .frame(maxHeight: .infinity)
                    .background {
                        VStack(spacing: 0) {
                            Color.clear
                            Color.clear.frame(height: 28)
                            Rectangle().fill(Color(.separator))
                                .frame(width: 1.5)
                        }
                        .accessibilityHidden(true)
                    }
                Text(String(localized: "today.earlier.title", defaultValue: "Earlier today · \(count) meals", bundle: .module))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppSpacing.small)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AppSpacing.xSmall)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(LocalizedStringKey(isExpanded ? "today.earlier.expanded" : "today.earlier.collapsed"), bundle: .module))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.small, bottom: 0, trailing: AppSpacing.small))
    }
}
