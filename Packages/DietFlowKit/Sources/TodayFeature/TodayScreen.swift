import Foundation
import SwiftUI
import AppCore
import DesignSystem
import Domain

/// What the Today screen asks the app to do. The app decides where it leads.
public struct TodayActions {
    public var openSettings: () -> Void
    public var createPlan: () -> Void
    public var importPlan: () -> Void
    public var addMeal: (CalendarDay) -> Void

    public init(openSettings: @escaping () -> Void, createPlan: @escaping () -> Void, importPlan: @escaping () -> Void, addMeal: @escaping (CalendarDay) -> Void) {
        self.openSettings = openSettings
        self.createPlan = createPlan
        self.importPlan = importPlan
        self.addMeal = addMeal
    }
}

/// The screen that answers one question at a glance: what am I eating next? A week strip and a
/// day pager on top, the meal in front, then the day's timeline.
public struct TodayScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay = CalendarDay.today()
    private let actions: TodayActions

    public init(actions: TodayActions) {
        self.actions = actions
    }

    public var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .navigationTitle(Text("today.title", bundle: .module))
        .toolbar { toolbar }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let today = CalendarDay(now)
        if let schedule = store.schedule {
            VStack(alignment: .leading, spacing: 0) {
                header(today: today, schedule: schedule)
                DayPager(days: pagerDays(around: today), selection: $selectedDay) { day in
                    DayPage(day: day, today: today, now: now, actions: actions)
                }
            }
            .sensoryFeedback(trigger: completedCount(on: today)) { old, new in
                new > old ? .success : nil
            }
            .onChange(of: today) { previous, current in
                // At midnight, someone looking at today keeps looking at today.
                if selectedDay == previous { selectedDay = current }
            }
        } else {
            ScrollView {
                NoPlanView(onCreate: actions.createPlan, onImport: actions.importPlan)
                    .padding(.top, AppSpacing.xLarge)
            }
        }
    }

    private func header(today: CalendarDay, schedule: MealSchedule) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(selectedDay.middayDate(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
                .accessibilityAddTraits(.isHeader)
            DateStrip(
                days: selectedDay.week(startingOn: firstWeekday),
                selection: $selectedDay,
                today: today,
                isAvailable: { schedule.dayIndex(on: $0) != nil }
            )
        }
        .padding(.horizontal, AppSpacing.screenMargin)
        .padding(.bottom, AppSpacing.xxSmall)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if store.schedule != nil, selectedDay != CalendarDay.today() {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
                        selectedDay = .today()
                    }
                } label: {
                    Text("today.jumpToToday", bundle: .module)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: actions.openSettings) {
                Label {
                    Text("today.settings", bundle: .module)
                } icon: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }

    private var firstWeekday: Int {
        store.settings.firstWeekday ?? Calendar.current.firstWeekday
    }

    /// A month back and two ahead, always including the selected day.
    private func pagerDays(around today: CalendarDay) -> [CalendarDay] {
        let first = min(today.adding(days: -31), selectedDay)
        let last = max(today.adding(days: 62), selectedDay)
        return (0...first.days(to: last)).map { first.adding(days: $0) }
    }

    private func completedCount(on day: CalendarDay) -> Int {
        store.states.filter { $0.key.day == day && $0.value == .completed }.count
    }
}

/// Days side by side, one screen wide; the outgoing day follows the finger and the next one comes
/// in with it. Native paging, so it feels like the rest of the system.
struct DayPager<Page: View>: View {
    let days: [CalendarDay]
    @Binding var selection: CalendarDay
    @ViewBuilder let page: (CalendarDay) -> Page

    @State private var position: CalendarDay?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    page(day)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position)
        .onAppear {
            position = selection
        }
        .onChange(of: position) { _, newValue in
            if let newValue, newValue != selection {
                selection = newValue
            }
        }
        .onChange(of: selection) { _, newValue in
            guard position != newValue else { return }
            withAnimation(reduceMotion ? nil : AppMotion.settle) {
                position = newValue
            }
        }
    }
}
