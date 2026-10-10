import Foundation
import SwiftUI
import UIKit
import AppCore
import DesignSystem
import Domain

/// The meal in front. On now: its name large, what it is and when, how long it stays in front,
/// and the two things to do about it. Next: its time large and a countdown. Always the meal after
/// it, so the day reads at a glance. Typography carries it; there is no card. The text opens the
/// meal.
struct NextMealSection: View {
    enum Lead {
        case now
        case next
        /// The first meal of a later day than `today`.
        case laterDay(today: CalendarDay)
        /// The first meal of the day being looked at.
        case firstOfDay
    }

    let occurrence: MealOccurrence
    let lead: Lead
    let now: Date
    let energyUnit: EnergyUnit
    /// The meal after this one, for the "Then" line.
    var following: MealOccurrence? = nil
    /// When a meal on now gives way to the next one: the end of its "40 min left" bar.
    var windowEnd: Date? = nil
    var onDone: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    /// Opens cook mode for this meal; nil without the assistant.
    var onCook: (() -> Void)? = nil

    @Environment(MealAssistantModel.self) private var assistant
    @Environment(AccessModel.self) private var access
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A recipe already written for this meal opens for free, so it shows no cost.
    @State private var isRecipeKept = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            NavigationLink(value: MealRoute.occurrence(occurrence.key)) {
                summary
                    .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityActions {
                if let onDone {
                    Button(action: onDone) { Text("today.hero.markDone", bundle: .module) }
                }
                if let onSkip {
                    Button(action: onSkip) { Text("today.hero.skip", bundle: .module) }
                }
            }

            if onDone != nil || onSkip != nil {
                markButtons
            }
            if let onCook {
                AssistantButton(Text("today.hero.cook", bundle: .module), cost: cookCost, action: onCook)
            }
            if let following {
                thenLine(following)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(occurrence.key)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
        .task(id: occurrence.key) { checkRecipe() }
        .onAppear { checkRecipe() }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                leadLine
                switch lead {
                case .now:
                    nowBody
                case .next, .laterDay, .firstOfDay:
                    timeBody
                }
                if let details = occurrence.meal.details?.trimmedNonEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if occurrence.isMoved {
                    movedLine
                }
            }
            Spacer(minLength: 0)
            if !dynamicTypeSize.isAccessibilitySize {
                MealGlyph(occurrence.meal.type, size: 44)
                    .padding(.top, AppSpacing.xxSmall)
            }
        }
        .contentShape(Rectangle())
    }

    private var leadLine: some View {
        HStack(spacing: AppSpacing.xxSmall + 2) {
            Text(leadTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.brandAccent)
            if let leadDetail {
                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(leadDetail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animationAware(AppMotion.snappy, reduceMotion: reduceMotion, value: leadDetail)
            }
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
    }

    /// On now, the name is what matters: the time has already come.
    @ViewBuilder
    private var nowBody: some View {
        Text(occurrence.meal.title)
            .font(.title.weight(.bold))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
        Text(verbatim: nowMeta)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        if let windowEnd, windowEnd > now {
            timeLeft(until: windowEnd)
                .padding(.top, AppSpacing.xxSmall)
        }
    }

    /// Later, the time is what matters.
    @ViewBuilder
    private var timeBody: some View {
        // At accessibility sizes the large time takes the whole width, so the type goes under it.
        let timeAndType = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.small))
        timeAndType {
            Text(occurrence.date, format: .dateTime.hour().minute())
                .font(.largeTitle.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(occurrence.meal.typeLabel)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
        Text(occurrence.meal.title)
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
        if let energy = energyUnit.format(occurrence.meal.nutrition) {
            Text(verbatim: energy)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "Lunch · 20:48 · ≈ 510 kcal".
    private var nowMeta: String {
        [
            occurrence.meal.typeLabel,
            occurrence.date.formatted(date: .omitted, time: .shortened),
            energyUnit.format(occurrence.meal.nutrition),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// A capsule filling up as the meal's time in front runs out, and how much is left.
    private func timeLeft(until end: Date) -> some View {
        let total = end.timeIntervalSince(occurrence.date)
        let left = end.timeIntervalSince(now)
        let fraction = total > 0 ? min(max(1 - left / total, 0), 1) : 1
        let minutes = max(Int((left / 60).rounded(.up)), 1)
        let amount = Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
        )
        return HStack(spacing: AppSpacing.xSmall) {
            Capsule()
                .fill(AppColors.brandWash)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(AppColors.brandAccent)
                            .frame(width: max(6, proxy.size.width * fraction))
                    }
                }
                .frame(maxWidth: 140)
                .animationAware(AppMotion.settle, reduceMotion: reduceMotion, value: fraction)
                .accessibilityHidden(true)
            Text(String(localized: "today.hero.timeLeft", defaultValue: "\(amount) left", bundle: .module))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.brandAccent)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animationAware(AppMotion.snappy, reduceMotion: reduceMotion, value: minutes)
        }
    }

    /// The day started late, so this meal is not at the plan's time; say from where it moved.
    private var movedLine: some View {
        let planned = occurrence.meal.time.date(on: occurrence.day).formatted(date: .omitted, time: .shortened)
        return Label {
            Text(String(localized: "today.hero.moved", defaultValue: "Moved from \(planned)", bundle: .module))
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    // MARK: Actions

    private var markButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.small) { markButtonRow }
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) { markButtonRow }
        }
        .controlSize(.large)
        .padding(.top, AppSpacing.xxSmall)
    }

    @ViewBuilder
    private var markButtonRow: some View {
        if let onDone {
            Button(action: onDone) {
                Label {
                    Text("today.hero.markDone", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.brandAccent)
        }
        if let onSkip {
            Button(action: onSkip) {
                Text("today.hero.skip", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
    }

    /// "Then 16:30 · Apple and almonds": the meal after this one, on another day with its weekday.
    private func thenLine(_ next: MealOccurrence) -> some View {
        let time = next.day == occurrence.day
            ? next.date.formatted(date: .omitted, time: .shortened)
            : next.date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return Text(String(localized: "today.hero.then", defaultValue: "Then \(time) · \(next.meal.title)", bundle: .module))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.top, AppSpacing.xxSmall)
    }

    private var cookCost: AssistantCost? {
        isRecipeKept ? nil : AssistantCost.caption(remaining: assistant.remaining(.aiRecipe), tier: access.tier)
    }

    private func checkRecipe() {
        guard onCook != nil else { return }
        isRecipeKept = assistant.cachedRecipe(for: occurrence.meal) != nil
    }

    private var leadTitle: String {
        switch lead {
        case .now:
            return String(localized: "today.hero.now", bundle: .module)
        case .next:
            return String(localized: "today.hero.next", bundle: .module)
        case .laterDay(let today):
            if occurrence.day == today.adding(days: 1) {
                return String(localized: "today.hero.tomorrow", bundle: .module)
            }
            return occurrence.day.middayDate().formatted(.dateTime.weekday(.wide))
        case .firstOfDay:
            return String(localized: "today.hero.firstMeal", bundle: .module)
        }
    }

    /// Next: a countdown. Now says nothing here; its bar says how long is left.
    private var leadDetail: String? {
        switch lead {
        case .next: RelativeTimeText.until(occurrence.date, from: now)
        case .now, .laterDay, .firstOfDay: nil
        }
    }
}

/// One meal in the day's timeline: time, a status circle on the timeline that marks it done with a
/// tap, its type and name. Swipe for Done and Skip; touch and hold for the same. Tap the row for
/// the meal's details.
struct MealTimelineRow: View {
    let item: AgendaItem
    let isFirst: Bool
    let isLast: Bool
    /// Only today's timeline says which meal is on now or next.
    let showsTags: Bool
    /// Meals on later days cannot be marked yet.
    let canMark: Bool
    let onSetState: (OccurrenceState) -> Void

    @ScaledMetric(relativeTo: .body) private var timeColumn: CGFloat = 52
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var occurrence: MealOccurrence { item.occurrence }
    private var isMarked: Bool { occurrence.state != .pending }
    /// Its time went by and nobody marked it.
    private var isMissed: Bool { item.role == .past }
    /// Drawn quieter: done, skipped, or gone by.
    private var isQuiet: Bool { isMarked || isMissed }
    /// Where the plan puts it, when a late start moved it.
    private var plannedDate: Date { occurrence.meal.time.date(on: occurrence.day) }
    private var isFocus: Bool { showsTags && (item.role == .current || item.role == .next) }

    var body: some View {
        ZStack {
            // A hidden link makes the whole row open the meal, without a disclosure chevron.
            NavigationLink(value: MealRoute.occurrence(occurrence.key)) { EmptyView() }
                .opacity(0)
                .accessibilityHidden(true)
            row
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.small, bottom: 0, trailing: AppSpacing.small))
        .listRowBackground(highlight)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) { swipeButtons }
        .contextMenu { menuButtons }
        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.97, 1.0], trigger: occurrence.state) { content, scale in
            content.scaleEffect(scale)
        } animation: { _ in
            .snappy(duration: 0.14)
        }
    }

    private var row: some View {
        HStack(spacing: AppSpacing.xSmall) {
            if !dynamicTypeSize.isAccessibilitySize {
                times
                    .frame(minWidth: timeColumn, alignment: .leading)
            }
            statusButton
            VStack(alignment: .leading, spacing: 2) {
                if dynamicTypeSize.isAccessibilitySize {
                    times
                }
                Text(occurrence.meal.typeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(occurrence.meal.title)
                    .font(.body.weight(isFocus ? .semibold : .regular))
                    .foregroundStyle(isQuiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                if occurrence.state == .skipped {
                    Text("today.row.skipped", bundle: .module)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, AppSpacing.small)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
            Spacer(minLength: 0)
            tag
        }
        .padding(.horizontal, AppSpacing.xSmall)
        // Lets the status column stretch to the row's height, so the timeline line is unbroken.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The time it is at, and when a late start moved it, the plan's own time struck through
    /// under it.
    private var times: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(occurrence.date, format: .dateTime.hour().minute())
                .font(.body.weight(isFocus || dynamicTypeSize.isAccessibilitySize ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isQuiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .contentTransition(.numericText())
            if occurrence.isMoved {
                Text(plannedDate, format: .dateTime.hour().minute())
                    .font(.caption)
                    .monospacedDigit()
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    /// "Lunch, 3:30 PM, Caesar salad, next meal, moved from 2:00 PM to 3:30 PM."
    private var accessibilityText: String {
        let label = MealAccessibility.label(typeLabel: occurrence.meal.typeLabel, date: occurrence.date, title: occurrence.meal.title, role: accessibilityRole)
        guard occurrence.isMoved else { return label }
        let from = plannedDate.formatted(date: .omitted, time: .shortened)
        let to = occurrence.date.formatted(date: .omitted, time: .shortened)
        return String(localized: "today.a11y.movedMeal", defaultValue: "\(label), moved from \(from) to \(to)", bundle: .module)
    }

    /// The circle on the timeline. Its line runs through the whole row so rows join up.
    private var statusButton: some View {
        Button {
            onSetState(occurrence.state == .completed ? .pending : .completed)
        } label: {
            MealStatusSymbol(statusSymbol)
                .symbolEffect(.bounce, value: occurrence.state == .completed)
                .frame(width: AppSpacing.minimumHitTarget, height: AppSpacing.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!canMark)
        .frame(maxHeight: .infinity)
        .background {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : Color(.separator))
                    .frame(width: 1.5)
                Color.clear.frame(height: 28)
                Rectangle().fill(isLast ? Color.clear : Color(.separator))
                    .frame(width: 1.5)
            }
            .accessibilityHidden(true)
        }
        .accessibilityLabel(occurrence.state == .completed
            ? String(localized: "today.a11y.markNotDone", defaultValue: "Mark \(occurrence.meal.title) not done", bundle: .module)
            : String(localized: "today.a11y.markDone", defaultValue: "Mark \(occurrence.meal.title) done", bundle: .module))
    }

    /// Today says which meal is on now and next; other days only what happened, and which meals
    /// went by unmarked.
    private var statusSymbol: MealStatusSymbol.Status {
        if showsTags { return MealStatusSymbol.Status(item.role) }
        switch occurrence.state {
        case .completed: return .done
        case .skipped: return .skipped
        case .pending: return isMissed ? .missed : .pending
        }
    }

    @ViewBuilder
    private var tag: some View {
        if showsTags, item.role == .current {
            Text("today.row.now", bundle: .module)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.brandAccent)
                .accessibilityHidden(true)
        } else if showsTags, item.role == .next {
            Text("today.row.next", bundle: .module)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.brandAccent)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var highlight: some View {
        if isFocus {
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(AppColors.brandWash)
                .padding(.horizontal, AppSpacing.small)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var swipeButtons: some View {
        if canMark {
            if occurrence.state == .pending {
                Button { onSetState(.completed) } label: {
                    Label { Text("today.action.done", bundle: .module) } icon: { Image(systemName: "checkmark") }
                }
                .tint(.green)
                Button { onSetState(.skipped) } label: {
                    Label { Text("today.action.skip", bundle: .module) } icon: { Image(systemName: "forward.end") }
                }
                .tint(.gray)
            } else {
                Button { onSetState(.pending) } label: {
                    Label { Text("today.action.undo", bundle: .module) } icon: { Image(systemName: "arrow.uturn.backward") }
                }
                .tint(.gray)
            }
        }
    }

    @ViewBuilder
    private var menuButtons: some View {
        if canMark {
            if occurrence.state != .completed {
                Button { onSetState(.completed) } label: {
                    Label { Text("today.action.done", bundle: .module) } icon: { Image(systemName: "checkmark.circle") }
                }
            }
            if occurrence.state != .skipped {
                Button { onSetState(.skipped) } label: {
                    Label { Text("today.action.skip", bundle: .module) } icon: { Image(systemName: "forward.end") }
                }
            }
            if occurrence.state != .pending {
                Button { onSetState(.pending) } label: {
                    Label { Text("today.action.undo", bundle: .module) } icon: { Image(systemName: "arrow.uturn.backward") }
                }
            }
        }
    }

    private var accessibilityRole: MealRole? {
        if showsTags { return item.role == .upcoming ? nil : item.role }
        switch occurrence.state {
        case .completed: return .done
        case .skipped: return .skipped
        case .pending: return nil
        }
    }
}

/// What the widget suggestion does when tapped or closed.
struct WidgetTipModel {
    let show: () -> Void
    let dismiss: () -> Void
}

/// A compact suggestion at the top of today: the widget is the point of the app, and many people
/// never find the Widgets tab on their own. Closed once, it does not come back; it goes by itself
/// once a widget is on screen.
struct WidgetTip: View {
    let model: WidgetTipModel

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.title3)
                .foregroundStyle(AppColors.brandAccent)
                .frame(width: 40, height: 40)
                .background(AppColors.brandWash, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("today.widgetTip.title", bundle: .module)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: model.show) {
                    Text("today.widgetTip.show", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(AppColors.brandAccent)
                .accessibilityHint(Text("today.widgetTip.message", bundle: .module))
            }
            Spacer(minLength: 0)
            Button(action: model.dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppSpacing.minimumHitTarget, height: AppSpacing.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("today.widgetTip.dismiss", bundle: .module))
        }
        .padding(.leading, AppSpacing.small)
        .padding(.vertical, AppSpacing.xSmall)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: AppSpacing.xSmall, leading: AppSpacing.screenMargin, bottom: AppSpacing.xxSmall, trailing: AppSpacing.screenMargin))
    }
}
