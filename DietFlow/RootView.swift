import SwiftUI
import AssistantFeature
import PlanFeature
import SettingsFeature
import TodayFeature

/// Routes between features. Placeholder navigation: the real shell replaces this body.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("tab.today", systemImage: "sun.max") {
                TodayScreen()
            }
            Tab("tab.plan", systemImage: "calendar") {
                PlanScreen()
            }
            Tab("tab.assistant", systemImage: "sparkles") {
                AssistantScreen()
            }
            Tab("tab.settings", systemImage: "gearshape") {
                SettingsScreen()
            }
        }
    }
}
