import SwiftUI
import WidgetKit
import Domain
import DesignSystem

/// The widget, for any family. `done` builds the Done button of the medium and large sizes: an
/// App Intent button in the widget extension, an inert look-alike in the app's previews.
public struct MealWidgetView<Done: View>: View {
    private let entry: MealWidgetEntry
    private let family: WidgetFamily
    private let done: (WidgetMealItem) -> Done

    public init(entry: MealWidgetEntry, family: WidgetFamily, @ViewBuilder done: @escaping (WidgetMealItem) -> Done) {
        self.entry = entry
        self.family = family
        self.done = done
    }

    public var body: some View {
        switch family {
        case .systemSmall:
            SmallMealWidgetView(entry: entry)
        case .systemMedium:
            MediumMealWidgetView(entry: entry, done: done)
        case .systemLarge, .systemExtraLarge:
            LargeMealWidgetView(entry: entry, done: done)
        case .accessoryRectangular:
            RectangularMealWidgetView(entry: entry)
        case .accessoryInline:
            InlineMealWidgetView(entry: entry)
        default:
            SmallMealWidgetView(entry: entry)
        }
    }
}

extension MealWidgetView where Done == WidgetDonePreview {
    /// For previews inside the app: the Done button is drawn but does nothing.
    public init(entry: MealWidgetEntry, family: WidgetFamily) {
        self.init(entry: entry, family: family) { _ in WidgetDonePreview() }
    }
}

// MARK: - Small

