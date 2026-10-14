import SwiftUI
import WidgetKit
import Domain
import DesignSystem

/// The widget, for any family. `action` builds each button the widget offers — "Eaten", taking a
/// mark back, "I'm up" — around the label it is handed: an App Intent button in the widget
/// extension, the label alone in the app's previews.
public struct MealWidgetView<Action: View>: View {
    private let entry: MealWidgetEntry
    private let kind: MealWidgetKind
    private let family: WidgetFamily
    private let actions: WidgetActions<Action>

    public init(entry: MealWidgetEntry, kind: MealWidgetKind = .nextMeal, family: WidgetFamily, @ViewBuilder action: @escaping (WidgetAction, WidgetActionLabel) -> Action) {
        self.entry = entry
        self.kind = kind
        self.family = family
        self.actions = WidgetActions(make: action)
    }

    public var body: some View {
        sized.modifier(WidgetThemed(theme: WidgetTheme(entry.preferences), family: family))
    }

    @ViewBuilder
    private var sized: some View {
        switch kind {
        case .progress:
            if family == .accessoryCircular {
                CircularProgressWidgetView(entry: entry)
            } else {
                ProgressWidgetView(entry: entry, actions: actions)
            }
        case .today:
            if family == .systemMedium {
                TodayMediumWidgetView(entry: entry, actions: actions)
            } else {
                TodayLargeWidgetView(entry: entry, actions: actions)
            }
        case .nextMeal:
            switch family {
            case .systemMedium:
                MediumMealWidgetView(entry: entry, actions: actions)
            case .systemLarge, .systemExtraLarge:
                LargeMealWidgetView(entry: entry, actions: actions)
            case .accessoryRectangular:
                RectangularMealWidgetView(entry: entry)
            case .accessoryInline:
                InlineMealWidgetView(entry: entry)
            case .accessoryCircular:
                CircularMealWidgetView(entry: entry)
            default:
                SmallMealWidgetView(entry: entry, actions: actions)
            }
        }
    }
}

extension MealWidgetView where Action == WidgetActionPreview {
    /// For previews inside the app: the buttons are drawn but do nothing.
    public init(entry: MealWidgetEntry, kind: MealWidgetKind = .nextMeal, family: WidgetFamily) {
        self.init(entry: entry, kind: kind, family: family) { _, label in
            WidgetActionPreview(label: label)
        }
    }
}

extension MealWidgetEntry {
    /// The meal in front can be ticked off from the widget: the person wants the button, and the
    /// meal is today's.
    func canMarkEaten(_ lead: WidgetDayContent.Lead) -> Bool {
        preferences.showDoneButton && (lead == .now || lead == .next)
    }

    /// The meal's energy as the person wants it shown, "≈" included for an estimate.
    func energyText(_ item: WidgetMealItem) -> String? {
        guard preferences.showCalories else { return nil }
        return preferences.energyUnit.format(item.nutrition)
    }
}

/// The meal's time, with the "+45 min" of a late start beside it and, when asked for, its energy.
struct WidgetMealTimeRow: View {
    let item: WidgetMealItem
    var font: Font = .headline.weight(.bold)
    var energy: String?

    var body: some View {
        // The time is never cut short: where the row is narrow, the energy goes first, then the chip.
        ViewThatFits(in: .horizontal) {
            row(showsShift: true, showsEnergy: true)
            row(showsShift: true, showsEnergy: false)
            row(showsShift: false, showsEnergy: false)
        }
    }

