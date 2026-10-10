import Foundation
import SwiftUI
import UIKit
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
    /// The assistant writing a plan, and putting a pasted list in order; nil without the assistant.
    public var writePlan: (() -> Void)?
    public var organizeList: (() -> Void)?

    public init(
        addMeal: @escaping (Int) -> Void,
        importPlan: @escaping () -> Void,
        newPlan: @escaping () -> Void,
        editPlan: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        writePlan: (() -> Void)? = nil,
        organizeList: (() -> Void)? = nil
    ) {
        self.addMeal = addMeal
        self.importPlan = importPlan
        self.newPlan = newPlan
        self.editPlan = editPlan
        self.openSettings = openSettings
        self.writePlan = writePlan
        self.organizeList = organizeList
    }
}

/// The plan itself: every day it covers, each with its meals in order. The place to look over
/// and maintain the schedule — not a spreadsheet, just days and meals. When meals have no figures,
/// the assistant offers to fill them in for the whole plan at once.
public struct PlanScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(MealAssistantModel.self) private var assistant
    @Environment(AccessModel.self) private var access
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmsPlanDeletion = false
    @State private var mealPendingDeletion: Meal?
    /// The consent alert, before the first estimate sends anything.
    @State private var asksConsent = false
    /// Counts estimates that filled something in, for the success haptic.
    @State private var estimatesLanded = 0
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
                    NoPlanView(onCreate: actions.newPlan, onImport: actions.importPlan, onWritePlan: actions.writePlan, onOrganizeList: actions.organizeList)
                        .padding(.top, AppSpacing.xLarge)
                }
            }
        }
        .navigationTitle(Text("plan.title", bundle: .module))
        .toolbar { toolbar }
        .confirmationDialog(Text("plan.delete.title", bundle: .module), isPresented: $confirmsPlanDeletion, titleVisibility: .visible) {
            Button(role: .destructive) {
                guard let id = store.activePlan?.id else { return }
                withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                    store.attempt { try store.deletePlan(id: id) }
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
                    store.attempt { try store.deleteMeal(id: meal.id) }
                }
            } label: {
                Text("plan.deleteMeal.confirm", bundle: .module)
            }
        } message: { _ in
            Text("plan.deleteMeal.message", bundle: .module)
        }
        .assistantConsent(isPresented: $asksConsent) {
            assistant.allowSharing()
            estimatePlan()
        }
        .sensoryFeedback(.warning, trigger: confirmsPlanDeletion) { _, new in new }
        .sensoryFeedback(.success, trigger: estimatesLanded)
        .task(id: assistant.planEstimate) {
            // A finished estimate says so for a moment, then the card steps aside.
            guard case .some(.finished) = assistant.planEstimate else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                assistant.dismissPlanEstimate()
            }
        }
    }

    // MARK: List

    private func planList(_ plan: MealPlan, schedule: MealSchedule) -> some View {
        let today = CalendarDay.today()
        let days = shownDays(plan, schedule: schedule, today: today)
        return ScrollViewReader { proxy in
            List {
                Section {
                    planHeader(plan, schedule: schedule, today: today)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.xxSmall, bottom: AppSpacing.xSmall, trailing: AppSpacing.xxSmall))
                    if showsEstimate {
                        estimateRow(plan)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: AppSpacing.xxSmall, leading: 0, bottom: AppSpacing.xxSmall, trailing: 0))
                            .transition(.opacity)
                    }
                }

                ForEach(days, id: \.self) { day in
                    daySection(day, plan: plan, schedule: schedule, today: today)
                        .id(day)
                }
            }
            .listStyle(.insetGrouped)
            .animation(AppMotion.animation(AppMotion.snappy, reduceMotion: reduceMotion), value: store.revision)
            .animation(AppMotion.animation(AppMotion.settle, reduceMotion: reduceMotion), value: assistant.planEstimate)
            .onAppear {
                // A plan that started days ago opens on today, not on its first day.
                if let first = days.first, first < today, days.contains(today) {
                    proxy.scrollTo(today, anchor: .top)
                }
            }
        }
    }

    /// The plan's name, wrapping as long as it needs, and where the plan stands today.
    private func planHeader(_ plan: MealPlan, schedule: MealSchedule, today: CalendarDay) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(verbatim: plan.name)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(summary(plan, schedule: schedule, today: today))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func daySection(_ day: CalendarDay, plan: MealPlan, schedule: MealSchedule, today: CalendarDay) -> some View {
        let occurrences = schedule.occurrences(on: day, states: store.states)
        let dayIndex = schedule.dayIndex(on: day) ?? 0
        let title = header(day, dayIndex: dayIndex, kind: plan.schedule.kind, today: today)
        let isToday = day == today
        let shownTitle = isToday ? String(localized: "plan.day.today", defaultValue: "Today · \(title)", bundle: .module) : title
        let total = dayTotal(occurrences)
        let isPlanEstimating = assistant.planEstimate?.isRunning == true
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
                    .tint(AppColors.brandAccent)
                }
            }
            ForEach(occurrences) { occurrence in
                NavigationLink(value: MealRoute.occurrence(occurrence.key)) {
                    PlanMealRow(
                        occurrence: occurrence,
                        energy: store.settings.energyUnit.format(occurrence.meal.nutrition),
                        isEstimating: occurrence.meal.lacksNutrition
                            && (isPlanEstimating || assistant.estimatingMeals.contains(occurrence.meal.id)),
                        movedFrom: movedFrom(occurrence)
                    )
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
            HStack(alignment: .center, spacing: AppSpacing.xSmall) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shownTitle)
                        .foregroundStyle(isToday ? AnyShapeStyle(AppColors.brandAccent) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    if let total {
                        Text(total)
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AppSpacing.xSmall)
                // Adding a meal to this very day, wherever the list is scrolled.
                Button {
                    actions.addMeal(dayIndex)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: AppSpacing.minimumHitTarget, minHeight: AppSpacing.minimumHitTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .tint(AppColors.brandAccent)
                .accessibilityLabel(Text(String(localized: "plan.day.addMealTo", defaultValue: "Add meal to \(title)", bundle: .module)))
            }
            .textCase(nil)
        }
    }

    /// "Moved from 08:00" for a meal the day's late start moved.
    private func movedFrom(_ occurrence: MealOccurrence) -> String? {
        guard occurrence.isMoved else { return nil }
        let planned = occurrence.meal.time.date(on: occurrence.day).formatted(.dateTime.hour().minute())
        return String(localized: "plan.meal.moved", defaultValue: "Moved from \(planned)", bundle: .module)
    }

    /// The day's energy, once every meal of the day has a figure: a total missing a meal would
    /// read as the day's and be wrong. "≈" when any of it is an estimate.
    private func dayTotal(_ occurrences: [MealOccurrence]) -> String? {
        guard !occurrences.isEmpty else { return nil }
        var calories = 0
        var estimated = false
        for occurrence in occurrences {
            guard let value = occurrence.meal.nutrition.calories else { return nil }
            calories += value
            estimated = estimated || occurrence.meal.nutrition.isEstimated
        }
        return store.settings.energyUnit.format(Nutrition(calories: calories, estimated: estimated))
    }

    // MARK: Estimate

    /// The card shows while there is something to fill in, and stays to say how it went.
    private var showsEstimate: Bool {
        assistant.isAvailable && (assistant.planEstimate != nil || assistant.dishesNeedingEstimates > 0)
    }

    /// Meals of the plan with no figures of their own.
    private func mealsWithoutNutrition(_ plan: MealPlan) -> Int {
        plan.meals.filter { $0.dayIndex < plan.schedule.length && $0.lacksNutrition }.count
    }

    @ViewBuilder
    private func estimateRow(_ plan: MealPlan) -> some View {
        let count = mealsWithoutNutrition(plan)
        switch assistant.planEstimate {
        case .some(.running(let dishes)):
            EstimateStatus(symbol: "sparkles", isWorking: true) {
                Text(String(localized: "plan.estimate.running", defaultValue: "The assistant is reading \(dishes) dishes…", bundle: .module))
            } detail: {
                Text("plan.estimate.runningDetail", bundle: .module)
            }
        case .some(.finished(let meals)):
            EstimateStatus(symbol: "checkmark.circle.fill", symbolTint: AppColors.success) {
                Text(String(localized: "plan.estimate.finished", defaultValue: "Added nutrition to \(meals) meals.", bundle: .module))
            } detail: {
                Text("plan.estimate.finishedDetail", bundle: .module)
            } accessory: {
                dismissButton
            }
        case .some(.failed(let error)):
            EstimateStatus(symbol: "exclamationmark.circle", symbolTint: .secondary) {
                Text(failureMessage(error))
            } detail: {
                Button {
                    estimatePlan()
                } label: {
                    Label {
                        Text("plan.estimate.retry", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.brandAccent)
                    .frame(minHeight: AppSpacing.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            } accessory: {
                dismissButton
            }
        case nil:
            AssistantCard(
                title: Text(String(localized: "plan.estimate.title", defaultValue: "Add Nutrition to \(count) Meals", bundle: .module)),
                subtitle: Text("plan.estimate.subtitle", bundle: .module),
                badge: estimateBadge,
                style: .prominent
            ) {
                estimatePlan()
            }
        }
    }

    private var dismissButton: some View {
        Button {
            withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                assistant.dismissPlanEstimate()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: AppSpacing.minimumHitTarget, minHeight: AppSpacing.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("plan.estimate.dismiss", bundle: .module))
    }

    /// What the estimate costs, said before it is asked for: one use for the whole plan.
    private var estimateBadge: Text {
        switch AssistantCost.caption(remaining: assistant.remaining(.aiNutrition), tier: access.tier) {
        case .left(let count):
            Text(String(localized: "plan.estimate.costLeft", defaultValue: "1 AI use for the whole plan · \(count) left this month", bundle: .module))
        case .plus:
            Text("plan.estimate.costPlus", bundle: .module)
        case nil:
            Text("plan.estimate.costOne", bundle: .module)
        }
    }

    private func estimatePlan() {
        // A used-up allowance opens the Plus screen straight away, rather than first asking to share.
        guard assistant.canAsk(.aiNutrition) else {
            access.check(.aiNutrition)
            return
        }
        Task {
            switch await assistant.estimateActivePlan() {
            case .success(let filled):
                if filled > 0 { estimatesLanded += 1 }
            case .needsConsent:
                asksConsent = true
            case .failed, .refused, .unavailable:
                // A failure shows in the card (`planEstimate`); a refusal opens the Plus screen or
                // the "comes back on" alert from the app.
                break
            }
        }
    }

    private func failureMessage(_ error: AssistantError) -> String {
        switch error {
        case .offline:
            String(localized: "plan.estimate.failed.offline", bundle: .module)
        case .busy:
            String(localized: "plan.estimate.failed.busy", bundle: .module)
        case .dailyLimit:
            String(localized: "plan.estimate.failed.dailyLimit", bundle: .module)
        case .tooLong, .noPlan, .unavailable:
            String(localized: "plan.estimate.failed.other", bundle: .module)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if store.activePlan != nil {
                    Button {
                        actions.addMeal(store.schedule?.dayIndex(on: .today()) ?? 0)
                    } label: {
                        Label { Text("plan.menu.addMeal", bundle: .module) } icon: { Image(systemName: "plus") }
                    }
                }
                if let writePlan = actions.writePlan {
                    Button(action: writePlan) {
                        Label { Text("plan.menu.writePlan", bundle: .module) } icon: { Image(systemName: "sparkles") }
                    }
                }
                if let organizeList = actions.organizeList {
                    Button(action: organizeList) {
                        Label { Text("plan.menu.organizeList", bundle: .module) } icon: { Image(systemName: "wand.and.stars") }
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
                                        store.attempt { try store.activatePlan(id: summary.id) }
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

// MARK: Rows

/// One meal in the plan: its sitting's glyph, time and name, what it holds, and what happened to it.
private struct PlanMealRow: View {
    let occurrence: MealOccurrence
    /// "510 kcal", "≈ 510 kcal", or nil when the meal has no energy figure.
    let energy: String?
    /// The assistant is working its figures out: a placeholder shimmers where they will be.
    let isEstimating: Bool
    let movedFrom: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 34

    var body: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        HStack(alignment: .center, spacing: AppSpacing.small) {
            if !isLarge {
                MealGlyph(occurrence.meal.type, size: glyphSize)
                    .symbolEffect(.bounce, value: occurrence.state)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(verbatim: occurrence.meal.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let movedFrom {
                    Label {
                        Text(movedFrom)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if isLarge {
                    facts
                }
            }
            Spacer(minLength: 0)
            if !isLarge {
                facts
            }
        }
        .padding(.vertical, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        let time = occurrence.date.formatted(.dateTime.hour().minute())
        let sitting = occurrence.meal.typeLabel
        return String(localized: "plan.meal.meta", defaultValue: "\(time) · \(sitting)", bundle: .module)
    }

    /// The energy figure and the meal's state.
    private var facts: some View {
        HStack(spacing: AppSpacing.xSmall) {
            if isEstimating {
                Text(verbatim: "≈ 000 kcal")
                    .font(.footnote.weight(.medium))
                    .assistantShimmer(true)
            } else if let energy {
                Text(energy)
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            switch occurrence.state {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                    .accessibilityLabel(Text("plan.meal.done", bundle: .module))
            case .skipped:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("plan.meal.skipped", bundle: .module))
            case .pending:
                EmptyView()
            }
        }
    }
}

/// How the plan's estimate is going, in place of the card that started it.
private struct EstimateStatus<Title: View, Detail: View, Accessory: View>: View {
    private let symbol: String
    private let symbolTint: Color
    private let isWorking: Bool
    private let title: Title
    private let detail: Detail
    private let accessory: Accessory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        symbol: String,
        symbolTint: Color = AppColors.brandAccent,
        isWorking: Bool = false,
        @ViewBuilder title: () -> Title,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.symbol = symbol
        self.symbolTint = symbolTint
        self.isWorking = isWorking
        self.title = title()
        self.detail = detail()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolTint)
                .symbolEffect(.pulse, options: .repeating, isActive: isWorking && !reduceMotion)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                title
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            accessory
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .strokeBorder(AppColors.assistantGradient.opacity(0.6), lineWidth: 1)
        }
    }
}

extension EstimateStatus where Accessory == EmptyView {
    init(
        symbol: String,
        symbolTint: Color = AppColors.brandAccent,
        isWorking: Bool = false,
        @ViewBuilder title: () -> Title,
        @ViewBuilder detail: () -> Detail
    ) {
        self.init(symbol: symbol, symbolTint: symbolTint, isWorking: isWorking, title: title, detail: detail) { EmptyView() }
    }
}
