import Combine
import SwiftUI
import UIKit
import AppCore
import Domain
import ImportFeature
import MealFeature
import OnboardingFeature
import Persistence
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
    case newMeal(dayIndex: Int)
    case newPlan
    case editPlan(MealPlan)

    var id: String {
        switch self {
        case .settings: "settings"
        case .importPlan: "importPlan"
        case .newMeal(let dayIndex): "newMeal-\(dayIndex)"
        case .newPlan: "newPlan"
        case .editPlan(let plan): "editPlan-\(plan.id.uuidString)"
        }
    }

    /// Whether closing this sheet could lose something the person typed.
    var holdsUnsavedWork: Bool {
        switch self {
        case .settings: false
        case .importPlan, .newMeal, .newPlan, .editPlan: true
        }
    }
}

/// Routes between features: three tabs, the sheets over them, first-run onboarding, and the links
/// that open the app — the widget, a shared plan file, the Import Plan shortcut.
/// Features never import each other; whatever leads from one to another is decided here.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(MealPlanStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today
    @State private var todayPath: [MealRoute] = []
    @State private var planPath: [MealRoute] = []
    @State private var sheet: AppSheet?
    @State private var showsOnboarding = false
    @State private var plansSaved = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("tab.today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack(path: $todayPath) {
                    TodayScreen(actions: todayActions)
                        .mealDestinations()
                }
            }
            Tab("tab.plan", systemImage: "calendar", value: AppTab.plan) {
                NavigationStack(path: $planPath) {
                    PlanScreen(actions: planActions)
                        .mealDestinations()
                }
            }
            Tab("tab.widgets", systemImage: "rectangle.3.group", value: AppTab.widgets) {
                NavigationStack {
                    WidgetsScreen()
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingScreen(
                onCreatePlan: { finishOnboarding(then: .newPlan) },
                onImportPlan: { finishOnboarding(then: .importPlan(nil)) },
                onTrySample: trySamplePlan,
                initialPage: onboardingStartPage
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
            showsOnboarding = !store.hasPlans && !store.settings.hasCompletedOnboarding
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
            guard phase == .active else { return }
            // The widget's Done button may have written while the app was away, and the day may
            // have changed: bring everything up to date.
            store.refresh()
            takePendingImport()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Midnight, a time zone change, or a daylight-saving jump.
            store.refresh()
        }
    }

    // MARK: Routing

    private var todayActions: TodayActions {
        TodayActions(
            openSettings: { present(.settings) },
            createPlan: { present(.newPlan) },
            importPlan: { present(.importPlan(nil)) },
            trySample: trySamplePlan,
            addMeal: { day in present(.newMeal(dayIndex: store.schedule?.dayIndex(on: day) ?? 0)) },
            showWidgets: { tab = .widgets }
        )
    }

    private var planActions: PlanActions {
        PlanActions(
            addMeal: { dayIndex in present(.newMeal(dayIndex: dayIndex)) },
            importPlan: { present(.importPlan(nil)) },
            newPlan: { present(.newPlan) },
            trySample: trySamplePlan,
            editPlan: {
                if let plan = store.activePlan { present(.editPlan(plan)) }
            },
            openSettings: { present(.settings) }
        )
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsScreen(importPlan: { present(.importPlan(nil), afterClosing: true) })
        case .importPlan(let input):
            ImportPlanScreen(initialInput: input) {
                // A saved import is a plan with meals: show what comes next.
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

    private func finishOnboarding(then next: AppSheet) {
        store.updateSettings { $0.hasCompletedOnboarding = true }
        showsOnboarding = false
        present(next, afterClosing: true)
    }

    private func trySamplePlan() {
        store.attempt { try store.addSamplePlan() }
        store.updateSettings { $0.hasCompletedOnboarding = true }
        showsOnboarding = false
        showToday()
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
        showsOnboarding = false
    }

    private var onboardingStartPage: Int {
        #if DEBUG
        return DebugLaunch.value("DebugOnboardingPage").flatMap(Int.init) ?? 0
        #else
        return 0
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
        default: break
        }
        if DebugLaunch.value("DebugMeal") == "next", let focus = store.focus() {
            tab = .today
            todayPath = [.occurrence(focus.occurrence.key)]
        }
    }
    #endif
}

private extension View {
    func mealDestinations() -> some View {
        navigationDestination(for: MealRoute.self) { route in
            MealDetailScreen(route: route)
        }
    }
}
