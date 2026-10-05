import Foundation
import SwiftUI
import AppCore
import DesignSystem
import Domain

/// What the Plan screen asks the app to do.
public struct PlanActions {
    /// Add a meal on plan day `dayIndex` (zero-based).
    public var addMeal: (Int) -> Void
    public var importPlan: () -> Void
    public var newPlan: () -> Void
    public var editPlan: () -> Void
    public var openSettings: () -> Void

    public init(addMeal: @escaping (Int) -> Void, importPlan: @escaping () -> Void, newPlan: @escaping () -> Void, editPlan: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.addMeal = addMeal
        self.importPlan = importPlan
        self.newPlan = newPlan
        self.editPlan = editPlan
        self.openSettings = openSettings
    }
}

/// The plan itself: every day it covers, each with its meals in order. The place to look over
/// and maintain the schedule — not a spreadsheet, just days and meals.
public struct PlanScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay = CalendarDay.today()
    @State private var confirmsPlanDeletion = false
    @State private var mealPendingDeletion: Meal?
    private let actions: PlanActions

    public init(actions: PlanActions) {
        self.actions = actions
    }

    public var body: some View {
        Group {
            if let plan = store.activePlan, let schedule = store.schedule {
                planList(plan, schedule: schedule)
            } else {
                ScrollView {
                    NoPlanView(onCreate: actions.newPlan, onImport: actions.importPlan)
                        .padding(.top, AppSpacing.xLarge)
                }
            }
        }
        .navigationTitle(store.activePlan.map { Text(verbatim: $0.name) } ?? Text("plan.title", bundle: .module))
        .toolbar { toolbar }
        .confirmationDialog(Text("plan.delete.title", bundle: .module), isPresented: $confirmsPlanDeletion, titleVisibility: .visible) {
            Button(role: .destructive) {
                guard let id = store.activePlan?.id else { return }
                withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                    _ = try? store.deletePlan(id: id)
                }
            } label: {
                Text("plan.delete.confirm", bundle: .module)
            }
        } message: {
            Text("plan.delete.message", bundle: .module)
        }
        .confirmationDialog(
            Text("plan.deleteMeal.title", bundle: .module),
            isPresented: Binding(get: { mealPendingDeletion != nil }, set: { if !$0 { mealPendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: mealPendingDeletion
        ) { meal in
            Button(role: .destructive) {
                withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                    _ = try? store.deleteMeal(id: meal.id)
                }
            } label: {
                Text("plan.deleteMeal.confirm", bundle: .module)
            }
        } message: { _ in
            Text("plan.deleteMeal.message", bundle: .module)
        }
        .sensoryFeedback(.warning, trigger: confirmsPlanDeletion) { _, new in new }
    }

    // MARK: List

    private func planList(_ plan: MealPlan, schedule: MealSchedule) -> some View {
        let today = CalendarDay.today()
        let days = shownDays(plan, schedule: schedule, today: today)
        return ScrollViewReader { proxy in
            List {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(summary(plan, schedule: schedule, today: today))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        DateStrip(
                            days: selectedDay.week(startingOn: store.settings.firstWeekday ?? Calendar.current.firstWeekday),
                            selection: $selectedDay,
                            today: today,
                            isAvailable: { schedule.dayIndex(on: $0) != nil }
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.xxSmall, bottom: 0, trailing: AppSpacing.xxSmall))
                }

                ForEach(days, id: \.self) { day in
                    daySection(day, plan: plan, schedule: schedule, today: today)
                        .id(day)
                }
            }
            .listStyle(.insetGrouped)
            .animation(AppMotion.animation(AppMotion.snappy, reduceMotion: reduceMotion), value: store.revision)
            .onChange(of: selectedDay) { _, day in
                withAnimation(reduceMotion ? nil : AppMotion.settle) {
                    proxy.scrollTo(day, anchor: .top)
                }
            }
        }
    }

    private func daySection(_ day: CalendarDay, plan: MealPlan, schedule: MealSchedule, today: CalendarDay) -> some View {
        let occurrences = schedule.occurrences(on: day, states: store.states)
        let dayIndex = schedule.dayIndex(on: day) ?? 0
        return Section {
            if occurrences.isEmpty {
                HStack {
                    Text("plan.day.empty", bundle: .module)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        actions.addMeal(dayIndex)
                    } label: {
                        Text("plan.day.addMeal", bundle: .module)
                    }
                    .buttonStyle(.borderless)
                }
            }
            ForEach(occurrences) { occurrence in
                NavigationLink(value: MealRoute.occurrence(occurrence.key)) {
                    MealSummaryRow(time: occurrence.date, typeLabel: occurrence.meal.typeLabel, title: occurrence.meal.title) {
                        if occurrence.state == .completed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppColors.success)
                                .accessibilityLabel(Text("plan.meal.done", bundle: .module))
                        } else if occurrence.state == .skipped {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Text("plan.meal.skipped", bundle: .module))
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        mealPendingDeletion = occurrence.meal
                    } label: {
                        Label {
                            Text("plan.meal.delete", bundle: .module)
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        } header: {
            Text(header(day, dayIndex: dayIndex, kind: plan.schedule.kind, today: today))
                .foregroundStyle(day == today ? AnyShapeStyle(AppColors.brandAccent) : AnyShapeStyle(.secondary))
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if store.activePlan != nil {
                    Button {
                        actions.addMeal(store.schedule?.dayIndex(on: selectedDay) ?? 0)
                    } label: {
                        Label { Text("plan.menu.addMeal", bundle: .module) } icon: { Image(systemName: "plus") }
                    }
                }
                Button(action: actions.importPlan) {
                    Label { Text("plan.menu.importPlan", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                }
                Button(action: actions.newPlan) {
                    Label { Text("plan.menu.newPlan", bundle: .module) } icon: { Image(systemName: "calendar.badge.plus") }
                }
            } label: {
                Label { Text("plan.menu.add", bundle: .module) } icon: { Image(systemName: "plus") }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let plan = store.activePlan {
                    Button(action: actions.editPlan) {
                        Label { Text("plan.menu.editPlan", bundle: .module) } icon: { Image(systemName: "slider.horizontal.3") }
                    }
                    if store.plans.count > 1 {
                        Menu {
                            ForEach(store.plans) { summary in
                                Button {
                                    withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
                                        _ = try? store.activatePlan(id: summary.id)
                                    }
                                } label: {
                                    if summary.isActive {
                                        Label(summary.name, systemImage: "checkmark")
                                    } else {
                                        Text(verbatim: summary.name)
                                    }
                                }
                            }
                        } label: {
                            Label { Text("plan.menu.switchPlan", bundle: .module) } icon: { Image(systemName: "arrow.left.arrow.right") }
                        }
                    }
                    ShareLink(item: PlanExport(plan: plan), preview: SharePreview(plan.name)) {
                        Label { Text("plan.menu.export", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
                    }
                }
                Button(action: actions.openSettings) {
                    Label { Text("plan.menu.settings", bundle: .module) } icon: { Image(systemName: "gearshape") }
                }
                if store.activePlan != nil {
                    Divider()
                    Button(role: .destructive) {
                        confirmsPlanDeletion = true
                    } label: {
                        Label { Text("plan.menu.deletePlan", bundle: .module) } icon: { Image(systemName: "trash") }
                    }
                }
            } label: {
                Label { Text("plan.menu.more", bundle: .module) } icon: { Image(systemName: "ellipsis") }
            }
        }
    }

    // MARK: Words

    /// Which days to list: one pass of the plan from today for a repeating plan, otherwise all of it.
    private func shownDays(_ plan: MealPlan, schedule: MealSchedule, today: CalendarDay) -> [CalendarDay] {
        let start = plan.schedule.startDay
        let first = plan.schedule.repeats && start < today ? today : start
        return (0..<plan.schedule.length).map { first.adding(days: $0) }
    }

    private func summary(_ plan: MealPlan, schedule: MealSchedule, today: CalendarDay) -> String {
        let length = plan.schedule.length
        switch schedule.phase(on: today) {
        case .notStarted(let start):
            let date = start.middayDate().formatted(.dateTime.weekday(.wide).month(.wide).day())
            return String(localized: "plan.summary.starts", defaultValue: "Starts \(date)", bundle: .module)
        case .ended(let lastDay):
            let date = lastDay.middayDate().formatted(.dateTime.month(.wide).day())
            return String(localized: "plan.summary.ended", defaultValue: "Ended \(date)", bundle: .module)
        case .active(let index, _):
            if plan.schedule.kind == .fixedDates {
                let first = plan.schedule.startDay.middayDate().formatted(.dateTime.month(.abbreviated).day())
                let last = plan.schedule.startDay.adding(days: length - 1).middayDate().formatted(.dateTime.month(.abbreviated).day())
                return String(localized: "plan.summary.fixed", defaultValue: "\(first) – \(last)", bundle: .module)
            }
            if length == 1 {
                return String(localized: "plan.summary.daily", bundle: .module)
            }
            let day = index + 1
            if plan.schedule.repeats {
                return String(localized: "plan.summary.repeating", defaultValue: "Day \(day) of \(length) · Repeats", bundle: .module)
            }
            return String(localized: "plan.summary.once", defaultValue: "Day \(day) of \(length)", bundle: .module)
        }
    }

    private func header(_ day: CalendarDay, dayIndex: Int, kind: PlanKind, today: CalendarDay) -> String {
        let date = day.middayDate().formatted(.dateTime.weekday(.wide).month(.wide).day())
        if kind == .fixedDates {
            return date
        }
        let number = dayIndex + 1
        return String(localized: "plan.day.header", defaultValue: "Day \(number) · \(date)", bundle: .module)
    }
}
