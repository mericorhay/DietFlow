import SwiftUI
import WidgetKit
import Domain
import DesignSystem

/// The widgets the app offers. The raw values are the kinds WidgetKit stores for widgets already
/// on someone's Home Screen, so they never change.
public enum MealWidgetKind: String, CaseIterable, Sendable {
    /// What to eat now or next, and when.
    case nextMeal = "NextMeal"
    /// The whole day as a list.
    case today = "TodayMeals"
    /// How far through the day's meals the person is.
    case progress = "DayProgress"

    public var families: [WidgetFamily] {
        switch self {
        case .nextMeal: [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
        case .today: [.systemMedium, .systemLarge]
        case .progress: [.systemSmall, .accessoryCircular]
        }
    }
}

extension WidgetDayContent {
    /// Today's meals that are behind the person: marked, or their time gone by. Nothing has to be
    /// ticked off for the day to move along.
    var mealsBehind: Int {
        schedule.filter { !$0.role.isOpenAhead }.count
    }

    var progressAccessibilityLabel: String {
        String(localized: "widget.progress.accessibility", defaultValue: "Meals today: \(mealsBehind) of \(schedule.count)", bundle: .module)
    }
}

/// A ring that fills as the day's meals go by.
struct WidgetProgressRing: View {
    let done: Int
    let total: Int
    var lineWidth: CGFloat = 6
    @Environment(\.widgetTheme) private var theme

    private var fraction: Double {
        total > 0 ? min(Double(done) / Double(total), 1) : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(theme.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Image(systemName: fraction >= 1 ? "checkmark" : "fork.knife")
                .font(.footnote.weight(.bold))
                .foregroundStyle(theme.tint)
                .widgetAccentable()
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Day Progress, small: how many of today's meals are behind, and the one in front.
struct ProgressWidgetView: View {
    let entry: MealWidgetEntry

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content) {
            message
        } else if case .active(let day) = entry.content {
            if day.schedule.isEmpty {
                // Nothing today: the meal the plan has next says more than an empty ring.
                SmallMealWidgetView(entry: entry)
            } else {
                progress(day)
            }
        }
    }

    private func progress(_ day: WidgetDayContent) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            HStack(spacing: AppSpacing.small) {
                WidgetProgressRing(done: day.mealsBehind, total: day.schedule.count)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(day.mealsBehind.formatted())/\(day.schedule.count.formatted())")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("widget.progress.caption", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let primary = day.primary, let lead = day.lead {
                WidgetLeadLabel(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                Text(verbatim: WidgetText.inline(primary))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(day))
    }

    private func accessibilityLabel(_ day: WidgetDayContent) -> String {
        [day.progressAccessibilityLabel, day.primary?.accessibilityLabel].compactMap { $0 }.joined(separator: ". ")
    }
}

/// Day Progress on the Lock Screen: the same ring, drawn by the system in its own colours.
struct CircularProgressWidgetView: View {
    let entry: MealWidgetEntry

    var body: some View {
        if case .active(let day) = entry.content, !day.schedule.isEmpty {
            Gauge(value: Double(day.mealsBehind), in: 0...Double(day.schedule.count)) {
                Image(systemName: "fork.knife")
            } currentValueLabel: {
                Text(verbatim: "\(day.mealsBehind.formatted())/\(day.schedule.count.formatted())")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(day.progressAccessibilityLabel)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "fork.knife")
                    .font(.title3)
            }
            .accessibilityLabel(Text(verbatim: WidgetText.appName()))
        }
    }
}
