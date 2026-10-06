import Foundation
import SwiftUI
import WidgetKit
import DesignSystem
import Domain
import WidgetUI

/// A Home Screen widget on the example day, at its real size, in the look that has been chosen.
/// Everything it is given is a plain value, so while a scene around it moves it is not drawn again.
struct StagedWidget: View {
    let kind: MealWidgetKind
    let family: WidgetFamily
    /// The time of the example day the widget shows, in minutes since midnight.
    let minute: Int
    let look: WidgetPreferences

    static func size(_ family: WidgetFamily) -> CGSize {
        family == .systemSmall ? CGSize(width: 170, height: 170) : CGSize(width: 364, height: 170)
    }

    var body: some View {
        let size = Self.size(family)
        let now = TimeOfDay(minutesSinceMidnight: minute).date(on: .today())
        MealWidgetView(entry: MealWidgetEntry.sample(now: now, preferences: look), kind: kind, family: family)
            .padding(AppSpacing.medium)
            .frame(width: size.width, height: size.height)
            .background { WidgetThemeBackground(look) }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}

/// Lays its content out at a fixed size and scales it, as a whole, to the width on offer: what
/// fits in the picture is what fits on the Home Screen.
struct FitToWidth<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .frame(maxWidth: size.width)
            .overlay {
                GeometryReader { proxy in
                    content()
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(proxy.size.width / size.width)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
    }
}

// MARK: - See what is next

/// One widget through a day: the time above it moves on, and the widget with it. Nobody touches it.
struct DayLapsePreview: View {
    let isActive: Bool
    let look: WidgetPreferences
    @State private var step = 0
    @Namespace private var marker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Morning, midday, evening.
    private static let minutes = [9 * 60 + 12, 13 * 60 + 18, 18 * 60 + 40]

    var body: some View {
        VStack(spacing: AppSpacing.xLarge) {
            HStack(spacing: 0) {
                ForEach(Array(Self.minutes.enumerated()), id: \.offset) { index, minute in
                    Text(TimeOfDay(minutesSinceMidnight: minute).date(on: .today()), format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(index == step ? Color.white : Color.secondary)
                        .padding(.vertical, AppSpacing.xSmall)
                        .frame(maxWidth: .infinity)
                        .background {
                            if index == step {
                                Capsule()
                                    .fill(look.accent.fill)
                                    .matchedGeometryEffect(id: "time", in: marker)
                            }
                        }
                }
            }
            .padding(AppSpacing.xxSmall)
            .background(Color(.systemBackground), in: Capsule())
            .frame(maxWidth: 300)

            FitToWidth(size: StagedWidget.size(.systemMedium)) {
                StagedWidget(kind: .nextMeal, family: .systemMedium, minute: Self.minutes[step], look: look)
                    .id(step)
                    .transition(.blurReplace)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .task(id: isActive) {
            // Still, on the morning, with Reduce Motion: the title says the rest.
            guard isActive, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.2))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.6, bounce: 0.22)) {
                    step = (step + 1) % Self.minutes.count
                }
            }
        }
    }
}

// MARK: - Make it yours

/// The widget, and under it what can be chosen about it: which one, its colour, its tone. A tap
/// changes the widget there and then; the colour and tone are stored as the person's own.
struct WidgetSetupStage: View {
    @Binding var accent: WidgetAccent
    @Binding var background: WidgetBackgroundStyle
    let look: WidgetPreferences
    @State private var kind = MealWidgetKind.nextMeal
    @State private var hasArrived = false
    /// Goes up with every choice: the widget answers each with a small bounce.
    @State private var choices = 0
    @Namespace private var marker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Midday on the example day: one meal behind, one on now, more ahead.
    private static let minute = 13 * 60 + 18

