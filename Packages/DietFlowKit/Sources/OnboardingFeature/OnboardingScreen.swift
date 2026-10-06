import Foundation
import SwiftUI
import UIKit
import WidgetKit
import AppCore
import DesignSystem
import Domain
import WidgetUI

/// First launch, four short pages: plan once, see what is next, make the widget yours, put it on
/// the Home Screen. The pictures are the app's own views drawing an example day, not
/// illustrations, and they move: the day goes by, the widget takes the colour that is tapped, a
/// finger shows where to press. The example is only drawn here: nothing on this screen puts it
/// into the person's data. The colour and tone chosen here are the person's own, and are kept.
public struct OnboardingScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    private let onCreatePlan: () -> Void
    private let onImportPlan: () -> Void
    private let sceneTime: TimeInterval?

    private static let pageCount = 4

    /// - Parameters:
    ///   - initialPage: the page shown first; 0 except when checking a later page.
    ///   - sceneTime: stops the last page's animation at this many seconds in, to check one moment
    ///     of it; nil lets it play.
    public init(onCreatePlan: @escaping () -> Void, onImportPlan: @escaping () -> Void, initialPage: Int = 0, sceneTime: TimeInterval? = nil) {
        self.onCreatePlan = onCreatePlan
        self.onImportPlan = onImportPlan
        self.sceneTime = sceneTime
        _page = State(initialValue: min(max(initialPage, 0), Self.pageCount - 1))
    }

    public var body: some View {
        // The widget in every picture wears what has been chosen so far.
        let look = store.settings.widgetPreferences
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingPage(
                    title: Text("onboarding.plan.title", bundle: .module),
                    message: Text("onboarding.plan.message", bundle: .module)
                ) {
                    TodayPreview()
                }
                .tag(0)
                OnboardingPage(
                    title: Text("onboarding.widget.title", bundle: .module),
                    message: Text("onboarding.widget.message", bundle: .module)
                ) {
                    DayLapsePreview(isActive: page == 1, look: look)
                }
                .tag(1)
                OnboardingPage(
                    title: Text("onboarding.setup.title", bundle: .module),
                    message: Text("onboarding.setup.message", bundle: .module),
                    picture: .interactive
                ) {
                    WidgetSetupStage(
                        accent: setting(\.widgetAccent),
                        background: setting(\.widgetBackground),
                        look: look
                    )
                }
                .tag(2)
                OnboardingPage(
                    title: Text("onboarding.add.title", bundle: .module),
                    message: Text("onboarding.add.message", bundle: .module),
                    picture: .described(AddWidgetSteps.all.joined(separator: ". "))
                ) {
                    AddWidgetPreview(isActive: page == 3, look: look, frozenAt: sceneTime)
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                PageDots(count: Self.pageCount, current: page)
                buttons
            }
            .padding(.horizontal, AppSpacing.screenMargin)
            .padding(.bottom, AppSpacing.small)
        }
        .background(Color(.systemBackground))
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    @ViewBuilder
    private var buttons: some View {
        if page < Self.pageCount - 1 {
            Button {
                withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) { page += 1 }
            } label: {
                Text("onboarding.continue", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.brandAccent)
            .controlSize(.large)
        } else {
            VStack(spacing: AppSpacing.xSmall) {
                Button(action: onCreatePlan) {
                    Text("onboarding.create", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brandAccent)
                .controlSize(.large)
                Button(action: onImportPlan) {
                    Text("onboarding.import", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

/// What a page's picture is to VoiceOver.
enum OnboardingPicture {
    /// An illustration of what the title says: skipped.
    case decorative
    /// It has controls of its own, which speak for themselves.
    case interactive
    /// It shows something the text does not say; this says it.
    case described(String)
}

/// A picture on top, a left-aligned title and one line under it.
private struct OnboardingPage<Preview: View>: View {
    let title: Text
    let message: Text
    var picture: OnboardingPicture = .decorative
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipped()
                .modifier(PictureAccessibility(picture: picture))
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                title
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                message
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.screenMargin)
            .padding(.top, AppSpacing.xLarge)
            .padding(.bottom, AppSpacing.medium)
        }
    }
}

private struct PictureAccessibility: ViewModifier {
    let picture: OnboardingPicture

    @ViewBuilder
    func body(content: Content) -> some View {
        switch picture {
        case .decorative:
            content.accessibilityHidden(true)
        case .interactive:
            content
        case .described(let text):
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: text))
        }
    }
}

/// Where the person is: the current page's dot is drawn out into a short bar.
private struct PageDots: View {
    let count: Int
    let current: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .animationAware(AppMotion.settle, reduceMotion: reduceMotion, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "onboarding.page", defaultValue: "Page \(current + 1) of \(count)", bundle: .module)))
    }
}

// MARK: - Plan once

/// A slice of the Today screen on the sample plan. Its rows arrive one after the other.
private struct TodayPreview: View {
    @State private var hasArrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let today = CalendarDay.today()
        let plan = SamplePlan.keto(startingOn: today)
        let schedule = MealSchedule(plan: plan)
        let occurrences = schedule.occurrences(on: today)
        let statuses: [MealStatusSymbol.Status] = [.done, .next, .pending, .pending]
        let isShown = hasArrived || reduceMotion
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("onboarding.preview.today", bundle: .module)
                .font(.title.weight(.bold))
            ForEach(Array(occurrences.prefix(4).enumerated()), id: \.element.id) { index, occurrence in
                HStack(spacing: AppSpacing.small) {
                    Text(occurrence.date, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(index == 1 ? .semibold : .regular))
                        .monospacedDigit()
                        .frame(minWidth: 48, alignment: .leading)
                    MealStatusSymbol(statuses[min(index, statuses.count - 1)], font: .body)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(occurrence.meal.typeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(occurrence.meal.title)
                            .font(.subheadline.weight(index == 1 ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, AppSpacing.xSmall)
                .background {
                    if index == 1 {
                        RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous).fill(AppColors.brandWash)
                    }
                }
                .opacity(isShown ? 1 : 0)
                .offset(y: isShown ? 0 : 22)
                .animation(.spring(duration: 0.55, bounce: 0.28).delay(0.25 + Double(index) * 0.1), value: hasArrived)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
        .padding(.top, AppSpacing.xxLarge)
        .padding(.horizontal, AppSpacing.xLarge)
        // The sheet of paper comes up from the bottom of the picture.
        .offset(y: isShown ? 0 : 60)
        .animation(.spring(duration: 0.6, bounce: 0.2), value: hasArrived)
        .onAppear { hasArrived = true }
        .onDisappear { hasArrived = false }
    }
}
