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
    case importPlan(text: String?)
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
}

/// Routes between features: three tabs, the sheets over them, and first-run onboarding.
/// Features never import each other; whatever leads from one to another is decided here.
struct RootView: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today
    @State private var sheet: AppSheet?
    @State private var showsOnboarding = false
    @State private var importsSaved = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("tab.today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack {
                    TodayScreen(actions: todayActions)
                        .mealDestinations()
                }
            }
            Tab("tab.plan", systemImage: "calendar", value: AppTab.plan) {
                NavigationStack {
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
                onImportPlan: { finishOnboarding(then: .importPlan(text: nil)) }
            )
        }
        .sensoryFeedback(.success, trigger: importsSaved)
        .onAppear {
            showsOnboarding = !store.hasPlans && !store.settings.hasCompletedOnboarding
            takePendingImport()
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
            importPlan: { present(.importPlan(text: nil)) },
            addMeal: { day in present(.newMeal(dayIndex: store.schedule?.dayIndex(on: day) ?? 0)) }
        )
    }

    private var planActions: PlanActions {
        PlanActions(
            addMeal: { dayIndex in present(.newMeal(dayIndex: dayIndex)) },
            importPlan: { present(.importPlan(text: nil)) },
            newPlan: { present(.newPlan) },
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
            SettingsScreen(importPlan: { present(.importPlan(text: nil)) })
        case .importPlan(let text):
            ImportPlanScreen(initialText: text) {
                tab = .plan
                importsSaved += 1
            }
        case .newMeal(let dayIndex):
            NavigationStack {
                MealEditorScreen(mode: .new(dayIndex: dayIndex))
            }
        case .newPlan:
            NavigationStack {
                PlanSetupScreen(mode: .new) { tab = .plan }
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

    private func finishOnboarding(then next: AppSheet) {
        store.updateSettings { $0.hasCompletedOnboarding = true }
        showsOnboarding = false
        present(next, afterClosing: true)
    }

    /// Text handed over by the Import Plan shortcut opens straight into review.
    private func takePendingImport() {
        if let text = PendingImportInbox.take() {
            present(.importPlan(text: text))
        }
    }
}

private extension View {
    func mealDestinations() -> some View {
        navigationDestination(for: MealRoute.self) { route in
            MealDetailScreen(route: route)
        }
    }
}
