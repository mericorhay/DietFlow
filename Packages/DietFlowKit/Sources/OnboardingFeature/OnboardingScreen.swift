import Foundation
import SwiftUI
import UIKit
import WidgetKit
import AppCore
import DesignSystem
import Domain
import WidgetUI

/// First launch, three short pages: plan once, see what's next, stop deciding. The pictures are the
/// app's own views drawing a sample plan, not illustrations.
public struct OnboardingScreen: View {
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onCreatePlan: () -> Void
    private let onImportPlan: () -> Void
    private let onTrySample: () -> Void

    private static let pageCount = 3

    /// - Parameters:
    ///   - onTrySample: starts with the sample plan, for a look around first.
    ///   - initialPage: the page shown first; 0 except when checking a later page.
    public init(onCreatePlan: @escaping () -> Void, onImportPlan: @escaping () -> Void, onTrySample: @escaping () -> Void, initialPage: Int = 0) {
        self.onCreatePlan = onCreatePlan
        self.onImportPlan = onImportPlan
        self.onTrySample = onTrySample
        _page = State(initialValue: min(max(initialPage, 0), Self.pageCount - 1))
    }

    public var body: some View {
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
                    WidgetsPreview()
                }
                .tag(1)
                OnboardingPage(
                    title: Text("onboarding.time.title", bundle: .module),
                    message: Text("onboarding.time.message", bundle: .module)
                ) {
                    TimePreview()
                }
                .tag(2)
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
                Button(action: onTrySample) {
                    Text("onboarding.trySample", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: AppSpacing.minimumHitTarget)
                }
                .buttonStyle(.borderless)
                .tint(AppColors.brandAccent)
            }
        }
    }
}

/// A picture on top, a left-aligned title and one line under it.
private struct OnboardingPage<Preview: View>: View {
    let title: Text
    let message: Text
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipped()
                .accessibilityHidden(true)
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

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "onboarding.page", defaultValue: "Page \(current + 1) of \(count)", bundle: .module)))
    }
}

// MARK: - Previews of the real thing

/// A slice of the Today screen on the sample plan.
private struct TodayPreview: View {
    var body: some View {
        let today = CalendarDay.today()
        let plan = SamplePlan.keto(startingOn: today)
        let schedule = MealSchedule(plan: plan)
        let occurrences = schedule.occurrences(on: today)
        let statuses: [MealStatusSymbol.Status] = [.done, .next, .pending, .pending]
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
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
        .padding(.top, AppSpacing.xxLarge)
        .padding(.horizontal, AppSpacing.xLarge)
    }
}

/// The widget, as it sits on a Home Screen.
private struct WidgetsPreview: View {
    var body: some View {
        let entry = MealWidgetEntry.sample(now: TimeOfDay(hour: 13, minute: 18).date(on: .today()))
        VStack(spacing: AppSpacing.large) {
            MealWidgetView(entry: entry, family: .systemMedium)
                .padding(AppSpacing.medium)
                .frame(maxWidth: 364)
                .aspectRatio(364 / 170, contentMode: .fit)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            MealWidgetView(entry: entry, family: .systemSmall)
                .padding(AppSpacing.medium)
                .frame(width: 170, height: 170)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: 364, alignment: .leading)
        }
        .padding(.horizontal, AppSpacing.small)
    }
}

/// The small widget at three times of the same day: it moves on by itself. Three real-size
/// widgets are wider than a phone, so the row is scaled down to the room it has.
private struct TimePreview: View {
    private static let rowWidth: CGFloat = 3 * 170 + 2 * AppSpacing.large

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, (proxy.size.width - 2 * AppSpacing.medium) / Self.rowWidth)
            row
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var row: some View {
        let times = [TimeOfDay(hour: 9, minute: 12), TimeOfDay(hour: 13, minute: 18), TimeOfDay(hour: 18, minute: 40)]
        return HStack(spacing: AppSpacing.large) {
            ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                let date = time.date(on: .today())
                VStack(spacing: AppSpacing.small) {
                    Text(String(localized: "onboarding.preview.at", defaultValue: "At \(date.formatted(.dateTime.hour().minute()))", bundle: .module))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(index == 1 ? .primary : .secondary)
                    MealWidgetView(entry: MealWidgetEntry.sample(now: date), family: .systemSmall)
                        .padding(AppSpacing.medium)
                        .frame(width: 170, height: 170)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .opacity(index == 1 ? 1 : 0.5)
            }
        }
        .fixedSize()
    }
}
