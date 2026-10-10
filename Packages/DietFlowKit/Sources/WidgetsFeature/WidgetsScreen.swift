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
    @Environment(\.scenePhase) private var scenePhase
    @State private var preview: WidgetPreview.ID?
    @State private var isInstalled: Bool?
    private let previews: [WidgetPreview]

    /// - Parameter firstPreview: the preview to open on, as "kind.size" ("today.large"); the
    ///   usual order otherwise.
    public init(firstPreview: String? = nil) {
        var all = WidgetPreview.all
        if let index = all.firstIndex(where: { $0.id == firstPreview }) {
            all.insert(all.remove(at: index), at: 0)
        }
        previews = all
        _preview = State(initialValue: all.first?.id)
    }

    private var selected: WidgetPreview {
        previews.first { $0.id == preview } ?? previews[0]
    }

    private var selectedIndex: Int {
        previews.firstIndex { $0.id == selected.id } ?? 0
    }

    /// The large widget is given more room, so it can be read; the others leave the choices
    /// under them in sight.
    private var stageHeight: CGFloat {
        selected.family == .large ? 330 : PreviewStage.height
    }

    public var body: some View {
        List {
            Section {
                VStack(spacing: AppSpacing.small) {
                    Picker(selection: sizeSelection) {
                        ForEach(PreviewSize.allCases) { size in
                            Text(verbatim: size.name).tag(size)
                        }
                    } label: {
                        Text("widgets.size", bundle: .module)
                    }
                    .pickerStyle(.segmented)

                    // Every widget there is, side by side: swipe to see the next.
                    TimelineView(.everyMinute) { context in
                        let shown = entry(at: context.date)
                        ScrollView(.horizontal) {
                            HStack(spacing: 0) {
                                ForEach(previews) { preview in
                                    PreviewStage(preview: preview, entry: shown, now: context.date)
                                        .containerRelativeFrame(.horizontal)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $preview)
                        .scrollIndicators(.hidden)
                        .frame(height: stageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                    }
                    // One element for VoiceOver: what is shown, which of how many, and a swipe up
                    // or down to the next or previous one, in place of page dots.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: selected.caption))
                    .accessibilityValue(Text(verbatim: String(localized: "widgets.preview.position", defaultValue: "\(selectedIndex + 1) of \(previews.count)", bundle: .module)))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: show(offset: 1)
                        case .decrement: show(offset: -1)
                        @unknown default: break
                        }
                    }

                    Text(verbatim: selected.caption)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .animationAware(AppMotion.settle, reduceMotion: reduceMotion, value: stageHeight)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: AppSpacing.xxSmall, trailing: 0))
            }

            // How to add it, straight under the picture of it.
            if isInstalled == true {
                Section {
                    Label {
                        Text("widgets.installed", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                    }
                } footer: {
                    Text(smartStackNote)
                }
            } else {
                Section {
                    step(1, Text("widgets.add.step1", bundle: .module))
                    step(2, Text("widgets.add.step2", bundle: .module))
                    step(3, Text(String(localized: "widgets.add.step3", defaultValue: "Search for \(AppBrand.displayName) and pick a size.", bundle: .module)))
                } header: {
                    Text(selected.family.isLockScreen ? "widgets.add.lockHeader" : "widgets.add.header", bundle: .module)
                } footer: {
                    Text(smartStackNote)
                }
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
                Toggle(isOn: setting(\.hidesMealNamesOnLockScreen)) {
                    Text("widgets.lock.hideNames", bundle: .module)
                }
            } header: {
                Text("widgets.show.header", bundle: .module)
            } footer: {
                Text(String(localized: "widgets.show.footer", defaultValue: "Applies to every \(AppBrand.displayName) widget.", bundle: .module))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("widgets.title", bundle: .module))
        // Asked again whenever the app comes back, so the steps give way to "on your Home Screen"
        // as soon as the widget has been added there.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let installed = await store.isWidgetOnScreen()
            withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
                isInstalled = installed
            }
        }
    }

    /// Smart Stack relevance (`WidgetTimelineBuilder.Relevance`), said where people add the widget.
    private var smartStackNote: String {
        String(localized: "widgets.add.smartStack", defaultValue: "In a Smart Stack, \(AppBrand.displayName) comes to the top by itself at mealtimes.", bundle: .module)
    }

    /// The size the picture shows, as the segmented control above it chooses it: choosing a size
    /// pages to its first widget.
    private var sizeSelection: Binding<PreviewSize> {
        Binding(
            get: { selected.family.previewSize },
            set: { size in
                guard let first = previews.first(where: { $0.family.previewSize == size }) else { return }
                withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
                    preview = first.id
                }
            }
        )
    }

    private func show(offset: Int) {
        let index = min(max(selectedIndex + offset, 0), previews.count - 1)
        withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
            preview = previews[index].id
        }
    }

    /// The person's own day as the widget will show it — late start included — or, before there
    /// is a plan, the example the widget gallery shows, in their colour.
    private func entry(at now: Date) -> MealWidgetEntry {
        var preferences = store.settings.widgetPreferences
        preferences.smartMealTimes = store.settings.smartMealTimes
        guard let plan = store.activePlan else {
            return MealWidgetEntry.gallery(preferences: preferences, now: now)
        }
        let snapshot = WidgetSnapshot(plan: plan, states: store.states, preferences: preferences, generatedAt: now, dayStarts: store.dayStarts)
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
        // A grid, not a scrolling row: every colour, and which one is chosen, is in sight at once.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: AppSpacing.minimumHitTarget), spacing: AppSpacing.xxSmall)], spacing: AppSpacing.xxSmall) {
            Group {
                ForEach(WidgetAccent.allCases, id: \.self) { accent in
                    let isSelected = accent == selection
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
                        // A tap, not a button: a list row can hand a tap anywhere in it to its
                        // buttons, and ten of them in one row must each get their own.
                        .onTapGesture { selection = accent }
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: accent.name))
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { selection = accent }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: AppSpacing.xxSmall, leading: AppSpacing.small, bottom: AppSpacing.xxSmall, trailing: AppSpacing.small))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("widgets.look.color", bundle: .module))
    }
}

