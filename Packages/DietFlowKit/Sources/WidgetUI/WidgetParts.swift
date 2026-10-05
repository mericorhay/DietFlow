import SwiftUI
import WidgetKit
import Domain
import DesignSystem

/// The words every widget size shares.
enum WidgetText {
    static func lead(_ lead: WidgetDayContent.Lead, typeLabel: String, today: CalendarDay) -> String {
        switch lead {
        case .now:
            return String(localized: "widget.lead.now", defaultValue: "Now · \(typeLabel)", bundle: .module)
        case .next:
            return String(localized: "widget.lead.next", defaultValue: "Next · \(typeLabel)", bundle: .module)
        case .laterDay(let day):
            if day == today.adding(days: 1) {
                return String(localized: "widget.lead.tomorrow", defaultValue: "Tomorrow · \(typeLabel)", bundle: .module)
            }
            let weekday = day.middayDate().formatted(.dateTime.weekday(.wide))
            return String(localized: "widget.lead.laterDay", defaultValue: "\(weekday) · \(typeLabel)", bundle: .module)
        case .planStarts(let day):
            if day == today.adding(days: 1) {
                return String(localized: "widget.lead.startsTomorrow", bundle: .module)
            }
            let date = day.middayDate().formatted(.dateTime.month(.abbreviated).day())
            return String(localized: "widget.lead.startsOn", defaultValue: "Starts \(date)", bundle: .module)
        }
    }

    /// "Then · Snack", "Tomorrow · Breakfast", "Friday · Breakfast".
    static func following(_ item: WidgetMealItem, on day: CalendarDay?, today: CalendarDay) -> String {
        guard let day else {
            return String(localized: "widget.following.then", defaultValue: "Then · \(item.typeLabel)", bundle: .module)
        }
        if day == today.adding(days: 1) {
            return String(localized: "widget.lead.tomorrow", defaultValue: "Tomorrow · \(item.typeLabel)", bundle: .module)
        }
        let weekday = day.middayDate().formatted(.dateTime.weekday(.wide))
        return String(localized: "widget.lead.laterDay", defaultValue: "\(weekday) · \(item.typeLabel)", bundle: .module)
    }

    /// "Then 16:30 · Snack", for the bottom line of the small widget.
    static func thenLine(_ item: WidgetMealItem, isLaterDay: Bool) -> String {
        let time = item.date.formatted(.dateTime.hour().minute())
        if isLaterDay {
            return String(localized: "widget.thenTomorrow", defaultValue: "Tomorrow \(time) · \(item.typeLabel)", bundle: .module)
        }
        return String(localized: "widget.then", defaultValue: "Then \(time) · \(item.typeLabel)", bundle: .module)
    }

    /// "Tomorrow 10:00 · Feta, cucumber and walnut salad".
    static func tomorrowMeal(_ item: WidgetMealItem) -> String {
        let time = item.date.formatted(.dateTime.hour().minute())
        return String(localized: "widget.tomorrowMeal", defaultValue: "Tomorrow \(time) · \(item.title)", bundle: .module)
    }

    /// "14:00 · Grilled Chicken Caesar Salad", for the one-line Lock Screen widget. Not translated:
    /// a time and the person's own words.
    static func inline(_ item: WidgetMealItem) -> String {
        "\(item.date.formatted(.dateTime.hour().minute())) · \(item.title)"
    }

    static func remaining(_ count: Int) -> String {
        String(localized: "widget.remaining", defaultValue: "\(count) remaining", bundle: .module)
    }

    static func more(_ count: Int) -> String {
        String(localized: "widget.more", defaultValue: "+\(count) more", bundle: .module)
    }

    static func appName() -> String {
        AppBrand.displayName
    }
}

/// "Next · Lunch": the accent-coloured line above a meal. Part of the accented group in tinted
/// mode, so it takes the person's tint.
struct WidgetLeadLabel: View {
    let text: String
    var isEmphasized = true

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isEmphasized ? AnyShapeStyle(AppColors.brandAccent) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .widgetAccentable(isEmphasized)
    }
}

/// A meal's time in the person's 12- or 24-hour format.
struct WidgetTimeText: View {
    let date: Date
    var font: Font = .title.weight(.bold)

    var body: some View {
        Text(date, format: .dateTime.hour().minute())
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// The label of the medium and large widgets' Done button.
public struct WidgetDoneLabel: View {
    public init() {}

    public var body: some View {
        Label {
            Text("widget.done", bundle: .module)
        } icon: {
            Image(systemName: "checkmark")
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
    }
}

/// How the Done button looks in the app's own previews, where it does nothing.
public struct WidgetDonePreview: View {
    public init() {}

    public var body: some View {
        Button {} label: { WidgetDoneLabel() }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(AppColors.brandAccent)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The soft background behind the meal that is on now or next. In tinted and clear modes a plain
/// translucent fill replaces the brand colour.
struct WidgetHighlight: ViewModifier {
    let isActive: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.background {
            if isActive {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(renderingMode == .fullColor ? AnyShapeStyle(AppColors.brandWash) : AnyShapeStyle(Color.primary.opacity(0.12)))
            }
        }
    }
}

/// No plan, an unreadable file, an ended plan, or nothing scheduled: a symbol, one line and, when
/// there is room, what to do about it.
struct WidgetMessageView: View {
    let symbol: String
    let title: String
    let message: String?
    var compact = false

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline).lineLimit(1)
                if let message {
                    Text(message).font(.caption).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }

    static func view(for content: WidgetContent, compact: Bool = false) -> WidgetMessageView? {
        let app = WidgetText.appName()
        switch content {
        case .noPlan:
            return WidgetMessageView(
                symbol: "calendar.badge.plus",
                title: String(localized: "widget.noPlan.title", bundle: .module),
                message: String(localized: "widget.noPlan.message", defaultValue: "Open \(app) to add one.", bundle: .module),
                compact: compact
            )
        case .needsRefresh:
            return WidgetMessageView(
                symbol: "arrow.clockwise",
                title: String(localized: "widget.refresh.title", bundle: .module),
                message: String(localized: "widget.refresh.message", defaultValue: "Open \(app) to update.", bundle: .module),
                compact: compact
            )
        case .planEnded(let name, let lastDay):
            let date = lastDay.middayDate().formatted(.dateTime.month(.abbreviated).day())
            return WidgetMessageView(
                symbol: "flag.checkered",
                title: String(localized: "widget.ended.title", bundle: .module),
                message: String(localized: "widget.ended.message", defaultValue: "\(name) ended \(date).", bundle: .module),
                compact: compact
            )
        case .active(let day) where day.primary == nil:
            return WidgetMessageView(
                symbol: "fork.knife",
                title: String(localized: "widget.noMeals.title", bundle: .module),
                message: day.planName,
                compact: compact
            )
        case .active:
            return nil
        }
    }
}

extension WidgetMealItem {
    /// What VoiceOver reads for this meal.
    var accessibilityLabel: String {
        MealAccessibility.label(typeLabel: typeLabel, date: date, title: title, role: role == .upcoming ? nil : role)
    }
}