    var body: some View {
        let isShown = hasArrived || reduceMotion
        VStack(spacing: AppSpacing.large) {
            FitToWidth(size: StagedWidget.size(.systemMedium)) {
                widget
                    .id(kind)
                    .transition(.blurReplace)
            }
            .animation(.smooth(duration: 0.35), value: look)
            .phaseAnimator([CGFloat(1), CGFloat(1.05)], trigger: choices) { content, scale in
                content.scaleEffect(reduceMotion ? 1 : scale)
            } animation: { _ in
                .spring(duration: 0.22, bounce: 0.5)
            }
            .scaleEffect(isShown ? 1 : 0.84)
            .opacity(isShown ? 1 : 0)
            .animation(.spring(duration: 0.6, bounce: 0.3), value: hasArrived)
            .accessibilityHidden(true)

            VStack(spacing: AppSpacing.small) {
                kinds
                swatches
                Picker(selection: $background) {
                    ForEach(WidgetBackgroundStyle.allCases, id: \.self) { style in
                        Text(verbatim: style.name).tag(style)
                    }
                } label: {
                    Text("onboarding.setup.tone", bundle: .module)
                }
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: 364)
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : 24)
            .animation(.spring(duration: 0.55, bounce: 0.25).delay(0.15), value: hasArrived)
        }
        .padding(.horizontal, AppSpacing.medium)
        .sensoryFeedback(.selection, trigger: choices)
        .onChange(of: background) { choices += 1 }
        .onAppear { hasArrived = true }
        .onDisappear { hasArrived = false }
    }

    /// The widget being looked at. Day Progress is small, so it is shown the way two small widgets
    /// sit side by side on a Home Screen.
    @ViewBuilder
    private var widget: some View {
        switch kind {
        case .nextMeal, .today:
            StagedWidget(kind: kind, family: .systemMedium, minute: Self.minute, look: look)
        case .progress:
            HStack(spacing: 24) {
                StagedWidget(kind: .progress, family: .systemSmall, minute: Self.minute, look: look)
                StagedWidget(kind: .nextMeal, family: .systemSmall, minute: Self.minute, look: look)
            }
        }
    }

    private var kinds: some View {
        HStack(spacing: 0) {
            ForEach(MealWidgetKind.allCases, id: \.self) { option in
                let isSelected = option == kind
                Text(verbatim: option.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .padding(.vertical, AppSpacing.xSmall)
                    .padding(.horizontal, AppSpacing.xxSmall)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(accent.fill)
                                .matchedGeometryEffect(id: "kind", in: marker)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { choose(option) }
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: option.name))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { choose(option) }
            }
        }
        .padding(AppSpacing.xxSmall)
        .background(Color(.systemBackground), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("onboarding.setup.widget", bundle: .module))
    }

    private func choose(_ option: MealWidgetKind) {
        guard option != kind else { return }
        withAppAnimation(.spring(duration: 0.45, bounce: 0.25), reduceMotion: reduceMotion) { kind = option }
        choices += 1
    }

    /// Every colour in one row. They pop in one after the other, and the chosen one stands a
    /// little larger than the rest.
    private var swatches: some View {
        let isShown = hasArrived || reduceMotion
        return HStack(spacing: 0) {
            ForEach(Array(WidgetAccent.allCases.enumerated()), id: \.element) { index, option in
                let isSelected = option == accent
                Circle()
                    .fill(option.fill)
                    // A hairline, so the darkest colour does not vanish into a dark picture.
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5) }
                    .frame(width: 24, height: 24)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(3)
                    .overlay {
                        Circle().strokeBorder(isSelected ? option.fill : Color.clear, lineWidth: 2)
                    }
                    .scaleEffect(isSelected ? 1.12 : 1)
                    .animation(.spring(duration: 0.3, bounce: 0.5), value: accent)
                    .scaleEffect(isShown ? 1 : 0.2)
                    .opacity(isShown ? 1 : 0)
                    .animation(.spring(duration: 0.45, bounce: 0.5).delay(0.3 + Double(index) * 0.04), value: hasArrived)
                    // A swatch is small; the tappable area is not.
                    .frame(maxWidth: .infinity, minHeight: AppSpacing.minimumHitTarget)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard option != accent else { return }
                        accent = option
                        choices += 1
                    }
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: option.name))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { accent = option }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("onboarding.setup.color", bundle: .module))
    }
}