/// One widget in one size, as the Widgets tab shows it.
struct WidgetPreview: Identifiable, Hashable {
    let kind: MealWidgetKind
    let family: PreviewFamily

    var id: String { "\(kind.previewName).\(family.rawValue)" }

    /// "Next Meal · Medium".
    var caption: String {
        String(localized: "widgets.preview.caption", defaultValue: "\(kind.name) · \(family.name)", bundle: .module)
    }

    /// By size, in the order of the size picker, Next Meal first in each.
    static let all: [WidgetPreview] = [
        WidgetPreview(kind: .nextMeal, family: .small),
        WidgetPreview(kind: .progress, family: .small),
        WidgetPreview(kind: .nextMeal, family: .medium),
        WidgetPreview(kind: .today, family: .medium),
        WidgetPreview(kind: .today, family: .large),
        WidgetPreview(kind: .nextMeal, family: .lockScreen),
        WidgetPreview(kind: .nextMeal, family: .lockCircle),
        WidgetPreview(kind: .progress, family: .lockCircle),
    ]
}

extension MealWidgetKind {
    var previewName: String {
        switch self {
        case .nextMeal: "nextMeal"
        case .today: "today"
        case .progress: "progress"
        }
    }
}

/// The sizes the picker above the previews offers.
enum PreviewSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case lockScreen

    var id: Self { self }

    var name: String {
        switch self {
        case .small: String(localized: "widgets.size.small", bundle: .module)
        case .medium: String(localized: "widgets.size.medium", bundle: .module)
        case .large: String(localized: "widgets.size.large", bundle: .module)
        case .lockScreen: String(localized: "widgets.size.lockScreen", bundle: .module)
        }
    }
}

enum PreviewFamily: String {
    case small
    case medium
    case large
    case lockScreen
    case lockCircle

    var name: String {
        switch self {
        case .small: String(localized: "widgets.size.small", bundle: .module)
        case .medium: String(localized: "widgets.size.medium", bundle: .module)
        case .large: String(localized: "widgets.size.large", bundle: .module)
        case .lockScreen, .lockCircle: String(localized: "widgets.size.lockScreen", bundle: .module)
        }
    }

    var isLockScreen: Bool {
        self == .lockScreen || self == .lockCircle
    }

    var previewSize: PreviewSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .lockScreen, .lockCircle: .lockScreen
        }
    }

    var widgetFamily: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .large: .systemLarge
        case .lockScreen: .accessoryRectangular
        case .lockCircle: .accessoryCircular
        }
    }

    /// The widget's size on a 6.1-inch iPhone.
    var size: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        case .lockScreen: CGSize(width: 172, height: 76)
        case .lockCircle: CGSize(width: 76, height: 76)
        }
    }
}

/// The widget laid out at its real size on a plain backdrop, or under a clock for the Lock Screen,
/// then scaled down as a whole where the stage is smaller: what fits in the preview is what fits
/// on the Home Screen.
struct PreviewStage: View {
    static let height: CGFloat = 236

    let preview: WidgetPreview
    let entry: MealWidgetEntry
    let now: Date

    var body: some View {
        Group {
            if preview.family.isLockScreen {
                lockScreen
            } else {
                homeScreen
            }
        }
        // The real time, so the countdowns run; taps stay with the screen around it.
        .environment(\.widgetRendering, .livePreview)
        .accessibilityElement(children: .contain)
    }

    private var homeScreen: some View {
        GeometryReader { proxy in
            let size = preview.family.size
            let margin = AppSpacing.medium * 2
            let scale = min(1, (proxy.size.width - margin) / size.width, (proxy.size.height - margin) / size.height)
            MealWidgetView(entry: entry, kind: preview.kind, family: preview.family.widgetFamily)
                .padding(AppSpacing.medium)
                .frame(width: size.width, height: size.height)
                // The same background the widget extension draws, so the preview is what will appear.
                .background { WidgetThemeBackground(entry.preferences) }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .scaleEffect(max(scale, 0.1))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var lockScreen: some View {
        VStack(spacing: AppSpacing.small) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityHidden(true)
            MealWidgetView(entry: entry, kind: preview.kind, family: preview.family.widgetFamily)
                .frame(width: preview.family.size.width, height: preview.family.size.height)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.11, green: 0.14, blue: 0.2))
    }
}
