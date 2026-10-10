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

    /// "until 14:30": when the meal on now gives way to the next.
    static func until(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        return String(localized: "widget.live.until", defaultValue: "until \(time)", bundle: .module)
    }

    /// "2 hr, 10 min": the time left, worked out once, for previews whose clock does not run.
    static func timeLeft(until date: Date, from reference: Date) -> String {
        let seconds = max(date.timeIntervalSince(reference), 60)
        return Duration.seconds(Int((seconds / 60).rounded(.up)) * 60)
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    /// "+45 min": how far a late start moved the meal. The figure and unit come from the system,
    /// so there is nothing to translate.
    static func shift(_ minutes: Int) -> String {
        "+" + Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    /// "Moved 45 minutes later", for VoiceOver.
    static func shiftAccessibility(_ minutes: Int) -> String {
        let amount = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2))
        return String(localized: "widget.shift.accessibility", defaultValue: "Moved \(amount) later", bundle: .module)
    }

    /// "Keto · Day 3 of 14", or the plan's name alone before it starts.
    static func planDay(_ day: WidgetDayContent) -> String {
        guard let index = day.dayIndex else { return day.planName }
        let number = index + 1
        let count = day.dayCount
        let name = day.planName
        return String(localized: "widget.header.planDay", defaultValue: "\(name) · Day \(number) of \(count)", bundle: .module)
    }

    /// "2 earlier · 1 eaten": the meals before the one in front, folded into one line.
    static func earlier(_ count: Int, eaten: Int) -> String {
        String(localized: "widget.today.earlier", defaultValue: "\(count) earlier · \(eaten) eaten", bundle: .module)
    }

    /// "2 of 4 · meals so far", under the Day Progress ring.
    static func mealsSoFar(_ done: Int, of total: Int) -> String {
        String(localized: "widget.progress.soFar", defaultValue: "\(done) of \(total) · meals so far", bundle: .module)
    }

    /// "820 of 1,640 kcal eaten", with "≈" in front when any figure is the assistant's estimate.
    /// Never "left": what was planned is not a budget to use up.
    static func energy(_ energy: WidgetEnergy, unit: EnergyUnit) -> String {
        let planned = unit.format(kilocalories: energy.planned)
        let eatenValue = unit == .kilocalories ? Double(energy.eaten) : Measurement(value: Double(energy.eaten), unit: UnitEnergy.kilocalories).converted(to: .kilojoules).value
        let eaten = eatenValue.formatted(.number.precision(.fractionLength(0)))
        let text = String(localized: "widget.energy.progress", defaultValue: "\(eaten) of \(planned) eaten", bundle: .module)
        return energy.isEstimated ? "≈\u{2009}" + text : text
    }

    static func appName() -> String {
        AppBrand.displayName
    }
}

// MARK: - Chips and tiles

/// "Now · Lunch": the capsule above a meal, in the accent. Part of the accented group in tinted
/// mode, so it takes the person's tint.
struct WidgetLeadChip: View {
    let text: String
    var isEmphasized = true
    @Environment(\.widgetTheme) private var theme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEmphasized ? AnyShapeStyle(theme.ink) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            // Room for languages that say "Tomorrow · Breakfast" in more letters.
            .minimumScaleFactor(0.8)
            .padding(.horizontal, isEmphasized ? 8 : 0)
            .padding(.vertical, isEmphasized ? 3 : 0)
            .background {
                if isEmphasized {
                    Capsule().fill(renderingMode == .fullColor ? AnyShapeStyle(theme.wash) : AnyShapeStyle(Color.primary.opacity(0.14)))
                }
            }
            .widgetAccentable(isEmphasized)
    }
}

/// "+45 min": a meal moved later today because the day started late.
struct WidgetShiftChip: View {
    let minutes: Int

    var body: some View {
        Text(verbatim: WidgetText.shift(minutes))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .accessibilityLabel(Text(verbatim: WidgetText.shiftAccessibility(minutes)))
    }
}

