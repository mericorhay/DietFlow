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
        case .nextMeal: [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular]
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

/// How each meal of the day colours its part of a ring or bar: eaten in full colour, skipped or
/// missed faded, the one on now half way, and what is still ahead as the track.
struct WidgetSegmentStyle {
    let theme: WidgetTheme

    func color(_ role: MealRole) -> Color {
        switch role {
        case .done: theme.tint
        case .skipped, .past: theme.tint.opacity(0.4)
        case .current: theme.tint.opacity(0.65)
        case .next, .upcoming: Color.primary.opacity(0.12)
        }
    }
}

/// A ring with one segment per meal of the day, filling as the meals go by.
struct WidgetSegmentedRing<Center: View>: View {
    let schedule: [WidgetMealItem]
    var lineWidth: CGFloat = 6
    @ViewBuilder let center: Center
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        let count = schedule.count
        // Room between segments for their round ends, less as there are more of them.
        let gap = count > 1 ? min(0.03, 0.25 / Double(count)) : 0
        let style = WidgetSegmentStyle(theme: theme)
        ZStack {
            if schedule.isEmpty {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            }
            ForEach(Array(schedule.enumerated()), id: \.offset) { index, item in
                Circle()
                    .trim(from: Double(index) / Double(count) + gap, to: Double(index + 1) / Double(count) - gap)
                    .stroke(style.color(item.role), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable(item.role == .done)
            }
            center
        }
        .padding(lineWidth / 2)
    }
}

/// The same day as a bar of segments, for a bottom line.
struct WidgetMealBar: View {
    let schedule: [WidgetMealItem]
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        let style = WidgetSegmentStyle(theme: theme)
        HStack(spacing: 3) {
            ForEach(schedule) { item in
                Capsule()
                    .fill(style.color(item.role))
                    .widgetAccentable(item.role == .done)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Day Progress, small: the day's meals as a ring that fills as they go by, how many are behind,
/// and the one in front on a line of its own.
struct ProgressWidgetView<Action: View>: View {
    let entry: MealWidgetEntry
    let actions: WidgetActions<Action>
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content) {
            message
        } else if case .active(let day) = entry.content {
            if day.schedule.isEmpty {
                // Nothing today: the meal the plan has next says more than an empty ring.
                SmallMealWidgetView(entry: entry, actions: actions)
            } else {
                progress(day)
            }
        }
    }

    private func progress(_ day: WidgetDayContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetSegmentedRing(schedule: day.schedule, lineWidth: 7) {
                if day.isDayComplete {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(theme.success)
                        .widgetAccentable()
                } else {
                    Text(verbatim: "\(day.mealsBehind.formatted())/\(day.schedule.count.formatted())")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: 62, height: 62)
            Text(WidgetText.mealsSoFar(day.mealsBehind, of: day.schedule.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let primary = day.primary, let lead = day.lead {
                WidgetLeadChip(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                Text(primary.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel(day)))
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
