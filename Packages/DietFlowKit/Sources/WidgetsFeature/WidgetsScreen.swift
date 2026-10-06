import Foundation
import SwiftUI
import UIKit
import WidgetKit
import AppCore
import DesignSystem
import Domain
import WidgetUI

/// The widget is the product; this is where the person sees it, chooses what it shows, and learns
/// how to add it. The previews are the real widget views drawing the real plan.
public struct WidgetsScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var family: PreviewFamily = .medium
    @State private var isInstalled: Bool?

    public init() {}

    public var body: some View {
        List {
            Section {
                Picker(selection: $family) {
                    ForEach(PreviewFamily.allCases) { family in
                        Text(family.name).tag(family)
                    }
                } label: {
                    Text("widgets.size", bundle: .module)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.xxSmall, bottom: AppSpacing.small, trailing: AppSpacing.xxSmall))

                TimelineView(.everyMinute) { context in
                    PreviewStage(family: family, entry: entry(at: context.date), now: context.date)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .animation(AppMotion.animation(AppMotion.settle, reduceMotion: reduceMotion), value: family)
            }

            Section {
                ColorSwatches(selection: setting(\.widgetAccent))
                Picker(selection: setting(\.widgetBackground)) {
                    ForEach(WidgetBackgroundStyle.allCases, id: \.self) { style in
                        Text(style.name).tag(style)
                    }
                } label: {
                    Text("widgets.look.background", bundle: .module)
                }
            } header: {
                Text("widgets.look.header", bundle: .module)
            } footer: {
                Text("widgets.look.footer", bundle: .module)
            }

            Section {
                Picker(selection: setting(\.mealWindowMinutes)) {
                    ForEach(windowOptions, id: \.self) { minutes in
                        Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
                            .tag(minutes)
                    }
                } label: {
                    Text("widgets.timing.window", bundle: .module)
                }
                Toggle(isOn: setting(\.showDoneButtonOnWidget)) {
                    Text("widgets.timing.done", bundle: .module)
                }
            } header: {
                Text("widgets.timing.header", bundle: .module)
            } footer: {
                Text("widgets.timing.footer", bundle: .module)
            }

            Section {
                Toggle(isOn: setting(\.showCaloriesOnWidget)) {
                    Text("widgets.show.calories", bundle: .module)
                }
                Toggle(isOn: setting(\.showFollowingMealOnWidget)) {
                    Text("widgets.show.following", bundle: .module)
                }
                Toggle(isOn: setting(\.showCompletedMealsOnWidget)) {
                    Text("widgets.show.completed", bundle: .module)
                }
            } header: {
                Text("widgets.show.header", bundle: .module)
            } footer: {
                Text(String(localized: "widgets.show.footer", defaultValue: "Applies to every \(AppBrand.displayName) widget.", bundle: .module))
            }

            if isInstalled == true {
                Section {
                    Label {
                        Text("widgets.installed", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                    }
                }
            } else {
                Section {
                    step(1, Text("widgets.add.step1", bundle: .module))
                    step(2, Text("widgets.add.step2", bundle: .module))
                    step(3, Text(String(localized: "widgets.add.step3", defaultValue: "Search for \(AppBrand.displayName) and pick a size.", bundle: .module)))
                } header: {
                    Text(family == .lockScreen ? "widgets.add.lockHeader" : "widgets.add.header", bundle: .module)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("widgets.title", bundle: .module))
        .task {
            isInstalled = await store.isWidgetOnScreen()
        }
    }

    private func entry(at now: Date) -> MealWidgetEntry {
        guard let plan = store.activePlan else {
            return MealWidgetEntry.sample(now: now, preferences: store.settings.widgetPreferences)
        }
        let snapshot = WidgetSnapshot(plan: plan, states: store.states, preferences: store.settings.widgetPreferences, generatedAt: now)
        return MealWidgetEntry.current(for: snapshot, now: now)
    }

    /// What the picker offers, with whatever is stored added if it is not one of them, so the
    /// picker always has a row for the value in force.
    private var windowOptions: [Int] {
        let stored = store.settings.mealWindowMinutes
        return WidgetPreferences.windowOptions.contains(stored)
            ? WidgetPreferences.windowOptions
            : (WidgetPreferences.windowOptions + [stored]).sorted()
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in
                withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                    store.updateSettings { $0[keyPath: keyPath] = newValue }
                }
            }
        )
    }

    private func step(_ number: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
            Text(number, format: .number)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 24, minHeight: 24)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
                .accessibilityHidden(true)
            text
        }
        .padding(.vertical, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
    }
}