/// The meal's sitting as a symbol on a tile in the accent: breakfast, lunch, a snack, dinner.
struct WidgetMealTile: View {
    let type: MealType
    var size: CGFloat = 28
    @Environment(\.widgetTheme) private var theme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Image(systemName: type.symbolName)
            .font(.system(size: size * 0.48, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.ink)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(renderingMode == .fullColor ? AnyShapeStyle(theme.wash) : AnyShapeStyle(Color.primary.opacity(0.14)))
            )
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

/// A meal's time in the person's 12- or 24-hour format, with "AM" or "PM" drawn small beside the
/// figures so the figures carry the weight.
struct WidgetTimeText: View {
    let date: Date
    var font: Font = .title2.weight(.bold)
    var periodFont: Font = .caption.weight(.semibold)

    var body: some View {
        let parts = Self.parts(of: date)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if let period = parts.period, parts.periodFirst {
                Text(verbatim: period).font(periodFont)
            }
            Text(verbatim: parts.figures).font(font)
            if let period = parts.period, !parts.periodFirst {
                Text(verbatim: period).font(periodFont)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.hour().minute()))
    }

    /// The figures, and the day period ("PM") apart from them where the locale writes one.
    static func parts(of date: Date) -> (figures: String, period: String?, periodFirst: Bool) {
        let full = date.formatted(.dateTime.hour().minute())
        let figures = date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        guard full != figures else { return (figures: full, period: nil, periodFirst: false) }
        if full.hasPrefix(figures) {
            let period = String(full.dropFirst(figures.count)).trimmingCharacters(in: .whitespaces)
            if !period.isEmpty { return (figures: figures, period: period, periodFirst: false) }
        } else if full.hasSuffix(figures) {
            let period = String(full.dropLast(figures.count)).trimmingCharacters(in: .whitespaces)
            if !period.isEmpty { return (figures: figures, period: period, periodFirst: true) }
        }
        return (figures: full, period: nil, periodFirst: false)
    }
}

/// A time that keeps the width of the widest time of day, so the titles beside a column of them
/// line up.
struct WidgetTimeColumn: View {
    let date: Date
    var font: Font = .subheadline.weight(.semibold)
    var isMuted = false

    var body: some View {
        ZStack(alignment: .leading) {
            WidgetTimeText(date: Self.widest(near: date), font: font, periodFont: .caption2.weight(.semibold))
                .hidden()
            WidgetTimeText(date: date, font: font, periodFont: .caption2.weight(.semibold))
                .foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }

    /// 22:00 — "10:00 PM" or "22:00": as wide as a time gets in either format.
    static func widest(near date: Date) -> Date {
        Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: date) ?? date
    }
}

/// "Recipe": opens cook mode for the meal (`AppLink.cook`).
struct WidgetCookChip: View {
    let item: WidgetMealItem

    var body: some View {
        WidgetLink(url: AppLink.cook(item.key).url) {
            ViewThatFits(in: .horizontal) {
                label(showsText: true)
                label(showsText: false)
            }
        }
        .accessibilityLabel(Text("widget.cook", bundle: .module))
    }

    private func label(showsText: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "frying.pan")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            if showsText {
                Text("widget.cook.short", bundle: .module)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, showsText ? 9 : 7)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .widgetAccentable()
    }
}

/// A part of a medium or large widget that opens its own place in the app, where the widget opens
/// links; elsewhere (the app's previews) the same content, inert.
struct WidgetLink<Content: View>: View {
    let url: URL
    @ViewBuilder let content: Content
    @Environment(\.widgetRendering) private var rendering