    private func row(showsShift: Bool, showsEnergy: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            WidgetTimeText(date: item.date, font: font)
                .fixedSize()
            if showsShift, item.isMoved {
                WidgetShiftChip(minutes: item.shiftMinutes)
                    .fixedSize()
            }
            if showsEnergy, let energy {
                Text(verbatim: energy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Small

/// The most important widget: what is next, when, and nothing else.
struct SmallMealWidgetView<Action: View>: View {
    let entry: MealWidgetEntry
    let actions: WidgetActions<Action>
    @Environment(\.widgetTheme) private var theme
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content) {
            message
        } else if case .active(let day) = entry.content, let primary = day.primary, let lead = day.lead {
            if day.isDayComplete, case .laterDay = lead {
                WidgetDayCompleteView(day: day, tomorrow: primary)
            } else if !showsBackground {
                standBy(day, primary: primary, lead: lead)
            } else {
                meal(day, primary: primary, lead: lead)
            }
        }
    }

    private func meal(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                WidgetMealTile(type: primary.type, size: 24)
                WidgetLeadChip(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                Spacer(minLength: 0)
            }
            Text(primary.title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(primary.key)
                .transition(.push(from: .bottom))
                .accessibilityLabel(Text(verbatim: primary.spokenLabel(energyUnit: entry.preferences.showCalories ? entry.preferences.energyUnit : nil)))
            Spacer(minLength: 0)
            bottom(day, primary: primary, lead: lead)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .invalidatableContent()
    }

    @ViewBuilder
    private func bottom(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> some View {
        let canMark = entry.canMarkEaten(lead)
        if day.offersStartDay {
            VStack(alignment: .leading, spacing: 6) {
                WidgetMealTimeRow(item: primary, font: .subheadline.weight(.bold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        actions(.startDay, .capsule)
                        Spacer(minLength: 0)
                        if canMark {
                            actions(.markEaten(primary), .check)
                        }
                    }
                    actions(.startDay, .capsule)
                }
            }
        } else {
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    WidgetMealTimeRow(item: primary, font: .headline.weight(.bold))
                    WidgetLiveLine(day: day, primary: primary, entry: entry)
                }
                Spacer(minLength: 0)
                if canMark {
                    actions(.markEaten(primary), .check)
                }
            }
        }
    }

    /// StandBy and other places without the widget's background: one meal, centred and large,
    /// readable from across the room.
    private func standBy(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> some View {
        VStack(spacing: 4) {
            WidgetMealTile(type: primary.type, size: 30)
            Text(WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
            WidgetTimeText(date: primary.date, font: .system(.largeTitle, design: .rounded).weight(.bold))
            Text(primary.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: primary.accessibilityLabel))
    }
}

/// Every meal of the day is marked: the full ring, and what comes first tomorrow.
struct WidgetDayCompleteView: View {
    let day: WidgetDayContent
    let tomorrow: WidgetMealItem
    /// Medium draws tomorrow's first meal in its own column beside this, so it is not said twice.
    var showsTomorrow = true
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            WidgetSegmentedRing(schedule: day.schedule, lineWidth: 5) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(theme.success)
                    .widgetAccentable()
            }
            .frame(width: 40, height: 40)
            Text("widget.dayComplete", bundle: .module)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if showsTomorrow {
                Text(WidgetText.thenLine(tomorrow, isLaterDay: day.followingDay != nil || isTomorrow))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(tomorrow.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var isTomorrow: Bool {
        if case .laterDay = day.lead { return true }
        return false
    }
}

// MARK: - Medium

/// The meal in front given most of the width, and what comes after it beside it.
struct MediumMealWidgetView<Action: View>: View {
    let entry: MealWidgetEntry
    let actions: WidgetActions<Action>
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content, linksSteps: true) {
            message
        } else if case .active(let day) = entry.content, let primary = day.primary, let lead = day.lead {
            GeometryReader { proxy in
                let showsSide = day.isDayComplete || (entry.preferences.showFollowingMeal && day.following != nil)
                let gap: CGFloat = 12
                let main = showsSide ? (proxy.size.width - gap * 2 - 1) * 0.62 : proxy.size.width
                HStack(alignment: .top, spacing: gap) {
                    if day.isDayComplete, case .laterDay = lead {
                        WidgetDayCompleteView(day: day, tomorrow: primary, showsTomorrow: false)
                            .frame(width: main)
                        Divider()
                        sideColumn(primary, label: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                    } else {
                        primaryColumn(day, primary: primary, lead: lead)
                            .frame(width: main)
                        if showsSide, let following = day.following {
                            Divider()
                            sideColumn(following, label: WidgetText.following(following, on: day.followingDay, today: day.today))
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    private func primaryColumn(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                WidgetLink(url: AppLink.meal(primary.key).url) {
                    HStack(spacing: 6) {
                        WidgetMealTile(type: primary.type, size: 26)
                        WidgetLeadChip(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                    }
                }
                Spacer(minLength: 0)
                if entry.canMarkEaten(lead) {
                    actions(.markEaten(primary), .check)
                }
            }
            WidgetLink(url: AppLink.meal(primary.key).url) {
                Text(primary.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(primary.key)
            .transition(.push(from: .bottom))
            .accessibilityLabel(Text(verbatim: primary.spokenLabel(energyUnit: entry.preferences.showCalories ? entry.preferences.energyUnit : nil)))
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    WidgetMealTimeRow(item: primary, font: .headline.weight(.bold), energy: entry.energyText(primary))
                    WidgetLiveLine(day: day, primary: primary, entry: entry)
                }
                Spacer(minLength: 0)
                if day.offersStartDay {
                    actions(.startDay, .capsule)
                }
            }
            .layoutPriority(1)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .invalidatableContent()
    }

    /// "Then · Snack" in secondary: what comes after, quieter than the meal in front.
    private func sideColumn(_ item: WidgetMealItem, label: String) -> some View {
        WidgetLink(url: AppLink.meal(item.key).url) {
            VStack(alignment: .leading, spacing: 3) {
                WidgetLeadChip(text: label, isEmphasized: false)
                WidgetMealTimeRow(item: item, font: .subheadline.weight(.bold))
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if let energy = entry.energyText(item) {
                    Text(verbatim: energy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.accessibilityLabel))
    }
}

// MARK: - Large next meal

/// A full-size meal card, distinct from the day's agenda. The time and meal stay together;
/// actions have their own row so they cannot squeeze the title or countdown.
struct LargeMealWidgetView<Action: View>: View {
    let entry: MealWidgetEntry
    let actions: WidgetActions<Action>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content, linksSteps: true) {
            message
        } else if case .active(let day) = entry.content, let primary = day.primary, let lead = day.lead {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    WidgetMealTile(type: primary.type, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetLeadChip(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                        Text(primary.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                WidgetLink(url: AppLink.meal(primary.key).url) {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetMealTimeRow(item: primary, font: .system(.largeTitle, design: .rounded).weight(.bold), energy: entry.energyText(primary))
                        Text(primary.title)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                WidgetLiveLine(day: day, primary: primary, entry: entry)
                HStack(spacing: 8) {
                    if entry.canMarkEaten(lead) {
                        actions(.markEaten(primary), .labeledCheck)
                    }
                    if day.offersStartDay {
                        actions(.startDay, .capsule)
                    } else if lead == .now || lead == .next {
                        WidgetCookChip(item: primary)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize, entry.preferences.showFollowingMeal, let following = day.following {
                    Divider()
                    WidgetLink(url: AppLink.meal(following.key).url) {
                        HStack(spacing: 10) {
                            WidgetMealTile(type: following.type, size: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(WidgetText.following(following, on: day.followingDay, today: day.today))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(following.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            WidgetTimeText(date: following.date, font: .subheadline.weight(.bold))
                                .fixedSize()
                        }
                    }
                }
                WidgetDayFooter(day: day, entry: entry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .invalidatableContent()
        }
    }
}

// MARK: - Today's Meals

/// How Today's Meals splits the day around the meal in front.
struct WidgetDayLayout {
    /// The meal on now or next today, drawn as the focus card.
    let focus: WidgetMealItem?
    /// Rows before the focus, drawn one by one.
    let earlier: [WidgetMealItem]
    /// Meals before the focus folded into "2 earlier · 1 eaten", when there is no room for them.
    let folded: [WidgetMealItem]
    /// Rows after the focus.
    let later: [WidgetMealItem]
    /// Later meals left out for room.
    let hidden: Int

    init(day: WidgetDayContent, rowLimit: Int, showsCompleted: Bool) {
        let isToday = day.lead == .now || day.lead == .next
        let primaryKey = day.primary?.key
        let focusIndex: Int? = isToday ? day.schedule.firstIndex(where: { $0.key == primaryKey }) : nil
        focus = focusIndex.map { day.schedule[$0] }
        let visible: (WidgetMealItem) -> Bool = { showsCompleted || ($0.role != .done && $0.role != .skipped) }
        let before: [WidgetMealItem]
        let after: [WidgetMealItem]
        if let focusIndex {
            before = Array(day.schedule[..<focusIndex])
            after = Array(day.schedule[(focusIndex + 1)...])
        } else {
            before = []
            after = day.schedule
        }
        let shownBefore = before.filter(visible)
        let shownAfter = after.filter(visible)
        if shownBefore.count + shownAfter.count <= rowLimit {
            earlier = shownBefore
            folded = []
            later = shownAfter
            hidden = 0
        } else {
            earlier = []
            folded = before
            // One row goes to the folded line.
            let room = max(rowLimit - (before.isEmpty ? 0 : 1), 1)
            later = Array(shownAfter.prefix(room))
            hidden = shownAfter.count - later.count
        }
    }
}

/// Today's Meals, large: the day at a glance — the meal in front as a card, the rest as rows that
/// share the room left, and a bottom line that is always there.
struct TodayLargeWidgetView<Action: View>: View {
    let entry: MealWidgetEntry
    let actions: WidgetActions<Action>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.widgetTheme) private var theme

    /// The rows that fit beside the header, the card and the bottom line at the standard text size;
    /// larger text shows fewer.
    private func rowLimit(hasFocus: Bool) -> Int {
        if dynamicTypeSize >= .xxLarge { return hasFocus ? 1 : 3 }
        return hasFocus ? 3 : 5
    }

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content, linksSteps: true) {
            message
        } else if case .active(let day) = entry.content {
            let hasFocus = day.lead == .now || day.lead == .next
            let layout = WidgetDayLayout(day: day, rowLimit: rowLimit(hasFocus: hasFocus), showsCompleted: entry.preferences.showCompletedMeals)
            VStack(alignment: .leading, spacing: 6) {
                WidgetDayHeader(day: day)
                if !layout.folded.isEmpty {
                    foldedRow(layout.folded)
                }
                ForEach(layout.earlier) { item in
                    WidgetMealRow(item: item, entry: entry, actions: actions)
                }
                if let focus = layout.focus, let lead = day.lead {
                    WidgetFocusCard(day: day, item: focus, lead: lead, entry: entry, actions: actions)
                } else if day.isDayComplete {
                    completeCard(day)
                } else if day.schedule.isEmpty, let primary = day.primary, let lead = day.lead {
                    laterDayCard(day, primary: primary, lead: lead)
                }
                ForEach(layout.later) { item in
                    WidgetMealRow(item: item, entry: entry, actions: actions)
                }
                if layout.hidden > 0 {
                    Text(WidgetText.more(layout.hidden))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
                Spacer(minLength: 0)
                WidgetDayFooter(day: day, entry: entry)
            }
        }
    }

    private func foldedRow(_ items: [WidgetMealItem]) -> some View {
        let eaten = items.filter { $0.role == .done }.count
        return HStack(spacing: 6) {
            Image(systemName: "chevron.up")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(WidgetText.earlier(items.count, eaten: eaten))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }

    private func completeCard(_ day: WidgetDayContent) -> some View {
        HStack(spacing: AppSpacing.small) {
            WidgetSegmentedRing(schedule: day.schedule, lineWidth: 5) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(theme.success)
                    .widgetAccentable()
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("widget.dayComplete", bundle: .module)
                    .font(.headline)
                    .lineLimit(2)
                Text(day.progressAccessibilityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .modifier(WidgetHighlight(isActive: true, cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func laterDayCard(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> some View {
        WidgetLink(url: AppLink.meal(primary.key).url) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    WidgetMealTile(type: primary.type, size: 30)
                    WidgetLeadChip(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                }
                Text(primary.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(3)
                WidgetMealTimeRow(item: primary, energy: entry.energyText(primary))
                WidgetLiveLine(day: day, primary: primary, entry: entry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .modifier(WidgetHighlight(isActive: true, cornerRadius: 16))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The weekday and date, the plan and its day, and how many meals are still ahead.
struct WidgetDayHeader: View {
    let day: WidgetDayContent
    var isCompact = false
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if isCompact {
                Text(day.today.middayDate(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(day.today.middayDate(), format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(verbatim: WidgetText.planDay(day))
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: AppSpacing.xSmall)
            if day.remainingCount > 0 {
                Text(WidgetText.remaining(day.remainingCount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if day.isDayComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.success)
                    .widgetAccentable()
                    .accessibilityLabel(Text("widget.dayComplete", bundle: .module))
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The meal in front on Today's Meals: its sitting, name, time, the time left, and its buttons.
struct WidgetFocusCard<Action: View>: View {
    let day: WidgetDayContent
    let item: WidgetMealItem
    let lead: WidgetDayContent.Lead
    let entry: MealWidgetEntry
    let actions: WidgetActions<Action>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                WidgetLink(url: AppLink.meal(item.key).url) {
                    HStack(alignment: .top, spacing: 8) {
                        WidgetMealTile(type: item.type, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            WidgetLeadChip(text: WidgetText.lead(lead, typeLabel: item.typeLabel, today: day.today))
                            name
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: item.spokenLabel(energyUnit: entry.preferences.showCalories ? entry.preferences.energyUnit : nil)))
                if entry.canMarkEaten(lead) {
                    actions(.markEaten(item), .check)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    if lead != .now {
                        WidgetMealTimeRow(item: item, font: .subheadline.weight(.bold), energy: entry.energyText(item))
                    }
                    WidgetLiveLine(day: day, primary: item, entry: entry)
                }
                Spacer(minLength: 0)
                if day.offersStartDay {
                    actions(.startDay, .capsule)
                } else {
                    WidgetCookChip(item: item)
                }
            }
        }
        .padding(10)
        .modifier(WidgetHighlight(isActive: true, cornerRadius: 16))
        .id(item.key)
        .transition(.push(from: .bottom))
        .invalidatableContent()
    }

    /// The title, or a title written as a list of foods drawn as a plate: up to three, then "+2 more".
    @ViewBuilder
    private var name: some View {
        let plate = item.plateItems
        if plate.isEmpty {
            Text(item.title)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(plate.prefix(3).enumerated()), id: \.offset) { _, food in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Circle()
                            .frame(width: 4, height: 4)
                            .foregroundStyle(.secondary)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                        Text(verbatim: food)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                if plate.count > 3 {
                    Text(WidgetText.more(plate.count - 3))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One meal of Today's Meals on one line: its status, which is also its button, then its time,
/// sitting and name, which open it.
struct WidgetMealRow<Action: View>: View {
    let item: WidgetMealItem
    let entry: MealWidgetEntry
    let actions: WidgetActions<Action>
    var isCompact = false
    var isHighlighted = false

    private var isMarked: Bool { item.role == .done || item.role == .skipped }

    var body: some View {
        HStack(spacing: 6) {
            if entry.preferences.showDoneButton {
                actions(isMarked ? .unmark(item) : .markEaten(item), .status(item.role))
            } else {
                WidgetStatusSymbol(role: item.role)
                    .frame(width: 26, height: 26)
            }
            WidgetLink(url: AppLink.meal(item.key).url) {
                HStack(spacing: 8) {
                    WidgetTimeColumn(date: item.date, isMuted: isMarked)
                    if !isCompact {
                        Image(systemName: item.type.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                    }
                    Text(item.title)
                        .font(.subheadline.weight(isHighlighted ? .semibold : .regular))
                        .foregroundStyle(isMarked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if item.isMoved, !isMarked {
                        WidgetShiftChip(minutes: item.shiftMinutes)
                    }
                    Spacer(minLength: 0)
                    if let energy = entry.energyText(item) {
                        Text(verbatim: energy)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: item.spokenLabel(energyUnit: entry.preferences.showCalories ? entry.preferences.energyUnit : nil)))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, isCompact ? 2 : 3)
        // Rows share the room left, up to a comfortable height, so a short day does not leave the
        // bottom of the widget empty.
        .frame(minHeight: isCompact ? 26 : 30, maxHeight: isCompact ? 32 : 40)
        .modifier(WidgetHighlight(isActive: isHighlighted))
        .invalidatableContent()
    }
}

/// The line at the foot of Today's Meals, always there: how the day is going, or once it is done,
/// what comes first tomorrow.
struct WidgetDayFooter: View {
    let day: WidgetDayContent
    let entry: MealWidgetEntry
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            if day.remainingCount == 0, let tomorrow = day.nextDayFirst {
                HStack(spacing: 6) {
                    Image(systemName: tomorrow.type.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .widgetAccentable()
                        .accessibilityHidden(true)
                    Text(WidgetText.tomorrowMeal(tomorrow))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if !day.schedule.isEmpty {
                HStack(spacing: 8) {
                    WidgetMealBar(schedule: day.schedule)
                        .frame(height: 5)
                    if entry.preferences.showCalories, let energy = day.energy {
                        Text(verbatim: WidgetText.energy(energy, unit: entry.preferences.energyUnit))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Text(day.progressAccessibilityLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Today's Meals, medium: the day as rows, centred on the meal that matters now.
struct TodayMediumWidgetView<Action: View>: View {
    let entry: MealWidgetEntry
    let actions: WidgetActions<Action>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rowLimit: Int {
        dynamicTypeSize >= .xxLarge ? 2 : 3
    }

    var body: some View {
        if let message = WidgetMessageView.view(for: entry.content, linksSteps: true) {
            message
        } else if case .active(let day) = entry.content {
            let rows = visibleRows(day)
            VStack(alignment: .leading, spacing: 4) {
                WidgetDayHeader(day: day, isCompact: true)
                if rows.items.isEmpty, let primary = day.primary, let lead = day.lead {
                    WidgetLink(url: AppLink.meal(primary.key).url) {
                        VStack(alignment: .leading, spacing: 4) {
                            WidgetLeadChip(text: WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today))
                            Text(primary.title)
                                .font(.headline)
                                .lineLimit(2)
                            WidgetMealTimeRow(item: primary, font: .subheadline.weight(.bold))
                        }
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                } else {
                    ForEach(rows.items) { item in
                        WidgetMealRow(item: item, entry: entry, actions: actions, isCompact: true, isHighlighted: item.key == day.primary?.key && (day.lead == .now || day.lead == .next))
                    }
                    Spacer(minLength: 0)
                    if rows.hidden > 0 {
                        Text(WidgetText.more(rows.hidden))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                }
            }
        }
    }

    /// The rows that fit, centred on the meal that matters now. With three or more meals still
    /// ahead, the ones already marked give way to them.
    private func visibleRows(_ day: WidgetDayContent) -> (items: [WidgetMealItem], hidden: Int) {
        let hidesMarked = !entry.preferences.showCompletedMeals || day.remainingCount >= 3
        let all = hidesMarked ? day.schedule.filter { $0.role != .done && $0.role != .skipped } : day.schedule
        guard all.count > rowLimit else { return (all, 0) }
        let focusIndex = all.firstIndex { $0.role == .current || $0.role == .next } ?? all.firstIndex { $0.role == .upcoming } ?? all.count - 1
        let start = min(max(focusIndex - 1, 0), all.count - rowLimit)
        return (Array(all[start..<(start + rowLimit)]), all.count - rowLimit)
    }
}

// MARK: - Lock Screen

/// "Next · Lunch · 14:00" over the meal's name, on two lines.
struct RectangularMealWidgetView: View {
    let entry: MealWidgetEntry

    var body: some View {
        if case .active(let day) = entry.content, let primary = day.primary, let lead = day.lead {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: primary.type.symbolName)
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(verbatim: line(day, primary: primary, lead: lead))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .widgetAccentable()
                Text(primary.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .privacySensitive(entry.preferences.hidesMealNamesWhenLocked)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else if let message = WidgetMessageView.view(for: entry.content, compact: true) {
            message
        }
    }

    private func line(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> String {
        let leadText = WidgetText.lead(lead, typeLabel: primary.typeLabel, today: day.today)
        if lead == .now {
            return leadText
        }
        return "\(leadText) · \(primary.date.formatted(.dateTime.hour().minute()))"
    }
}

/// "14:00 · Grilled Chicken Caesar Salad" beside the meal's symbol, above the clock.
struct InlineMealWidgetView: View {
    let entry: MealWidgetEntry

    var body: some View {
        if case .active(let day) = entry.content, let primary = day.primary {
            Label {
                if entry.preferences.hidesMealNamesWhenLocked {
                    Text(verbatim: "\(primary.date.formatted(.dateTime.hour().minute())) · \(primary.typeLabel)")
                } else {
                    Text(verbatim: WidgetText.inline(primary))
                }
            } icon: {
                Image(systemName: primary.type.symbolName)
            }
        } else if let message = WidgetMessageView.view(for: entry.content, compact: true) {
            Text(message.title)
        }
    }
}

/// A ring that empties until the next meal, with its symbol and time in the middle. While a meal
/// is on, the ring empties until it gives way.
struct CircularMealWidgetView: View {
    let entry: MealWidgetEntry
    @Environment(\.widgetRendering) private var rendering

    var body: some View {
        if case .active(let day) = entry.content, let primary = day.primary, let lead = day.lead {
            let range = interval(day, primary: primary, lead: lead)
            ZStack {
                AccessoryWidgetBackground()
                // A ring that runs by itself is a widget's; the app's preview redraws every minute.
                if rendering == .widget, !entry.isFrozen, let range {
                    ProgressView(timerInterval: range, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.circular)
                    .widgetAccentable()
                } else if let range {
                    Gauge(value: fractionLeft(range), in: 0...1) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .widgetAccentable()
                }
                VStack(spacing: 0) {
                    Image(systemName: primary.type.symbolName)
                        .font(.caption.weight(.bold))
                    Text(primary.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: primary.accessibilityLabel))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "fork.knife")
                    .font(.title3)
            }
            .accessibilityLabel(Text(verbatim: WidgetText.appName()))
        }
    }

    private func interval(_ day: WidgetDayContent, primary: WidgetMealItem, lead: WidgetDayContent.Lead) -> ClosedRange<Date>? {
        if lead == .now, let ends = day.primaryEnds, primary.date < ends {
            return primary.date...ends
        }
        if let start = day.waitStarted, start < primary.date {
            return start...primary.date
        }
        return nil
    }

    private func fractionLeft(_ range: ClosedRange<Date>) -> Double {
        let total = max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
        let left = range.upperBound.timeIntervalSince(entry.reference)
        return min(max(left / total, 0), 1)
    }
}
