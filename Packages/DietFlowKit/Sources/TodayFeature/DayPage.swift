import Foundation
import SwiftUI
import AppCore
import DesignSystem
import Domain

/// One day: the meal in front, then the timeline. Today puts the current or next meal in front;
/// a later day its first meal; an earlier day just its record.
///
/// Today, top to bottom: the widget suggestion while there is no widget, the morning question,
/// the meal in front (or tomorrow's, once the day is done), what the day adds up to, the
/// assistant's offer to fill in missing nutrition, the meals, and last one quiet card about Plus.
struct DayPage: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(MealAssistantModel.self) private var assistant
    @Environment(AccessModel.self) private var access
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let day: CalendarDay
    let today: CalendarDay
    let now: Date
    let actions: TodayActions
    /// Shown at the top of today while the widget is not on screen yet.
    var widgetTip: WidgetTipModel?
    /// Something worth a word on screen happened: a meal eaten, the day moved.
    var onMoment: @MainActor (TodayToast.Kind) -> Void = { _ in }

    /// Meals that went by unmarked are folded away until asked for.
    @State private var showsEarlier = false
    @State private var asksWakeTime = false

    private var isToday: Bool { day == today }

    var body: some View {
        let agenda = store.agenda(on: day, now: now)
        let question = isToday ? MorningQuestion.at(now, today: today, store: store) : nil
        let focus = isToday ? store.focus(now: now) : nil
        List {
            if isToday, let widgetTip {
                WidgetTip(model: widgetTip)
                    .transition(.opacity)
            }

            if let question {
                MorningCard(
                    question: question,
                    today: today,
                    isQuiet: focus?.kind == .now,
                    onUp: { startDay(DayStart.wokeUp(at: TimeOfDay(now), source: .morning)) },
                    onKeepTimes: keepPlannedTimes,
                    onPickWakeTime: { asksWakeTime = true }
                )
                .cardRow()
                .transition(.opacity)
            }

            hero(agenda, focus: focus)

            if let agenda, let nutrition = DayNutrition(items: agenda.items) {
                PlannedTodayCard(nutrition: nutrition, energyUnit: store.settings.energyUnit, isToday: isToday)
                    .cardRow()
            }

            if isToday, showsEstimateCard {
                EstimateCard()
                    .cardRow()
                    .transition(.opacity)
            }

            if let agenda, !agenda.items.isEmpty {
                timeline(agenda)
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

            if isToday, showsPlusCard {
                PlusCard(
                    onShow: actions.showPlus,
                    onDismiss: {
                        withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                            store.updateSettings { $0.hasDismissedPlusCard = true }
                        }
                    }
                )
                .cardRow()
                .transition(.opacity)
            }
        }
        .listStyle(.plain)
        .animation(AppMotion.animation(AppMotion.snappy, reduceMotion: reduceMotion), value: store.revision)
        .sheet(isPresented: $asksWakeTime) {
            WakeTimeSheet(today: today, now: now, meals: store.schedule?.meals(on: today) ?? []) { wake in
                startDay(DayStart.wokeUp(at: wake, source: .morning))
            }
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func hero(_ agenda: DayAgenda?, focus: MealFocus?) -> some View {
        if let schedule = store.schedule {
            switch schedule.phase(on: day) {
            case .notStarted(let start):
                notStarted(start, schedule: schedule)
            case .ended(let lastDay):
                ended(lastDay)
            case .active:
                if isToday {
                    todayHero(agenda, focus: focus)
                } else if day > today, let items = agenda?.items, let first = items.first?.occurrence {
                    NextMealSection(
                        occurrence: first,
                        lead: .firstOfDay,
                        now: now,
                        energyUnit: store.settings.energyUnit,
                        following: items.dropFirst().first?.occurrence,
                        onCook: cookAction(for: first)
                    )
                    .heroRow()
                }
            }
        }
    }

    @ViewBuilder
    private func todayHero(_ agenda: DayAgenda?, focus: MealFocus?) -> some View {
        if let focus {
            switch focus.kind {
            case .now:
                NextMealSection(
                    occurrence: focus.occurrence,
                    lead: .now,
                    now: now,
                    energyUnit: store.settings.energyUnit,
                    following: focus.following,
                    windowEnd: windowEnd(of: focus.occurrence, in: agenda),
                    onDone: { set(.completed, for: focus.occurrence.key) },
                    onSkip: { set(.skipped, for: focus.occurrence.key) },
                    onCook: cookAction(for: focus.occurrence)
                )
                .heroRow()
            case .next:
                NextMealSection(
                    occurrence: focus.occurrence,
                    lead: .next,
                    now: now,
                    energyUnit: store.settings.energyUnit,
                    following: focus.following,
                    onCook: cookAction(for: focus.occurrence)
                )
                .heroRow()
            case .laterDay:
                // The day is over: tomorrow's first meal, calmly, not in the "Now" style.
                TomorrowCard(occurrence: focus.occurrence, today: today)
                    .cardRow()
            }
        }
    }

    /// When a meal on now gives way: its window, or the next meal, or midnight, whichever is first
    /// — the same rule the schedule uses to decide what is on now.
    private func windowEnd(of occurrence: MealOccurrence, in agenda: DayAgenda?) -> Date? {
        guard let schedule = store.schedule else { return nil }
        var end = min(occurrence.date.addingTimeInterval(schedule.currentWindow), occurrence.day.endDate())
        if let later = agenda?.items.map(\.occurrence).first(where: { $0.date > occurrence.date }) {
            end = min(end, later.date)
        }
        return end
    }

    private func cookAction(for occurrence: MealOccurrence) -> (() -> Void)? {
        guard let cook = actions.cook else { return nil }
        let key = occurrence.key
        return { cook(key) }
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
        let firstDay = schedule.occurrences(on: start, states: store.states)
        if let first = firstDay.first {
            NextMealSection(
                occurrence: first,
                lead: .laterDay(today: today),
                now: now,
                energyUnit: store.settings.energyUnit,
                following: firstDay.dropFirst().first
            )
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

    // MARK: Timeline

    @ViewBuilder
    private func timeline(_ agenda: DayAgenda) -> some View {
        let items = agenda.items
        let folded = isToday ? Self.earlierCount(items) : 0
        scheduleHeading(agenda)
        if isToday, store.delay(on: day) > 0 {
            DayShiftBanner(delay: store.delay(on: day), start: store.dayStart(on: day), onUndo: undoShift)
                .cardRow()
                .transition(.opacity)
        }
        if folded > 0 {
            EarlierMealsRow(count: folded, isExpanded: showsEarlier) {
                withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                    showsEarlier.toggle()
                }
            }
        }
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index >= folded || showsEarlier {
                MealTimelineRow(
                    item: item,
                    isFirst: index == 0 && folded == 0,
                    isLast: index == items.count - 1,
                    showsTags: isToday,
                    canMark: day <= today,
                    onSetState: { state in set(state, for: item.occurrence.key) }
                )
            }
        }
        if isToday, agenda.isComplete {
            CompletionFooter()
                .listRowSeparator(.hidden)
                .transition(.opacity)
        }
    }

    /// How many of the day's first meals fold into "Earlier today": all of those before the first
    /// meal still ahead, once more than two of them went by unmarked. Otherwise none.
    static func earlierCount(_ items: [AgendaItem]) -> Int {
        let earlier = items.prefix { !$0.role.isOpenAhead }
        let unmarked = earlier.filter { $0.role == .past }.count
        return unmarked > 2 ? earlier.count : 0
    }

    private func scheduleHeading(_ agenda: DayAgenda) -> some View {
        let count = isToday
            ? String(localized: "today.remaining", defaultValue: "\(agenda.remainingCount) remaining", bundle: .module)
            : String(localized: "today.mealCount", defaultValue: "\(agenda.items.count) meals", bundle: .module)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                scheduleTitle
                Spacer()
                scheduleCount(count)
            }
            VStack(alignment: .leading, spacing: 2) {
                scheduleTitle
                scheduleCount(count)
            }
        }
        .padding(.top, AppSpacing.small)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.screenMargin, bottom: AppSpacing.xxSmall, trailing: AppSpacing.screenMargin))
    }

    private var scheduleTitle: some View {
        Text(LocalizedStringKey(isToday ? "today.schedule.titleToday" : "today.schedule.title"), bundle: .module)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private func scheduleCount(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }

    // MARK: Cards

    /// The assistant's offer, while it is running, and once to say how it went.
    private var showsEstimateCard: Bool {
        guard assistant.isAvailable, store.activePlan != nil else { return false }
        if assistant.planEstimate != nil { return true }
        return !store.settings.hasDismissedEstimateCard && assistant.dishesNeedingEstimates > 0
    }

    /// One offer at a time, and only for someone who has come back: on the free tier, on a second
    /// day of use or later, while nothing else is being suggested.
    private var showsPlusCard: Bool {
        guard assistant.isAvailable, access.tier == .free, !store.settings.hasDismissedPlusCard else { return false }
        guard widgetTip == nil, !showsEstimateCard else { return false }
        let daysUsed = Set(store.states.filter { $0.value != .pending }.map { $0.key.day }).count
        return daysUsed >= 2
    }

    // MARK: Changes

    private func set(_ state: OccurrenceState, for key: OccurrenceKey) {
        let wasCompleted = store.states[key] == .completed
        withAppAnimation(state == .completed ? AppMotion.settle : AppMotion.snappy, reduceMotion: reduceMotion) {
            store.attempt { try store.setState(state, for: key) }
        }
        if state == .completed, !wasCompleted, store.states[key] == .completed {
            onMoment(.done)
        }
    }

    /// The day started: its meals follow `start`. Says how it went, moved or on time.
    private func startDay(_ start: DayStart) {
        withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
            store.attempt { try store.startDay(start, on: today) }
        }
        guard store.dayStart(on: today) != nil else { return }
        let moved = store.delay(on: today)
        onMoment(moved > 0 ? .shifted(minutes: moved) : .onTime)
    }

    /// Late, but the plan's times stay: recorded, so the question is not asked again today.
    private func keepPlannedTimes() {
        guard let first = store.schedule?.meals(on: today).first else { return }
        withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
            store.attempt { try store.startDay(DayStart(firstMeal: first.time, source: .morning), on: today) }
        }
        if store.dayStart(on: today) != nil { onMoment(.kept) }
    }

    private func undoShift() {
        withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
            store.attempt { try store.clearDayStart(on: today) }
        }
        onMoment(.undone)
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

    /// A card on the page: no separator, the screen's margins, a little air above and below.
    func cardRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: AppSpacing.xSmall, leading: AppSpacing.screenMargin, bottom: AppSpacing.xSmall, trailing: AppSpacing.screenMargin))
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
