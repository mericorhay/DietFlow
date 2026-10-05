import Foundation
import SwiftUI
import UIKit
import AppCore
import DesignSystem
import Domain

/// The meal in front: its time large, its name under it, and — when it is on now — the two things
/// to do about it. Typography carries it; there is no card.
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
    var onDone: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
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
                }
            }
            .font(.subheadline)

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

            if let details = occurrence.meal.details?.trimmedNonEmpty {
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let calories = occurrence.meal.nutrition.calories {
                Text(energyUnit.format(kilocalories: calories))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if onDone != nil || onSkip != nil {
                actions.padding(.top, AppSpacing.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(occurrence.key)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.small) { actionButtons }
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) { actionButtons }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Group {
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

    private var leadDetail: String? {
        switch lead {
        case .now: RelativeTimeText.since(occurrence.date, from: now)
        case .next: RelativeTimeText.until(occurrence.date, from: now)
        case .laterDay, .firstOfDay: nil
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
                Text(occurrence.date, format: .dateTime.hour().minute())
                    .font(.body.weight(isFocus ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isMarked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .frame(minWidth: timeColumn, alignment: .leading)
            }
            statusButton
            VStack(alignment: .leading, spacing: 2) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(occurrence.date, format: .dateTime.hour().minute())
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
                Text(occurrence.meal.typeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(occurrence.meal.title)
                    .font(.body.weight(isFocus ? .semibold : .regular))
                    .foregroundStyle(isMarked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                if occurrence.state == .skipped {
                    Text("today.row.skipped", bundle: .module)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, AppSpacing.small)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MealAccessibility.label(typeLabel: occurrence.meal.typeLabel, date: occurrence.date, title: occurrence.meal.title, role: accessibilityRole))
            .accessibilityAddTraits(.isButton)
            Spacer(minLength: 0)
            tag
        }
        .padding(.horizontal, AppSpacing.xSmall)
        // Lets the status column stretch to the row's height, so the timeline line is unbroken.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The circle on the timeline. Its line runs through the whole row so rows join up.
    private var statusButton: some View {
        Button {
            onSetState(occurrence.state == .completed ? .pending : .completed)
        } label: {
            MealStatusSymbol(MealStatusSymbol.Status(showsTags ? item.role : (occurrence.state == .completed ? .done : occurrence.state == .skipped ? .skipped : .upcoming)))
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

/// A quiet suggestion under today's meals: the widget is the point of the app, and many people
/// never find the Widgets tab on their own. Closed once, it does not come back.
struct WidgetTip: View {
    let model: WidgetTipModel

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            Image(systemName: "rectangle.3.group")
                .font(.title3)
                .foregroundStyle(AppColors.brandAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("today.widgetTip.title", bundle: .module)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("today.widgetTip.message", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: model.show) {
                    Text("today.widgetTip.show", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(AppColors.brandAccent)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button(action: model.dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppSpacing.minimumHitTarget, height: AppSpacing.minimumHitTarget, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("today.widgetTip.dismiss", bundle: .module))
        }
        .padding(.vertical, AppSpacing.medium)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.screenMargin, bottom: 0, trailing: AppSpacing.xSmall))
    }
}
