import Foundation
import SwiftUI
import UIKit
import AppCore
import DesignSystem
import Domain

/// Cooking one meal, step by step: what goes in and what could go in instead, then one step at a
/// time with its timer, and at the end, marking the meal eaten. The assistant writes the recipe
/// (`MealAssistantModel.recipe`); a recipe written once opens again for free.
///
/// Shown over everything by the app, which owns its presentation so the Plus screen can be shown
/// on top of it when an allowance runs out. While it is open the screen stays awake, steps can be
/// read aloud, and Magic Tap moves on: hands that are busy with food need not touch the phone.
public struct CookModeScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(MealAssistantModel.self) private var assistant
    @Environment(AccessModel.self) private var access
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let key: OccurrenceKey
    private let onClose: () -> Void
    private let showPlus: (() -> Void)?
    private let startingStep: Int?

    @State private var phase: Phase = .loading
    @State private var meal: Meal?
    @State private var recipe: Recipe?
    @State private var servings = 1
    @State private var page = 0
    @State private var checked: Set<Int> = []
    @State private var swapsFor: SwapsRoute?
    // Another number of servings: waiting to be confirmed, being written, or what went wrong.
    @State private var pendingServings: Int?
    @State private var isRewriting = false
    @State private var rewriteError: AssistantError?
    @State private var asksConsent = false
    @State private var afterConsent: ConsentFollowUp = .recipe
    @State private var timers = CookTimers()
    @State private var voice = CookVoice()
    @State private var hasStarted = false
    @State private var hasAppliedStartingStep = false
    @State private var didEat = false
    @State private var ateCount = 0
    @AppStorage("cook.readsAloud.v1") private var readsAloud = false

    /// - Parameters:
    ///   - key: the meal, on the day it is being cooked for.
    ///   - onClose: closes the screen; called once, whichever way it ends.
    ///   - showPlus: opens the Plus screen again from the "used up" state; nil hides that button.
    ///   - startingStep: opens on this step once the recipe is there (1 is the first step; past the
    ///     last step is the last page). For screenshots; nil opens on the overview.
    public init(occurrence key: OccurrenceKey, onClose: @escaping () -> Void, showPlus: (() -> Void)? = nil, startingStep: Int? = nil) {
        self.key = key
        self.onClose = onClose
        self.showPlus = showPlus
        self.startingStep = startingStep
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
        }
        .assistantConsent(isPresented: $asksConsent) {
            assistant.allowSharing()
            Task { await askAgainAfterConsent() }
        }
        .sheet(item: $swapsFor) { route in
            SwapsSheet(ingredient: route.ingredient, energyUnit: store.settings.energyUnit)
        }
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.success, trigger: ateCount)
        .sensoryFeedback(.impact(weight: .heavy), trigger: timers.finishedCount)
        .task { await start() }
        .onAppear {
            // Cook mode is open while hands are busy; the phone must not lock between steps.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            voice.stop()
        }
        .onChange(of: page) { _, _ in
            readCurrentStep()
        }
        .onChange(of: readsAloud) { _, isOn in
            if isOn { readCurrentStep() } else { voice.stop() }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .missing:
            ContentUnavailableView {
                Label {
                    Text("cook.missing.title", bundle: .module)
                } icon: {
                    Image(systemName: "fork.knife")
                }
            } description: {
                Text("cook.missing.message", bundle: .module)
            }
        case .loading:
            if let meal {
                CookLoadingView(meal: meal, avoids: avoiding != nil)
            } else {
                Color.clear
            }
        case .consent:
            consentView
        case .refused:
            refusedView
        case .failed(let error):
            failedView(error)
        case .ready:
            if let recipe, let meal {
                cooking(recipe, meal: meal)
            } else {
                Color.clear
            }
        }
    }

    private func cooking(_ recipe: Recipe, meal: Meal) -> some View {
        TabView(selection: $page) {
            CookOverview(
                recipe: recipe,
                meal: meal,
                servings: pendingServings ?? servings,
                change: servingsChange,
                isRewriting: isRewriting,
                avoiding: avoiding,
                checked: $checked,
                onServings: requestServings,
                onSwaps: { index in
                    guard recipe.ingredients.indices.contains(index) else { return }
                    swapsFor = SwapsRoute(index: index, ingredient: recipe.ingredients[index])
                }
            )
            .tag(0)
            ForEach(Array(recipe.steps.indices), id: \.self) { index in
                CookStepPage(step: recipe.steps[index], number: index + 1, timers: timers)
                    .tag(index + 1)
            }
            CookFinishPage(meal: meal, isVisible: page == lastPage, state: finishState)
                .tag(lastPage)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .top, spacing: 0) {
            if isStepPage {
                stepProgress(count: recipe.steps.count)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .accessibilityAction(.magicTap) {
            if page < lastPage { go(to: page + 1) }
        }
    }

    private func stepProgress(count: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(String(localized: "cook.step.progress", defaultValue: "Step \(page) of \(count)", bundle: .module))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
            ProgressView(value: Double(min(page, count)), total: Double(max(count, 1)))
                .tint(AppColors.brandAccent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, AppSpacing.screenMargin)
        .padding(.top, AppSpacing.xxSmall)
        .padding(.bottom, AppSpacing.xSmall)
        .background(Color(.systemBackground))
        .animationAware(AppMotion.snappy, reduceMotion: reduceMotion, value: page)
        .accessibilityElement(children: .combine)
    }

    // MARK: Bottom bar

    /// One prominent action at a time: Start Cooking on the overview, Next on a step, I Ate It at
    /// the end.
    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: AppSpacing.xSmall) {
            if page == 0 {
                Button {
                    go(to: 1)
                } label: {
                    Label {
                        Text("cook.start", bundle: .module)
                    } icon: {
                        Image(systemName: "flame.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppColors.brandAccent)
                .disabled(isRewriting)
            } else if page == lastPage {
                finishButtons
            } else {
                stepButtons
            }
        }
        .padding(.horizontal, AppSpacing.screenMargin)
        .padding(.vertical, AppSpacing.small)
        .background(.bar)
    }

    private var stepButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.small) {
                backButton
                nextButton
            }
            VStack(spacing: AppSpacing.xSmall) {
                nextButton
                backButton
            }
        }
    }

    private var backButton: some View {
        Button {
            go(to: page - 1)
        } label: {
            Label {
                Text("cook.step.back", bundle: .module)
            } icon: {
                Image(systemName: "chevron.backward")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(AppColors.brandAccent)
    }

    private var nextButton: some View {
        let isLastStep = page >= (recipe?.steps.count ?? 0)
        return Button {
            go(to: page + 1)
        } label: {
            Label {
                if isLastStep {
                    Text("cook.step.finish", bundle: .module)
                } else {
                    Text("cook.step.next", bundle: .module)
                }
            } icon: {
                Image(systemName: isLastStep ? "checkmark" : "chevron.forward")
            }
            .labelStyle(TrailingIconLabelStyle())
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(AppColors.brandAccent)
    }

    @ViewBuilder
    private var finishButtons: some View {
        if finishState == .canMark {
            Button(action: markEaten) {
                Label {
                    Text("cook.finish.ate", bundle: .module)
                } icon: {
                    Image(systemName: didEat ? "checkmark.circle.fill" : "checkmark")
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppColors.brandAccent)
            .disabled(didEat)
            closeButton
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(AppColors.brandAccent)
        } else {
            closeButton
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppColors.brandAccent)
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Text("cook.close", bundle: .module)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: States before the recipe

    private var consentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                if let meal {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        MealGlyph(meal.type, size: 56)
                        Text(verbatim: meal.title)
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                AssistantCard(
                    symbol: "sparkles",
                    title: Text("cook.consent.title", bundle: .module),
                    subtitle: Text("cook.consent.message", bundle: .module),
                    style: .prominent
                ) {
                    asksConsent = true
                }
            }
            .padding(.horizontal, AppSpacing.screenMargin)
            .padding(.vertical, AppSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var refusedView: some View {
        ContentUnavailableView {
            Label {
                Text("cook.refused.title", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppColors.brandAccent)
            }
        } description: {
            Text("cook.refused.message", bundle: .module)
        } actions: {
            if let showPlus, access.tier == .free {
                Button(action: showPlus) {
                    Label {
                        Text("cook.refused.plus", bundle: .module)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brandAccent)
            }
            Button(action: close) {
                Text("cook.close", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
    }

    private func failedView(_ error: AssistantError) -> some View {
        ContentUnavailableView {
            Label {
                Text("cook.failed.title", bundle: .module)
            } icon: {
                Image(systemName: CookWords.symbol(for: error))
            }
        } description: {
            VStack(spacing: AppSpacing.xSmall) {
                Text(verbatim: CookWords.message(for: error))
                Text("cook.failed.notCounted", bundle: .module)
                    .font(.footnote)
            }
        } actions: {
            Button {
                Task { await load(servings: servings) }
            } label: {
                Text("cook.retry", bundle: .module)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.brandAccent)
            Button(action: close) {
                Text("cook.close", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(Text("cook.close", bundle: .module))
        }
        if phase == .ready {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $readsAloud) {
                    Label {
                        Text("cook.readAloud", bundle: .module)
                    } icon: {
                        Image(systemName: readsAloud ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                }
                .toggleStyle(.button)
                .tint(AppColors.brandAccent)
            }
        }
    }

    // MARK: Asking

    private func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        guard let occurrence = store.occurrence(for: key) else {
            phase = .missing
            return
        }
        meal = occurrence.meal
        // A recipe written before, for any number of servings, opens at once and costs nothing.
        for count in 1...8 {
            if let kept = assistant.cachedRecipe(for: occurrence.meal, servings: count) {
                show(kept, servings: count)
                return
            }
        }
        await load(servings: 1)
    }

    private func load(servings count: Int) async {
        guard let meal else {
            phase = .missing
            return
        }
        withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { phase = .loading }
        switch await assistant.recipe(for: meal, servings: count) {
        case .success(let written):
            show(written, servings: count)
        case .needsConsent:
            afterConsent = .recipe
            withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { phase = .consent }
            asksConsent = true
        case .refused:
            withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { phase = .refused }
        case .failed(let error):
            withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { phase = .failed(error) }
        case .unavailable:
            close()
        }
    }

    private func show(_ written: Recipe, servings count: Int) {
        if recipe != nil { timers.stopAll() }
        withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
            recipe = written
            servings = count
            checked = []
            phase = .ready
            page = min(page, written.steps.count + 1)
        }
        if let startingStep, !hasAppliedStartingStep {
            hasAppliedStartingStep = true
            page = min(max(startingStep, 0), written.steps.count + 1)
        }
    }

    private func askAgainAfterConsent() async {
        switch afterConsent {
        case .recipe: await load(servings: servings)
        case .servings: await writeForPendingServings()
        }
    }

    /// Another number of servings. One already written opens at once; a new one waits for the
    /// person to see what it costs and say yes.
    private func requestServings(_ count: Int) {
        let count = min(max(count, 1), 8)
        rewriteError = nil
        guard count != servings else {
            withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { pendingServings = nil }
            return
        }
        if let meal, let kept = assistant.cachedRecipe(for: meal, servings: count) {
            pendingServings = nil
            show(kept, servings: count)
        } else {
            withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { pendingServings = count }
        }
    }

    private func writeForPendingServings() async {
        guard let count = pendingServings, let meal, !isRewriting else { return }
        rewriteError = nil
        isRewriting = true
        let outcome = await assistant.recipe(for: meal, servings: count)
        isRewriting = false
        switch outcome {
        case .success(let written):
            pendingServings = nil
            show(written, servings: count)
        case .needsConsent:
            afterConsent = .servings
            asksConsent = true
        case .refused, .unavailable:
            // The Plus screen or the "comes back on" alert is on its way; the recipe stays as it was.
            withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { pendingServings = nil }
        case .failed(let error):
            rewriteError = error
        }
    }

    private var servingsChange: ServingsChange? {
        guard let count = pendingServings else { return nil }
        return ServingsChange(
            servings: count,
            cost: AssistantCost.caption(remaining: assistant.remaining(.aiRecipe), tier: access.tier),
            isWorking: isRewriting,
            error: rewriteError,
            onConfirm: { Task { await writeForPendingServings() } },
            onCancel: {
                rewriteError = nil
                withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { pendingServings = nil }
            }
        )
    }

    // MARK: Moving

    private var lastPage: Int { (recipe?.steps.count ?? 0) + 1 }

    private var isStepPage: Bool { page >= 1 && page < lastPage }

    private func go(to target: Int) {
        let target = min(max(target, 0), lastPage)
        guard target != page else { return }
        withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { page = target }
    }

    /// Reads the step on screen when reading aloud is on; stops on any other page.
    private func readCurrentStep() {
        guard readsAloud, let recipe, isStepPage, recipe.steps.indices.contains(page - 1) else {
            voice.stop()
            return
        }
        let text = recipe.steps[page - 1].text
        voice.speak(String(localized: "cook.speech.step", defaultValue: "Step \(page). \(text)", bundle: .module))
    }

    // MARK: Finishing

    private var avoiding: String? {
        store.settings.foodsToAvoid.trimmedNonEmpty
    }

    private var finishState: CookFinishState {
        if didEat { return .eaten }
        guard let occurrence = store.occurrence(for: key) else { return .nothing }
        switch occurrence.state {
        case .completed:
            return .eaten
        case .pending:
            return occurrence.day <= CalendarDay.today() ? .canMark : .later
        case .skipped:
            return .nothing
        }
    }

    private func markEaten() {
        guard finishState == .canMark, store.attempt({ try store.markMealCompleted(key) }) != nil else { return }
        withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) { didEat = true }
        ateCount += 1
        Task {
            // Long enough to feel the haptic and see the check settle; then the meal is done.
            try? await Task.sleep(for: .milliseconds(700))
            close()
        }
    }

    private func close() {
        timers.stopAll()
        voice.stop()
        onClose()
    }
}

// MARK: Types

extension CookModeScreen {
    fileprivate enum Phase: Equatable {
        case loading
        case consent
        case refused
        case failed(AssistantError)
        case ready
        case missing
    }

    /// What to ask again once the person agrees to sharing.
    fileprivate enum ConsentFollowUp {
        case recipe
        case servings
    }
}

/// The ingredient whose swaps are open.
private struct SwapsRoute: Identifiable {
    let index: Int
    let ingredient: Recipe.Ingredient

    var id: Int { index }
}

/// The title first and the symbol after it: "Next ›".
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: AppSpacing.xSmall) {
            configuration.title
            configuration.icon
        }
    }
}
