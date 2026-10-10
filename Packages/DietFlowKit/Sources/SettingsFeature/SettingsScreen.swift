import Foundation
import SwiftUI
import UIKit
import Analytics
import AppCore
import DesignSystem
import Domain

/// The few settings the app needs, in native form sections. Appearance follows the system; there
/// is no setting for it.
public struct SettingsScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(MealAssistantModel.self) private var mealAssistant
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationsDenied = false
    @State private var confirmsDeleteAll = false
    /// Mirrors `Analytics.isOn`, which is not observable, so the switch redraws when it is flipped.
    @State private var sharesUsage = Analytics.isOn
    private let importPlan: () -> Void
    private let showPlus: () -> Void
    private let showsAssistant: Bool

    /// - Parameters:
    ///   - showsAssistant: whether this build has the assistant, so its allowance is shown.
    ///   - importPlan: opens Import Plan; Settings closes first.
    ///   - showPlus: opens the DietFlow Plus screen over Settings.
    public init(showsAssistant: Bool, importPlan: @escaping () -> Void, showPlus: @escaping () -> Void) {
        self.showsAssistant = showsAssistant
        self.importPlan = importPlan
        self.showPlus = showPlus
    }

    public var body: some View {
        NavigationStack {
            Form {
                PlusSection(showsAssistant: showsAssistant, showPlus: showPlus)
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
                    mealAssistant.forgetRecipes()
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
        // Left out of a build that cannot share anything: a switch that changes nothing is a lie.
        if Analytics.isConfigured {
            Section {
                Toggle(isOn: Binding(
                    get: { sharesUsage },
                    set: { isOn in
                        sharesUsage = isOn
                        Analytics.isOn = isOn
                    }
                )) {
                    Text("settings.usage.toggle", bundle: .module)
                }
            } footer: {
                Text("settings.usage.footer", bundle: .module)
            }
        }
        Section {
            NavigationLink {
                PrivacyScreen(showsAssistant: showsAssistant, sharesUsage: Analytics.isConfigured)
            } label: {
                Text("settings.about.privacy", bundle: .module)
            }
            Link(destination: LegalLinks.privacy) {
                Text("settings.about.privacyPolicy", bundle: .module)
            }
            Link(destination: LegalLinks.terms) {
                Text("settings.about.terms", bundle: .module)
            }
            Link(destination: LegalLinks.support) {
                Text("settings.about.support", bundle: .module)
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

/// What happens to the person's data: it stays on the phone, except the text they hand the
/// assistant, which has to reach a server to be read. The screen says exactly that.
struct PrivacyScreen: View {
    @Environment(MealPlanStore.self) private var store
    let showsAssistant: Bool
    /// Whether this build shares anonymous usage data at all.
    let sharesUsage: Bool

    var body: some View {
        List {
            Section {
                Text(String(localized: "settings.privacy.body", defaultValue: "Your plan stays on this iPhone. \(AppBrand.displayName) has no account and no advertising.", bundle: .module))
                if sharesUsage {
                    Text("settings.privacy.usage", bundle: .module)
                }
                if showsAssistant {
                    Text(String(localized: "settings.privacy.assistant", defaultValue: "When you use the assistant, the text you give it is sent through our server to \(AssistantProvider.name), whose AI reads it and writes your plan. We do not store it. Nothing else you type leaves your iPhone.", bundle: .module))
                } else {
                    Text("settings.privacy.local", bundle: .module)
                }
                Text("settings.privacy.import", bundle: .module)
                Text("settings.privacy.widget", bundle: .module)
            }
            if showsAssistant {
                Section {
                    Toggle(isOn: Binding(
                        get: { store.settings.allowsAssistantSharing },
                        set: { isOn in store.updateSettings { $0.allowsAssistantSharing = isOn } }
                    )) {
                        Text(String(localized: "settings.privacy.assistantSharing", defaultValue: "Send Assistant Text to \(AssistantProvider.name)", bundle: .module))
                    }
                } footer: {
                    Text("settings.privacy.assistantSharing.footer", bundle: .module)
                }
            }
            Section {
                Link(destination: LegalLinks.privacy) {
                    Text("settings.about.privacyPolicy", bundle: .module)
                }
            }
        }
        .navigationTitle(Text("settings.about.privacy", bundle: .module))
    }
}
