import Foundation
import SwiftUI
import AppCore
import DesignSystem
import Domain

/// Every imported plan stops here before it is saved: its name, when it starts, whether it
/// repeats, every meal by day, and anything that had to be filled in or left out.
struct ImportReviewScreen: View {
    @State private var name: String
    @State private var startDate: Date
    @State private var repeats: Bool
    private let draft: ImportedPlanDraft
    private let onSave: (MealPlan) -> Void

    init(draft: ImportedPlanDraft, onSave: @escaping (MealPlan) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.plan.name)
        _startDate = State(initialValue: draft.plan.schedule.startDay.middayDate())
        _repeats = State(initialValue: draft.plan.schedule.repeats)
    }

    var body: some View {
        let plan = draft.plan
        let startDay = CalendarDay(startDate)
        List {
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    TextField(text: $name) {
                        Text("import.review.name", bundle: .module)
                    }
                    .font(.title2.weight(.bold))
                    Text(summary(plan))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.xxSmall, bottom: AppSpacing.xxSmall, trailing: AppSpacing.xxSmall))
            }

            Section {
                DatePicker(selection: $startDate, displayedComponents: .date) {
                    Text("import.review.start", bundle: .module)
                }
                if plan.schedule.kind == .cycle {
                    Toggle(isOn: $repeats) {
                        Text(String(localized: "import.review.repeat", defaultValue: "Repeat after day \(plan.schedule.length)", bundle: .module))
                    }
                }
            }

            if !draft.issues.isEmpty {
                Section {
                    ForEach(Array(draft.issues.enumerated()), id: \.offset) { _, issue in
                        Label {
                            Text(ImportIssueText.message(for: issue))
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("import.review.checkHeader", bundle: .module)
                }
            }

            ForEach(0..<plan.schedule.length, id: \.self) { index in
                let meals = plan.meals(onDayIndex: index)
                if !meals.isEmpty {
                    Section {
                        ForEach(meals) { meal in
                            MealSummaryRow(
                                time: meal.time.date(on: startDay.adding(days: index)),
                                typeLabel: meal.typeLabel,
                                title: meal.title,
                                note: draft.mealsWithAssignedTimes.contains(meal.id) ? String(localized: "import.review.timeAdded", bundle: .module) : nil,
                                noteIsWarning: true
                            )
                        }
                    } header: {
                        Text(dayHeader(index, startDay: startDay, kind: plan.schedule.kind))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("import.review.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                var plan = draft.plan
                plan.name = name.trimmedNonEmpty ?? plan.name
                plan.schedule = PlanSchedule(kind: plan.schedule.kind, startDay: CalendarDay(startDate), length: plan.schedule.length, repeats: repeats)
                onSave(plan)
            } label: {
                Text("import.review.save", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.brandAccent)
            .controlSize(.large)
            .padding(.horizontal, AppSpacing.screenMargin)
            .padding(.vertical, AppSpacing.small)
            .background(.bar)
        }
    }

    private func summary(_ plan: MealPlan) -> String {
        let days = String(localized: "import.review.days", defaultValue: "\(plan.schedule.length) days", bundle: .module)
        let meals = String(localized: "import.review.meals", defaultValue: "\(plan.mealCount) meals", bundle: .module)
        return String(localized: "import.review.summary", defaultValue: "\(days) · \(meals)", bundle: .module)
    }

    private func dayHeader(_ index: Int, startDay: CalendarDay, kind: PlanKind) -> String {
        let date = startDay.adding(days: index).middayDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if kind == .fixedDates {
            return date
        }
        let number = index + 1
        return String(localized: "import.review.dayHeader", defaultValue: "Day \(number) · \(date)", bundle: .module)
    }
}

/// What each import issue says on the review screen.
enum ImportIssueText {
    static func message(for issue: ImportIssue) -> String {
        switch issue {
        case .timeMissing(let day, let title, let assigned):
            let time = assigned.date(on: .today()).formatted(.dateTime.hour().minute())
            return String(localized: "import.issue.timeMissing", defaultValue: "Day \(day): “\(title)” had no time, so it is set to \(time).", bundle: .module)
        case .timeUnreadable(let day, let title, let text, let assigned):
            let time = assigned.date(on: .today()).formatted(.dateTime.hour().minute())
            return String(localized: "import.issue.timeUnreadable", defaultValue: "Day \(day): “\(text)” is not a time, so “\(title)” is set to \(time).", bundle: .module)
        case .untitledMealDropped(let day):
            return String(localized: "import.issue.untitled", defaultValue: "Day \(day): a meal without a name was left out.", bundle: .module)
        case .nutritionDropped(let day, let title):
            return String(localized: "import.issue.nutrition", defaultValue: "Day \(day): numbers for “\(title)” looked wrong and were left out.", bundle: .module)
        case .startDateUnreadable(let text):
            return String(localized: "import.issue.startDate", defaultValue: "“\(text)” is not a date, so the plan starts today.", bundle: .module)
        case .dayOutOfRange(let day):
            return String(localized: "import.issue.dayOutOfRange", defaultValue: "Day \(day) is outside the plan and was left out.", bundle: .module)
        case .newerFormat:
            return String(localized: "import.issue.newerFormat", bundle: .module)
        }
    }
}
