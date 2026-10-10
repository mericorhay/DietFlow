import Combine
import SwiftUI
import UIKit
import StoreKit
import Analytics
import AppCore
import CookFeature
import Domain
import ImportFeature
import MealFeature
import OnboardingFeature
import PaywallFeature
import Persistence
import Purchases
import PlanFeature
import SettingsFeature
import TodayFeature
import WidgetsFeature

enum AppTab: Hashable {
    case today
    case plan
    case widgets
}

/// Everything presented over the tabs.
enum AppSheet: Identifiable {
    case settings
    case importPlan(ImportInput?)
    /// Import Plan opened straight on one of the assistant's two jobs.
    case assistant(ImportStart)
    case newMeal(dayIndex: Int)
    case newPlan
    case editPlan(MealPlan)

    var id: String {
        switch self {
        case .settings: "settings"
        case .importPlan: "importPlan"
        case .assistant: "assistant"
        case .newMeal(let dayIndex): "newMeal-\(dayIndex)"
        case .newPlan: "newPlan"
        case .editPlan(let plan): "editPlan-\(plan.id.uuidString)"
        }
    }

    /// Whether this sheet ends in a new plan beside whatever exists.
    var startsAnotherPlan: Bool {
        switch self {
        case .newPlan, .importPlan, .assistant: true
        case .settings, .newMeal, .editPlan: false
        }
    }

    /// Whether closing this sheet could lose something the person typed.
    var holdsUnsavedWork: Bool {
        switch self {
        case .settings: false
        case .importPlan, .assistant, .newMeal, .newPlan, .editPlan: true
        }
    }
}

/// A meal being cooked, shown over everything (`CookModeScreen`).
struct CookRequest: Identifiable, Hashable {
    let key: OccurrenceKey
    var id: String { key.description }
}