/// The widget's colour, as a row of swatches: seen, not read from a list of names.
private struct ColorSwatches: View {
    @Binding var selection: WidgetAccent

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xSmall) {
                ForEach(WidgetAccent.allCases, id: \.self) { accent in
                    let isSelected = accent == selection
                    Button {
                        selection = accent
                    } label: {
                        Circle()
                            .fill(accent.fill)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(4)
                            .overlay {
                                Circle().strokeBorder(isSelected ? accent.fill : Color.clear, lineWidth: 2)
                            }
                            // A swatch is small; the tappable area is not.
                            .frame(minWidth: AppSpacing.minimumHitTarget, minHeight: AppSpacing.minimumHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: accent.name))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: AppSpacing.xxSmall, leading: AppSpacing.small, bottom: AppSpacing.xxSmall, trailing: 0))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("widgets.look.color", bundle: .module))
    }
}

extension WidgetAccent {
    var name: String {
        switch self {
        case .terracotta: String(localized: "widgets.color.terracotta", bundle: .module)
        case .orange: String(localized: "widgets.color.orange", bundle: .module)
        case .red: String(localized: "widgets.color.red", bundle: .module)
        case .pink: String(localized: "widgets.color.pink", bundle: .module)
        case .purple: String(localized: "widgets.color.purple", bundle: .module)
        case .indigo: String(localized: "widgets.color.indigo", bundle: .module)
        case .blue: String(localized: "widgets.color.blue", bundle: .module)
        case .teal: String(localized: "widgets.color.teal", bundle: .module)
        case .green: String(localized: "widgets.color.green", bundle: .module)
        case .graphite: String(localized: "widgets.color.graphite", bundle: .module)
        }
    }
}

extension WidgetBackgroundStyle {
    var name: String {
        switch self {
        case .system: String(localized: "widgets.background.system", bundle: .module)
        case .soft: String(localized: "widgets.background.soft", bundle: .module)
        case .bold: String(localized: "widgets.background.bold", bundle: .module)
        case .dark: String(localized: "widgets.background.dark", bundle: .module)
        }
    }
}

enum PreviewFamily: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case lockScreen

    var id: String { rawValue }

    var name: String {
        switch self {
        case .small: String(localized: "widgets.size.small", bundle: .module)
        case .medium: String(localized: "widgets.size.medium", bundle: .module)
        case .large: String(localized: "widgets.size.large", bundle: .module)
        case .lockScreen: String(localized: "widgets.size.lockScreen", bundle: .module)
        }
    }

    var widgetFamily: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .large: .systemLarge
        case .lockScreen: .accessoryRectangular
        }
    }

    /// The widget's size on a 6.1-inch iPhone. Previews shrink to fit narrower screens.
    var size: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        case .lockScreen: CGSize(width: 172, height: 76)
        }
    }
}

/// The widget drawn at its real size on a plain backdrop, or under a clock for the Lock Screen.
struct PreviewStage: View {
    let family: PreviewFamily
    let entry: MealWidgetEntry
    let now: Date

    var body: some View {
        Group {
            if family == .lockScreen {
                lockScreen
            } else {
                homeScreen
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var homeScreen: some View {
        MealWidgetView(entry: entry, family: family.widgetFamily)
            .padding(AppSpacing.medium)
            .frame(maxWidth: family.size.width)
            .aspectRatio(family.size.width / family.size.height, contentMode: .fit)
            // The same background the widget extension draws, so the preview is what will appear.
            .background { WidgetThemeBackground(entry.preferences) }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .padding(.vertical, AppSpacing.xLarge)
            .padding(.horizontal, AppSpacing.small)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .id(family)
            .transition(.opacity)
    }

    private var lockScreen: some View {
        VStack(spacing: AppSpacing.small) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityHidden(true)
            MealWidgetView(entry: entry, family: .accessoryRectangular)
                .frame(maxWidth: family.size.width, minHeight: family.size.height)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.vertical, AppSpacing.xLarge)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.11, green: 0.14, blue: 0.2), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .id(family)
        .transition(.opacity)
    }
}
