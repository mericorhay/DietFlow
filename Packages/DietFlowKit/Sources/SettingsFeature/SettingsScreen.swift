import Foundation
import SwiftUI
import UIKit
import AppCore
import DesignSystem
import Domain

/// The few settings the app needs, in native form sections. Appearance follows the system; there
/// is no setting for it.
public struct SettingsScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationsDenied = false
    @State private var confirmsDeleteAll = false
    private let importPlan: () -> Void

    /// - Parameter importPlan: opens Import Plan; Settings closes first.
    public init(importPlan: @escaping () -> Void) {
        self.importPlan = importPlan
    }

    public var body: some View {
        NavigationStack {
            Form {
                planSection
                remindersSection
                languageSection
                dataSection
                aboutSection
            }
            .navigationTitle(Text("settings.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("settings.done", bundle: .module)
                    }
                }
            }
            .confirmationDialog(Text("settings.deleteAll.title", bundle: .module), isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
                Button(role: .destructive) {
                    store.attempt { try store.deleteAllData() }
                } label: {
                    Text("settings.deleteAll.confirm", bundle: .module)
                }
            } message: {
                Text("settings.deleteAll.message", bundle: .module)
            }
            .task {
                if store.settings.remindersEnabled {
                    notificationsDenied = await store.areNotificationsDenied()
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var planSection: some View {
        Section {
            if store.plans.count > 1 {
                Picker(selection: Binding(
                    get: { store.activePlan?.id },
                    set: { id in if let id { store.attempt { try store.activatePlan(id: id) } } }
                )) {
                    ForEach(store.plans) { plan in
                        Text(verbatim: plan.name).tag(Optional(plan.id))
                    }
                } label: {
                    Text("settings.activePlan", bundle: .module)
                }
            } else {
                LabeledContent {
                    if let name = store.activePlan?.name {
                        Text(verbatim: name)
                    } else {
                        Text("settings.activePlan.none", bundle: .module)
                    }
                } label: {
                    Text("settings.activePlan", bundle: .module)
                }
            }
        } header: {
            Text("settings.plan.header", bundle: .module)
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.settings.remindersEnabled },
                set: { isOn in
                    if isOn {
                        Task {
                            let allowed = await store.enableReminders()
                            notificationsDenied = !allowed
                        }
                    } else {
                        notificationsDenied = false
                        store.updateSettings { $0.remindersEnabled = false }
                    }
                }
            )) {
                Text("settings.reminders.toggle", bundle: .module)
            }
            Picker(selection: Binding(
                get: { store.settings.defaultReminder },
                set: { offset in store.updateSettings { $0.defaultReminder = offset } }
            )) {
                ForEach(ReminderOffset.allCases.filter { $0 != .off }, id: \.self) { offset in
                    Text(offset.displayName).tag(offset)
                }
            } label: {
                Text("settings.reminders.default", bundle: .module)
            }
            .disabled(!store.settings.remindersEnabled)
            if notificationsDenied {
                Button(action: openSystemSettings) {
                    Text("settings.reminders.openSettings", bundle: .module)
                }
            }
        } header: {
            Text("settings.reminders.header", bundle: .module)
        } footer: {
            if notificationsDenied {
                Text(String(localized: "settings.reminders.denied", defaultValue: "Notifications are off for \(AppBrand.displayName) in the Settings app.", bundle: .module))
            } else {
                Text("settings.reminders.footer", bundle: .module)
            }
        }
    }

    /// The app's language is chosen in the Settings app, which lists every language the app ships;
    /// this row says which one is in use and leads there. Dates, times and numbers follow the
    /// region, so the week and the energy unit sit beside it.
    @ViewBuilder
    private var languageSection: some View {
        Section {
            Button(action: openSystemSettings) {
                LabeledContent {
                    HStack(spacing: AppSpacing.xSmall) {
                        Text(verbatim: AppLanguage.currentName())
                        Image(systemName: "arrow.up.forward.app")
                            .font(.footnote)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.secondary)
                } label: {
                    Text("settings.language.row", bundle: .module)
                        .foregroundStyle(Color.primary)
                }
            }
            .accessibilityHint(Text("settings.language.hint", bundle: .module))
            Picker(selection: Binding(
                get: { store.settings.firstWeekday },
                set: { weekday in store.updateSettings { $0.firstWeekday = weekday } }
            )) {
                Text("settings.units.weekStart.system", bundle: .module).tag(Int?.none)
                ForEach([2, 1, 7], id: \.self) { weekday in
                    Text(Calendar.current.standaloneWeekdaySymbols[weekday - 1]).tag(Int?.some(weekday))
                }
            } label: {
                Text("settings.units.weekStart", bundle: .module)
            }
            Picker(selection: Binding(
                get: { store.settings.energyUnit },
                set: { unit in store.updateSettings { $0.energyUnit = unit } }
            )) {
                ForEach(EnergyUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            } label: {
                Text("settings.units.energy", bundle: .module)
            }
        } header: {
            Text("settings.language.header", bundle: .module)
        } footer: {
            Text(String(localized: "settings.language.footer", defaultValue: "Choose the language \(AppBrand.displayName) uses in the Settings app. Dates, times and numbers follow your iPhone’s region.", bundle: .module))
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Button {
                dismiss()
                importPlan()
            } label: {
                Text("settings.data.import", bundle: .module)
            }
            if let plan = store.activePlan {
                ShareLink(item: PlanExport(plan: plan), preview: SharePreview(plan.name)) {
                    Text("settings.data.export", bundle: .module)
                }
            }
        } header: {
            Text("settings.data.header", bundle: .module)
        }

        // Apart from import and export, so the one action that deletes everything never sits
        // between two that do not.
        Section {
            Button(role: .destructive) {
                confirmsDeleteAll = true
            } label: {
                Text("settings.data.deleteAll", bundle: .module)
            }
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyScreen()
            } label: {
                Text("settings.about.privacy", bundle: .module)
            }
            LabeledContent {
                Text(verbatim: version)
            } label: {
                Text("settings.about.version", bundle: .module)
            }
        } header: {
            Text("settings.about.header", bundle: .module)
        }
    }

    /// This app's page in the Settings app: its language, notifications and the rest.
    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// What happens to the person's data: nothing leaves the phone.
struct PrivacyScreen: View {
    var body: some View {
        List {
            Section {
                Text(String(localized: "settings.privacy.body", defaultValue: "Your plan stays on this iPhone. \(AppBrand.displayName) has no account, no analytics and no advertising, and nothing you enter is sent anywhere.", bundle: .module))
                Text("settings.privacy.import", bundle: .module)
                Text("settings.privacy.widget", bundle: .module)
            }
        }
        .navigationTitle(Text("settings.about.privacy", bundle: .module))
    }
}