/// Routes between features: three tabs, the sheets over them, first-run onboarding, and the links
/// that open the app — the widget, a shared plan file, the Import Plan shortcut.
/// Features never import each other; whatever leads from one to another is decided here.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(MealPlanStore.self) private var store
    @Environment(AccessModel.self) private var access
    @Environment(PlusStore.self) private var plus
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var tab: AppTab = .today
    @State private var todayPath: [MealRoute] = []
    @State private var planPath: [MealRoute] = []
    @State private var sheet: AppSheet?
    @State private var showsOnboarding = false
    /// What Plus adds, offered once: right after the first plan is saved, when the person has seen
    /// what the app does for them, or on a later launch if that never happened.
    @State private var showsPlusIntro = false
    @State private var plansSaved = 0
    /// Cook mode, over everything.
    @State private var cooking: CookRequest?

    var body: some View {
        TabView(selection: $tab) {
            Tab("tab.today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack(path: $todayPath) {
                    TodayScreen(actions: todayActions)
                        .mealDestinations(mealActions)
                }
            }
            Tab("tab.plan", systemImage: "calendar", value: AppTab.plan) {
                NavigationStack(path: $planPath) {
                    PlanScreen(actions: planActions)
                        .mealDestinations(mealActions)
                }
            }
            Tab("tab.widgets", systemImage: "rectangle.3.group", value: AppTab.widgets) {
                NavigationStack {
                    WidgetsScreen(firstPreview: debugWidgetPreview)
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .modifier(PlusPresenter(isFrontmost: true))
        }
        .modifier(PlusPresenter(isFrontmost: sheet == nil && !showsOnboarding && !showsPlusIntro && cooking == nil))
        .fullScreenCover(item: $cooking) { request in
            CookModeScreen(occurrence: request.key) { cooking = nil }
                .modifier(PlusPresenter(isFrontmost: true))
        }
        .fullScreenCover(isPresented: $showsPlusIntro, onDismiss: plusIntroClosed) {
            PaywallScreen(reason: .intro, showsAssistant: dependencies.assistant != nil)
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingScreen(
                onCreatePlan: { finishOnboarding(then: .newPlan) },
                onImportPlan: { finishOnboarding(then: .importPlan(nil)) },
                onWritePlan: hasAssistant ? { finishOnboarding(then: .assistant(.create)) } : nil,
                initialPage: onboardingStartPage,
                sceneTime: onboardingSceneTime
            )
        }
        .sensoryFeedback(.success, trigger: plansSaved)
        .alert(
            Text("error.save.title"),
            isPresented: Binding(get: { store.failure != nil }, set: { if !$0 { store.clearFailure() } })
        ) {
            Button(role: .cancel) {} label: { Text("error.save.ok") }
        } message: {
            Text("error.save.message")
        }
        .onAppear {
            // What the app does comes first; Plus is offered once the person has seen it.
            showsOnboarding = needsOnboarding
            if !showsOnboarding, offersPlusIntro {
                Analytics.track("paywall_shown", ["reason": "intro", "moment": "launch"])
                showsPlusIntro = true
            }
            takePendingImport()
            #if DEBUG
            applyDebugLaunch()
            #endif
        }
        .onOpenURL(perform: openLink)
        .onChange(of: dependencies.pendingLink, initial: true) { _, link in
            guard let link else { return }
            dependencies.pendingLink = nil
            route(link)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // A short visit must not be lost to the next batch.
                Analytics.flush()
                // On the way to the Home Screen, where the widget is about to be looked at: write
                // what it shows once more and ask for it to be redrawn.
                store.refresh()
            }
            guard phase == .active else { return }
            // The widget's Done button may have written while the app was away, and the day may
            // have changed: bring everything up to date.
            store.refresh()
            takePendingImport()
            // A subscription may have renewed, lapsed or been bought on another device meanwhile.
            Task { await plus.refresh() }
            askForReviewIfEarned()
        }
        .onChange(of: plansSaved) { _, _ in
            // The first plan is in: the moment the app has shown what it does, and the one time
            // Plus is offered without being asked for.
            guard offersPlusIntro else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                guard sheet == nil, cooking == nil, !showsOnboarding, offersPlusIntro else { return }
                Analytics.track("paywall_shown", ["reason": "intro", "moment": "first_plan"])
                showsPlusIntro = true
            }
        }
        .onChange(of: access.request) { _, request in
            // Something only Plus does was asked for, or an allowance ran out: say so.
            guard let request else { return }
            access.request = nil
            dependencies.answer(request)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Midnight, a time zone change, or a daylight-saving jump.
            store.refresh()
        }
    }

    // MARK: Routing

    /// Whether this build has the assistant; without it nothing offers it.
    private var hasAssistant: Bool {
        dependencies.assistant != nil
    }

    private var todayActions: TodayActions {
        TodayActions(
            openSettings: { present(.settings) },
            createPlan: { present(.newPlan) },
            importPlan: { present(.importPlan(nil)) },
            addMeal: { day in present(.newMeal(dayIndex: store.schedule?.dayIndex(on: day) ?? 0)) },
            showWidgets: { tab = .widgets },
            writePlan: hasAssistant ? { present(.assistant(.create)) } : nil,
            organizeList: hasAssistant ? { present(.assistant(.organize)) } : nil,
            cook: hasAssistant ? { key in cook(key) } : nil,
            showPlus: { showPlus(from: "today") }
        )
    }

    private var mealActions: MealActions {
        MealActions(
            cook: hasAssistant ? { key in cook(key) } : nil,
            showPlus: { showPlus(from: "meal") }
        )
    }

    /// Opens cook mode for a meal. Nothing is asked of the assistant until the screen is open.
    private func cook(_ key: OccurrenceKey) {
        guard sheet == nil else { return }
        cooking = CookRequest(key: key)
    }

    /// The Plus screen, opened from an offer somewhere in the app; `source` says which, for analytics.
    private func showPlus(from source: String) {
        Analytics.track("paywall_shown", ["reason": .text(source)])
        dependencies.paywall = PaywallRequest(.upgrade)
    }

    private var planActions: PlanActions {
        PlanActions(
            addMeal: { dayIndex in present(.newMeal(dayIndex: dayIndex)) },
            importPlan: { present(.importPlan(nil)) },
            newPlan: { present(.newPlan) },
            editPlan: {
                if let plan = store.activePlan { present(.editPlan(plan)) }
            },
            openSettings: { present(.settings) },
            writePlan: hasAssistant ? { present(.assistant(.create)) } : nil,
            organizeList: hasAssistant ? { present(.assistant(.organize)) } : nil
        )
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsScreen(
                showsAssistant: dependencies.assistant != nil,
                importPlan: { present(.importPlan(nil), afterClosing: true) },
                showPlus: {
                    Analytics.track("paywall_shown", ["reason": "settings"])
                    dependencies.paywall = PaywallRequest(.upgrade)
                }
            )
        case .importPlan(let input):
            ImportPlanScreen(initialInput: input, assistant: dependencies.assistant) {
                // A saved import is a plan with meals: show what comes next.
                showToday()
                plansSaved += 1
            }
        case .assistant(let start):
            ImportPlanScreen(assistant: dependencies.assistant, start: start) {
                showToday()
                plansSaved += 1
            }
        case .newMeal(let dayIndex):
            NavigationStack {
                MealEditorScreen(mode: .new(dayIndex: dayIndex))
            }
        case .newPlan:
            NavigationStack {
                // A new plan has no meals yet: the Plan tab is where they are added, day by day.
                PlanSetupScreen(mode: .new) {
                    Analytics.track("plan_saved", ["source": "manual"])
                    planPath = []
                    tab = .plan
                    plansSaved += 1
                }
            }
        case .editPlan(let plan):
            NavigationStack {
                PlanSetupScreen(mode: .edit(plan))
            }
        }
    }

    /// Presents `next`, first letting whatever is on screen finish closing.
    private func present(_ next: AppSheet, afterClosing isClosing: Bool = false) {
        // The free plan keeps one plan. Asking for a second records the refusal, and the Plus
        // screen that follows says the current plan can be deleted instead.
        if next.startsAnotherPlan, store.hasPlans, !access.check(.additionalPlan) {
            if isClosing { sheet = nil }
            return
        }
        guard sheet != nil || isClosing else {
            sheet = next
            return
        }
        sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            sheet = next
        }
    }

    private func showToday() {
        todayPath = []
        tab = .today
    }

    private var needsOnboarding: Bool {
        !store.hasPlans && !store.settings.hasCompletedOnboarding
    }

    /// Plus is offered on its own once, never to someone who holds it, and never in a seeded state.
    private var offersPlusIntro: Bool {
        dependencies.showsPlusOnFirstLaunch && !store.settings.hasSeenPlusIntro && access.tier == .free
    }

    /// The introduction was closed, with or without a purchase: it is not shown again.
    private func plusIntroClosed() {
        store.updateSettings { $0.hasSeenPlusIntro = true }
    }

    /// Asks the App Store for a rating once, after the app has proved itself: meals marked eaten on
    /// at least three different days. Never after a refusal or an error, never twice.
    private func askForReviewIfEarned() {
        guard dependencies.showsPlusOnFirstLaunch, !store.settings.hasAskedForReview,
              sheet == nil, cooking == nil, !showsOnboarding, !showsPlusIntro,
              dependencies.paywall == nil, store.failure == nil
        else { return }
        let eaten = store.states.filter { $0.value == .completed }
        guard eaten.count >= 8, Set(eaten.keys.map(\.day)).count >= 3 else { return }
        store.updateSettings { $0.hasAskedForReview = true }
        Analytics.track("review_requested", ["meals_eaten": .int(eaten.count)])
        Task {
            // Once the app is settled on screen, not as it comes forward.
            try? await Task.sleep(for: .seconds(2))
            requestReview()
        }
    }

    private func finishOnboarding(then next: AppSheet) {
        store.updateSettings { $0.hasCompletedOnboarding = true }
        showsOnboarding = false
        present(next, afterClosing: true)
    }

    /// Text handed over by the Import Plan shortcut opens straight into review.
    private func takePendingImport() {
        // Left waiting while a form is open; it is picked up the next time the app comes forward.
        guard sheet?.holdsUnsavedWork != true else { return }
        if let text = PendingImportInbox.take() {
            present(.importPlan(.text(text)))
        }
    }

    // MARK: Links

    /// A `dietflow://` link — the widget opens the meal it shows — or a plan file opened with the
    /// app from Files, Mail or AirDrop.
    private func openLink(_ url: URL) {
        if url.isFileURL {
            openFile(url)
            return
        }
        if let link = AppLink(url: url) {
            route(link)
        }
    }

    private func route(_ link: AppLink) {
        // Any app or web page can open a dietflow:// link. It may move the person around, but it
        // must never close a form they are in the middle of filling in.
        guard sheet?.holdsUnsavedWork != true else { return }
        switch link {
        case .today:
            dismissSheet()
            showToday()
        case .meal(let key):
            dismissSheet()
            tab = .today
            todayPath = [.occurrence(key)]
        case .plan:
            dismissSheet()
            tab = .plan
        case .widgets:
            dismissSheet()
            tab = .widgets
        case .importPlan:
            present(.importPlan(nil))
        }
    }

    private func openFile(_ url: URL) {
        let input = ImportInput.reading(fileAt: url)
        // Opened files arrive as copies in the app's own Inbox; the plan is read from memory from
        // here on. Only that folder is ever cleaned up: a file somewhere else is the person's.
        if let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Inbox", isDirectory: true),
           url.resolvingSymlinksInPath().path(percentEncoded: false).hasPrefix(inbox.resolvingSymlinksInPath().path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: url)
        }
        showsOnboarding = false
        if !store.settings.hasCompletedOnboarding {
            store.updateSettings { $0.hasCompletedOnboarding = true }
        }
        present(.importPlan(input))
    }

    private func dismissSheet() {
        sheet = nil
        cooking = nil
        showsOnboarding = false
    }

    private var onboardingStartPage: Int {
        #if DEBUG
        return DebugLaunch.value("DebugOnboardingPage").flatMap(Int.init) ?? 0
        #else
        return 0
        #endif
    }

    /// A moment of the introduction's last page to stop at, for screenshots; nil lets it play.
    private var onboardingSceneTime: TimeInterval? {
        #if DEBUG
        return DebugLaunch.value("DebugOnboardingTime").flatMap(Double.init)
        #else
        return nil
        #endif
    }

    /// The widget the Widgets tab opens on, for screenshots; the usual first one otherwise.
    private var debugWidgetPreview: String? {
        #if DEBUG
        return DebugLaunch.value("DebugWidget")
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// Opens the tab, sheet or meal the launch arguments name (see DebugLaunch).
    private func applyDebugLaunch() {
        switch DebugLaunch.value("DebugTab") {
        case "plan": tab = .plan
        case "widgets": tab = .widgets
        case "today": tab = .today
        default: break
        }
        switch DebugLaunch.value("DebugSheet") {
        case "settings": sheet = .settings
        case "import": sheet = .importPlan(nil)
        case "newMeal": sheet = .newMeal(dayIndex: store.schedule?.dayIndex(on: .today()) ?? 0)
        case "newPlan": sheet = .newPlan
        case "plus": dependencies.paywall = PaywallRequest(.upgrade)
        case "write": sheet = .assistant(.create)
        case "organize": sheet = .assistant(.organize)
        case "plusIntro":
            showsOnboarding = false
            showsPlusIntro = true
        default: break
        }
        if DebugLaunch.value("DebugMeal") == "next", let focus = store.focus() {
            tab = .today
            todayPath = [.occurrence(focus.occurrence.key)]
        }
        if DebugLaunch.value("DebugCook") == "next", let focus = store.focus() {
            tab = .today
            cooking = CookRequest(key: focus.occurrence.key)
        }
    }
    #endif
}

private extension View {
    func mealDestinations(_ actions: MealActions) -> some View {
        navigationDestination(for: MealRoute.self) { route in
            MealDetailScreen(route: route, actions: actions)
        }
    }
}