    var body: some View {
        if rendering.opensLinks {
            Link(destination: url) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Live line

/// The bottom line of the meal in front, which keeps itself current between timeline entries:
/// while the meal is on, a bar that runs out when it gives way and "until 14:30"; while it is
/// ahead, the time left to it, ticking. Previews whose clock does not run work both out once.
struct WidgetLiveLine: View {
    let day: WidgetDayContent
    let primary: WidgetMealItem
    let entry: MealWidgetEntry
    @Environment(\.widgetRendering) private var rendering
    @Environment(\.widgetTheme) private var theme

    private var isLive: Bool { rendering.usesLiveTime && !entry.isFrozen }

    var body: some View {
        if day.lead == .now, let ends = day.primaryEnds {
            VStack(alignment: .leading, spacing: 4) {
                bar(from: primary.date, to: ends)
                Text(WidgetText.until(ends))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.ink)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Group {
                    if isLive {
                        Text(primary.date, style: .relative)
                    } else {
                        Text(verbatim: WidgetText.timeLeft(until: primary.date, from: entry.reference))
                    }
                }
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder
    private func bar(from start: Date, to end: Date) -> some View {
        if isLive, start < end {
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(theme.tint)
            .widgetAccentable()
        } else {
            let total = max(end.timeIntervalSince(start), 1)
            let left = min(max(end.timeIntervalSince(entry.reference), 0), total)
            ProgressView(value: left / total)
                .progressViewStyle(.linear)
                .tint(theme.tint)
                .widgetAccentable()
        }
    }
}

// MARK: - Actions

/// Something a widget lets the person do without opening the app. The widget extension turns each
/// into an App Intent button; the app's previews draw the same label, inert.
public enum WidgetAction: Hashable, Sendable {
    /// Mark the meal eaten (`MarkMealDoneIntent`).
    case markEaten(WidgetMealItem)
    /// Take back what was marked (`UnmarkMealIntent`), from a row of Today's Meals.
    case unmark(WidgetMealItem)
    /// The day starts now: "I'm up" (`DayStart.wokeUp(at:source: .widget)`).
    case startDay
}

/// What a widget button looks like. The widget extension wraps it in `Button(intent:)` with the
/// plain style, so every look is drawn here, the same in the widget and in the app.
public struct WidgetActionLabel: View {
    enum Style: Hashable {
        /// The round "Eaten" check beside the meal in front.
        case check
        /// The status mark at the start of a row of Today's Meals.
        case status(MealRole)
        /// "I'm up".
        case capsule
    }

    let action: WidgetAction
    let style: Style
    @Environment(\.widgetTheme) private var theme
    @Environment(\.widgetRenderingMode) private var renderingMode

    public var body: some View {
        switch style {
        case .check:
            check
        case .status(let role):
            status(role)
        case .capsule:
            capsule
        }
    }

    private var check: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(theme.ink)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 30, height: 30)
            .background(Circle().fill(renderingMode == .fullColor ? AnyShapeStyle(theme.wash) : AnyShapeStyle(Color.primary.opacity(0.16))))
            .overlay(Circle().strokeBorder(theme.ink.opacity(0.35), lineWidth: 1))
            .contentShape(Circle())
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("widget.done", bundle: .module))
    }

    private func status(_ role: MealRole) -> some View {
        WidgetStatusSymbol(role: role)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(role == .done || role == .skipped ? Text("widget.undo", bundle: .module) : Text("widget.done", bundle: .module))
    }

    private var capsule: some View {
        HStack(spacing: 4) {
            Image(systemName: "sunrise.fill")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text("widget.startDay", bundle: .module)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(renderingMode == .fullColor ? AnyShapeStyle(theme.wash) : AnyShapeStyle(Color.primary.opacity(0.16))))
        .overlay(Capsule().strokeBorder(theme.ink.opacity(0.35), lineWidth: 1))
        .contentShape(Capsule())
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("widget.startDay.accessibility", bundle: .module))
    }
}

/// How the app's previews show a widget button: its look, with nothing to tap.
public struct WidgetActionPreview: View {
    let label: WidgetActionLabel

    public var body: some View {
        label.accessibilityHidden(true)
    }
}

/// Builds the button for an action in the style a place in the widget calls for. On the main actor,
/// like the views that call it and the label it builds.
@MainActor
struct WidgetActions<Action: View> {
    let make: (WidgetAction, WidgetActionLabel) -> Action

    func callAsFunction(_ action: WidgetAction, _ style: WidgetActionLabel.Style) -> Action {
        make(action, WidgetActionLabel(action: action, style: style))
    }
}

/// A meal's status in a row: eaten, skipped, on now, next, ahead, or missed — drawn dashed, since
/// it went by without being marked. Never colour alone: each has its own shape.
struct WidgetStatusSymbol: View {
    let role: MealRole
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        Image(systemName: symbolName)
            .font(.subheadline.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            .widgetAccentable(role == .current || role == .next)
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch role {
        case .done: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .current: "circle.inset.filled"
        case .next: "circle.circle"
        case .upcoming: "circle"
        case .past: "circle.dashed"
        }
    }

    private var color: AnyShapeStyle {
        switch role {
        case .done: AnyShapeStyle(theme.success)
        case .current, .next: AnyShapeStyle(theme.tint)
        case .skipped, .past: AnyShapeStyle(.secondary)
        case .upcoming: AnyShapeStyle(.tertiary)
        }
    }
}

/// The soft background behind the meal that is on now or next. In tinted and clear modes a plain
/// translucent fill replaces the brand colour.
struct WidgetHighlight: ViewModifier {
    let isActive: Bool
    var cornerRadius: CGFloat = 10
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetTheme) private var theme