/// The most important widget: what is next, when, and nothing else.
struct SmallMealWidgetView: View {
    let entry: MealWidgetEntry

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content) {
            message
        } else if case .active(let day) = entry.content, let primary = day.primary, let lead = day.lead {
            if day.isDayComplete, case .laterDay = lead {
                completeDay(day, tomorrow: primary)
            } else {
                meal(day, primary: primary, lead: lead)
            }
        }
    }

    private func meal(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            WidgetLeadLabel(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
            WidgetTimeText(date: primary.date)
            Text(primary.title)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let footer = footer(day, primary: primary) {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(primary.accessibilityLabel)
    }

    private func footer(_ day: WidgetDayContent, primary: WidgetMealItem) -> String? {
        if let minutes = day.minutesUntilPrimary {
            return RelativeTimeText.until(minutes: minutes)
        }
        if entry.preferences.showCalories, let calories = primary.calories {
            return entry.preferences.energyUnit.format(kilocalories: calories)
        }
        if entry.preferences.showFollowingMeal, day.lead == .now, let following = day.following {
            return WidgetText.thenLine(following, isLaterDay: day.followingDay != nil)
        }
        return nil
    }

    private func completeDay(_ day: WidgetDayContent, tomorrow: WidgetMealItem) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(AppColors.success)
                .widgetAccentable()
                .accessibilityHidden(true)
            Text("widget.dayComplete", bundle: .module)
                .font(.headline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(WidgetText.thenLine(tomorrow, isLaterDay: true))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(tomorrow.title)
                .font(.footnote)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Medium

/// Now or next, prominently, and the meal after it.
struct MediumMealWidgetView<Done: View>: View {
    let entry: MealWidgetEntry
    let done: (WidgetMealItem) -> Done

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content) {
            message
        } else if case .active(let day) = entry.content, let primary = day.primary, let lead = day.lead {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                if day.isDayComplete, case .laterDay = lead {
                    completeColumn
                    Divider()
                    followingColumn(primary, label: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today), relative: nil)
                } else {
                    primaryColumn(day, primary: primary, lead: lead)
                    if entry.preferences.showFollowingMeal, let following = day.following {
                        Divider()
                        followingColumn(following, label: WidgetText.following(following, on: day.followingDay, today: day.today), relative: nil)
                    }
                }
            }
        }
    }

    private func primaryColumn(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            WidgetLeadLabel(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
            WidgetTimeText(date: primary.date)
            Text(primary.title)
                .font(.headline)
                .lineLimit(2)
            Spacer(minLength: 0)
            if lead == .now || lead == .next {
                done(primary)
            } else if let minutes = day.minutesUntilPrimary {
                Text(RelativeTimeText.until(minutes: minutes))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(primary.accessibilityLabel)
    }

    private func followingColumn(_ item: WidgetMealItem, label: String, relative: String?) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            WidgetLeadLabel(text: label, isEmphasized: false)
            WidgetTimeText(date: item.date, font: .title3.weight(.semibold))
            Text(item.title)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            if entry.preferences.showCalories, let calories = item.calories {
                Text(entry.preferences.energyUnit.format(kilocalories: calories))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private var completeColumn: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(AppColors.success)
                .widgetAccentable()
                .accessibilityHidden(true)
            Text("widget.dayComplete", bundle: .module)
                .font(.headline)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large

/// The whole day, with the meal that is on now or next marked, and the start of tomorrow.
struct LargeMealWidgetView<Done: View>: View {
    let entry: MealWidgetEntry
    let done: (WidgetMealItem) -> Done
    /// Rows that fit at the standard text size; larger text shows fewer.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rowLimit: Int {
        dynamicTypeSize >= .xxLarge ? 4 : 6
    }

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content) {
            message
        } else if case .active(let day) = entry.content {
            let rows = visibleRows(day)
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                header(day)
                if rows.items.isEmpty, let primary = day.primary, let lead = day.lead {
                    emptyToday(day, primary: primary, lead: lead)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(rows.items) { item in
                            row(item, isFocus: item.key == day.primary?.key && (day.lead == .now || day.lead == .next))
                        }
                    }
                    Spacer(minLength: 0)
                    footer(day, hidden: rows.hidden)
                }
            }
        }
    }

    private func header(_ day: WidgetDayContent) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day.today.middayDate(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: AppSpacing.xSmall)
            if day.remainingCount > 0 {
                Text(WidgetText.remaining(day.remainingCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if day.isDayComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                    .widgetAccentable()
                    .accessibilityLabel(Text("widget.dayComplete", bundle: .module))
            }
        }
        .padding(.horizontal, 6)
    }

    /// The rows that fit, centred on the meal that matters now, and how many were left out.
    private func visibleRows(_ day: WidgetDayContent) -> (items: [WidgetMealItem], hidden: Int) {
        let all = entry.preferences.showCompletedMeals ? day.schedule : day.schedule.filter { $0.role != .done && $0.role != .skipped }
        guard all.count > rowLimit else { return (all, 0) }
        let focusIndex = all.firstIndex { $0.role == .current || $0.role == .next } ?? all.firstIndex { $0.role == .upcoming } ?? all.count - 1
        let start = min(max(focusIndex - 1, 0), all.count - rowLimit)
        return (Array(all[start..<(start + rowLimit)]), all.count - rowLimit)
    }

    private func row(_ item: WidgetMealItem, isFocus: Bool) -> some View {
        let isMarked = item.role == .done || item.role == .skipped
        return HStack(spacing: AppSpacing.small) {
            Text(item.date, format: .dateTime.hour().minute())
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isMarked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
            MealStatusSymbol(MealStatusSymbol.Status(item.role), font: .subheadline)
                .widgetAccentable(item.role == .current || item.role == .next)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.typeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.title)
                    .font(.subheadline.weight(isFocus ? .semibold : .regular))
                    .foregroundStyle(isMarked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isFocus {
                done(item)
            } else if entry.preferences.showCalories, let calories = item.calories {
                Text(entry.preferences.energyUnit.format(kilocalories: calories))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .modifier(WidgetHighlight(isActive: isFocus))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder
    private func footer(_ day: WidgetDayContent, hidden: Int) -> some View {
        if hidden > 0 {
            Text(WidgetText.more(hidden))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        } else if let tomorrow = tomorrowsFirst(day) {
            Divider()
            Text(WidgetText.tomorrowMeal(tomorrow))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
    }

    private func tomorrowsFirst(_ day: WidgetDayContent) -> WidgetMealItem? {
        if case .laterDay = day.lead { return day.primary }
        return day.followingDay != nil ? day.following : nil
    }

    private func emptyToday(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            WidgetLeadLabel(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
            WidgetTimeText(date: primary.date)
            Text(primary.title)
                .font(.headline)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(primary.accessibilityLabel)
    }
}

// MARK: - Lock Screen

struct RectangularMealWidgetView: View {
    let entry: MealWidgetEntry

    var body: some View {
        if case .active(let day) = entry.content, let primary = day.primary, let lead = day.lead {
            VStack(alignment: .leading, spacing: 0) {
                Text(WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                    .lineLimit(1)
                Text(primary.date, format: .dateTime.hour().minute())
                    .font(.headline)
                    .lineLimit(1)
                Text(primary.title)
                    .font(.body)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(primary.accessibilityLabel)
        } else if let message = WidgetMessageView.view(for: entry.content, compact: true) {
            message
        }
    }
}

struct InlineMealWidgetView: View {
    let entry: MealWidgetEntry

    var body: some View {
        if case .active(let day) = entry.content, let primary = day.primary {
            Text(verbatim: WidgetText.inline(primary))
        } else if let message = WidgetMessageView.view(for: entry.content, compact: true) {
            Text(message.title)
        }
    }
}
