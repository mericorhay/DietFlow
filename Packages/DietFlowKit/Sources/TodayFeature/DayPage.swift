import Foundation
import SwiftUI
import AppCore
import DesignSystem
import Domain

/// One day: the meal in front, then the timeline. Today puts the current or next meal in front;
/// a later day its first meal; an earlier day just its record.
struct DayPage: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let day: CalendarDay
    let today: CalendarDay
    let now: Date
    let actions: TodayActions
    /// Shown under today's meals while the widget is not on screen yet.
    var widgetTip: WidgetTipModel?

    var body: some View {
        let agenda = store.agenda(on: day, now: now)
        List {
            hero(agenda)

            if let agenda, !agenda.items.isEmpty {
                scheduleHeading(agenda)
                ForEach(Array(agenda.items.enumerated()), id: \.element.id) { index, item in
                    MealTimelineRow(
                        item: item,
                        isFirst: index == 0,
                        isLast: index == agenda.items.count - 1,
                        showsTags: day == today,
                        canMark: day <= today,
                        onSetState: { state in set(state, for: item.occurrence.key) }
                    )
                }
                if day == today, agenda.isComplete {
                    CompletionFooter()
                        .listRowSeparator(.hidden)
                        .transition(.opacity)
                }
            } else if let agenda, case .active = agenda.phase {
                DayMessage(
                    symbol: "fork.knife",
                    title: String(localized: "today.noMeals.title", bundle: .module),
                    message: nil,
                    actionTitle: String(localized: "today.noMeals.add", bundle: .module),
                    action: { actions.addMeal(day) }
                )
                .listRowSeparator(.hidden)
            }

            if let widgetTip {
                WidgetTip(model: widgetTip)
                    .transition(.opacity)
            }
        }
        .listStyle(.plain)
        .animation(AppMotion.animation(AppMotion.snappy, reduceMotion: reduceMotion), value: store.revision)
    }

    // MARK: Hero

    @ViewBuilder
    private func hero(_ agenda: DayAgenda?) -> some View {
        if let schedule = store.schedule {
            switch schedule.phase(on: day) {
            case .notStarted(let start):
                notStarted(start, schedule: schedule)
            case .ended(let lastDay):
                ended(lastDay)
            case .active:
                if day == today {
                    todayHero()
                } else if day > today, let first = agenda?.items.first?.occurrence {
                    NextMealSection(occurrence: first, lead: .firstOfDay, now: now, energyUnit: store.settings.energyUnit)
                        .heroRow()
                }
            }
        }
    }

    @ViewBuilder
    private func todayHero() -> some View {
        if let focus = store.focus(now: now) {
            switch focus.kind {
            case .now:
                NextMealSection(
                    occurrence: focus.occurrence,
                    lead: .now,
                    now: now,
                    energyUnit: store.settings.energyUnit,
                    onDone: { set(.completed, for: focus.occurrence.key) },
                    onSkip: { set(.skipped, for: focus.occurrence.key) }
                )
                .heroRow()
            case .next:
                NextMealSection(occurrence: focus.occurrence, lead: .next, now: now, energyUnit: store.settings.energyUnit)
                    .heroRow()
            case .laterDay:
                NextMealSection(occurrence: focus.occurrence, lead: .laterDay(today: today), now: now, energyUnit: store.settings.energyUnit)
                    .heroRow()
            }
        }
    }

    @ViewBuilder
    private func notStarted(_ start: CalendarDay, schedule: MealSchedule) -> some View {
        let date = start.middayDate().formatted(.dateTime.weekday(.wide).month(.wide).day())
        DayMessage(
            symbol: "calendar",
            title: String(localized: "today.notStarted.title", defaultValue: "Your plan starts \(date)", bundle: .module),
            message: nil,
            actionTitle: nil,
            action: nil
        )
        .listRowSeparator(.hidden)
        if let first = schedule.occurrences(on: start, states: store.states).first {
            NextMealSection(occurrence: first, lead: .laterDay(today: today), now: now, energyUnit: store.settings.energyUnit)
                .heroRow()
        }
    }

    private func ended(_ lastDay: CalendarDay) -> some View {
        let name = store.activePlan?.name ?? ""
        let date = lastDay.middayDate().formatted(.dateTime.month(.wide).day())
        return DayMessage(
            symbol: "flag.checkered",
            title: String(localized: "today.ended.title", bundle: .module),
            message: String(localized: "today.ended.message", defaultValue: "\(name) ended on \(date).", bundle: .module),
            actionTitle: String(localized: "today.ended.startAgain", bundle: .module),
            action: restartPlan
        )
        .listRowSeparator(.hidden)
    }

    private func scheduleHeading(_ agenda: DayAgenda) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("today.schedule.title", bundle: .module)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text(day == today
                 ? String(localized: "today.remaining", defaultValue: "\(agenda.remainingCount) remaining", bundle: .module)
                 : String(localized: "today.mealCount", defaultValue: "\(agenda.items.count) meals", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.top, AppSpacing.small)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.screenMargin, bottom: AppSpacing.xxSmall, trailing: AppSpacing.screenMargin))
    }

    // MARK: Changes

    private func set(_ state: OccurrenceState, for key: OccurrenceKey) {
        withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
            store.attempt { try store.setState(state, for: key) }
        }
    }

    private func restartPlan() {
        guard var plan = store.activePlan else { return }
        plan.schedule.startDay = today
        withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
            store.attempt { try store.replacePlan(plan) }
        }
    }
}

private extension View {
    /// The hero sits on the page, not in a row: no separator, the screen's own margins.
    func heroRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: AppSpacing.medium, leading: AppSpacing.screenMargin, bottom: AppSpacing.medium, trailing: AppSpacing.screenMargin))
    }
}

/// A short note in place of a day's meals: nothing scheduled, not started yet, finished.
struct DayMessage: View {
    let symbol: String
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .padding(.top, AppSpacing.xxSmall)
            }
        }
        .padding(.vertical, AppSpacing.small)
        .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.screenMargin, bottom: 0, trailing: AppSpacing.screenMargin))
    }
}

/// "Today's plan is complete." A checkmark that bounces once, and a success tap from the screen.
struct CompletionFooter: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(AppColors.success)
                .symbolEffect(.bounce, value: shown)
                .accessibilityHidden(true)
            Text("today.complete", bundle: .module)
                .font(.headline)
        }
        .padding(.vertical, AppSpacing.medium)
        .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.screenMargin, bottom: 0, trailing: AppSpacing.screenMargin))
        .accessibilityElement(children: .combine)
        .onAppear {
            if !reduceMotion { shown = true }
        }
    }
}