    func body(content: Content) -> some View {
        content.background {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(renderingMode == .fullColor ? AnyShapeStyle(theme.wash) : AnyShapeStyle(Color.primary.opacity(0.12)))
            }
        }
    }
}

// MARK: - Messages

/// No plan, an unreadable file, an ended plan, or nothing scheduled: a symbol, a line, and what to
/// do next — as buttons that open the right place where there is room for them.
struct WidgetMessageView: View {
    struct Step: Hashable {
        let title: String
        let link: AppLink
        let symbol: String
    }

    let symbol: String
    let title: String
    let message: String?
    var steps: [Step] = []
    var compact = false
    /// Medium and large: each step opens its own place. Small: the whole widget opens the first.
    var linksSteps = false
    @Environment(\.widgetTheme) private var theme

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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                if !steps.isEmpty {
                    HStack(spacing: AppSpacing.xSmall) {
                        ForEach(linksSteps ? steps : Array(steps.prefix(1)), id: \.self) { step in
                            stepChip(step)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func stepChip(_ step: Step) -> some View {
        let chip = HStack(spacing: 4) {
            Image(systemName: step.symbol)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(step.title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(theme.wash))
        .widgetAccentable()
        if linksSteps {
            WidgetLink(url: step.link.url) { chip }
        } else {
            chip
        }
    }

    static func view(for content: WidgetContent, compact: Bool = false, linksSteps: Bool = false) -> WidgetMessageView? {
        let app = WidgetText.appName()
        switch content {
        case .noPlan:
            return WidgetMessageView(
                symbol: "camera.viewfinder",
                title: String(localized: "widget.noPlan.title", bundle: .module),
                message: compact ? nil : String(localized: "widget.noPlan.message", defaultValue: "Add a photo, PDF or text and \(app) builds your plan.", bundle: .module),
                steps: [Step(title: String(localized: "widget.noPlan.action", bundle: .module), link: .importPlan, symbol: "plus")],
                compact: compact,
                linksSteps: linksSteps
            )
        case .needsRefresh:
            return WidgetMessageView(
                symbol: "arrow.clockwise",
                title: String(localized: "widget.refresh.title", bundle: .module),
                message: String(localized: "widget.refresh.message", defaultValue: "Open \(app) to update.", bundle: .module),
                compact: compact,
                linksSteps: linksSteps
            )
        case .planEnded(let name, let lastDay):
            let date = lastDay.middayDate().formatted(.dateTime.month(.abbreviated).day())
            return WidgetMessageView(
                symbol: "flag.checkered",
                title: String(localized: "widget.ended.title", bundle: .module),
                message: String(localized: "widget.ended.message", defaultValue: "\(name) ended \(date).", bundle: .module),
                steps: [
                    Step(title: String(localized: "widget.ended.startAgain", bundle: .module), link: .plan, symbol: "arrow.counterclockwise"),
                    Step(title: String(localized: "widget.ended.newPlan", bundle: .module), link: .importPlan, symbol: "sparkles"),
                ],
                compact: compact,
                linksSteps: linksSteps
            )
        case .active(let day) where day.primary == nil:
            return WidgetMessageView(
                symbol: "fork.knife",
                title: String(localized: "widget.noMeals.title", bundle: .module),
                message: day.planName,
                compact: compact,
                linksSteps: linksSteps
            )
        case .active:
            return nil
        }
    }
}

extension WidgetMealItem {
    /// What VoiceOver reads for this meal, with its energy and a late start's move when there are.
    func spokenLabel(energyUnit: EnergyUnit?) -> String {
        var parts = [MealAccessibility.label(typeLabel: typeLabel, date: date, title: title, role: role == .upcoming ? nil : role)]
        if let energyUnit, let energy = energyUnit.format(nutrition) {
            parts.append(energy)
        }
        if isMoved {
            parts.append(WidgetText.shiftAccessibility(shiftMinutes))
        }
        return parts.joined(separator: ", ")
    }

    /// What VoiceOver reads for this meal.
    var accessibilityLabel: String { spokenLabel(energyUnit: nil) }
}
