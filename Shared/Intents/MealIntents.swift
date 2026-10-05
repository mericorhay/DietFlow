import AppIntents
import Foundation
import AppCore
import Domain

// Compiled into both the app and the widget extension: the widget's Done button runs
// MarkMealDoneIntent in the widget's own process, and Shortcuts and Siri run all of them through
// the app. Every intent goes through MealPlanStore, so the widget, the reminders and the Today
// screen stay in step whichever way a change arrives.
//
// The app target defaults to the main actor and the widget target does not, so what App Intents
// reads from any thread (titles, descriptions, `init()`) is marked nonisolated explicitly.
// An intent with parameters cannot be nonisolated as a whole: its parameters are mutable storage.

/// One meal on one day, as Shortcuts and Siri see it.
nonisolated struct MealOccurrenceEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "intent.entity.meal")
    }
    static let defaultQuery = MealOccurrenceQuery()

    /// `OccurrenceKey.description`.
    let id: String
    let title: String
    let typeLabel: String
    let date: Date

    init(id: String, title: String, typeLabel: String, date: Date) {
        self.id = id
        self.title = title
        self.typeLabel = typeLabel
        self.date = date
    }

    init(_ occurrence: MealOccurrence) {
        self.init(id: occurrence.key.description, title: occurrence.meal.title, typeLabel: occurrence.meal.typeLabel, date: occurrence.date)
    }

    init(_ item: WidgetMealItem) {
        self.init(id: item.key.description, title: item.title, typeLabel: item.typeLabel, date: item.date)
    }

    var displayRepresentation: DisplayRepresentation {
        let time = date.formatted(date: .omitted, time: .shortened)
        return DisplayRepresentation(title: "\(title)", subtitle: "\(typeLabel) · \(time)")
    }
}

nonisolated struct MealOccurrenceQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [MealOccurrenceEntity.ID]) async throws -> [MealOccurrenceEntity] {
        let store = MealPlanStore.live()
        return identifiers
            .compactMap { OccurrenceKey($0) }
            .compactMap { store.occurrence(for: $0) }
            .map { MealOccurrenceEntity($0) }
    }

    /// Today's meals that are still open.
    @MainActor
    func suggestedEntities() async throws -> [MealOccurrenceEntity] {
        let store = MealPlanStore.live()
        let items = store.agenda(on: .today())?.items ?? []
        return items.filter { $0.occurrence.isPending }.map { MealOccurrenceEntity($0.occurrence) }
    }
}

nonisolated enum MealTypeOption: String, AppEnum {
    case breakfast
    case snack
    case lunch
    case dinner
    case other

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "intent.entity.mealType")
    }
    static var caseDisplayRepresentations: [MealTypeOption: DisplayRepresentation] {
        [
            .breakfast: DisplayRepresentation(title: "intent.mealType.breakfast"),
            .snack: DisplayRepresentation(title: "intent.mealType.snack"),
            .lunch: DisplayRepresentation(title: "intent.mealType.lunch"),
            .dinner: DisplayRepresentation(title: "intent.mealType.dinner"),
            .other: DisplayRepresentation(title: "intent.mealType.other"),
        ]
    }

    var mealType: MealType {
        MealType(rawValue: rawValue) ?? .other
    }
}

/// Marks a meal done: the one chosen, or the meal that is on now or next.
struct MarkMealDoneIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "intent.markDone.title"
    nonisolated static var description: IntentDescription { IntentDescription("intent.markDone.description") }

    @Parameter(title: "intent.parameter.meal")
    var meal: MealOccurrenceEntity?

    nonisolated init() {}

    init(meal: MealOccurrenceEntity) {
        self.meal = meal
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = MealPlanStore.live()
        let occurrence: MealOccurrence
        if let meal, let key = OccurrenceKey(meal.id), let chosen = store.occurrence(for: key) {
            occurrence = chosen
        } else if let focus = store.focus(), focus.kind != .laterDay {
            occurrence = focus.occurrence
        } else {
            return .result(dialog: IntentDialog("intent.markDone.nothing"))
        }
        try store.markMealCompleted(occurrence.key)
        let title = occurrence.meal.title
        return .result(dialog: IntentDialog(LocalizedStringResource("intent.markDone.result", defaultValue: "\(title) marked done.")))
    }
}

/// Says what to eat next and when.
nonisolated struct ShowNextMealIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.showNext.title"
    static var description: IntentDescription { IntentDescription("intent.showNext.description") }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = MealPlanStore.live()
        guard let focus = store.focus() else {
            let none = String(localized: "intent.showNext.none")
            return .result(value: none, dialog: IntentDialog("\(none)"))
        }
        let occurrence = focus.occurrence
        let type = occurrence.meal.typeLabel
        let title = occurrence.meal.title
        let time = occurrence.date.formatted(date: .omitted, time: .shortened)
        let answer: String
        switch focus.kind {
        case .now:
            answer = String(localized: "intent.showNext.now", defaultValue: "\(type) now: \(title)")
        case .next:
            answer = String(localized: "intent.showNext.next", defaultValue: "\(type) at \(time): \(title)")
        case .laterDay:
            let day = occurrence.date.formatted(.dateTime.weekday(.wide))
            answer = String(localized: "intent.showNext.later", defaultValue: "\(type) on \(day) at \(time): \(title)")
        }
        return .result(value: answer, dialog: IntentDialog("\(answer)"))
    }
}

/// Adds a meal to the active plan, on the plan day that falls on the chosen date.
struct AddMealIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "intent.addMeal.title"
    nonisolated static var description: IntentDescription { IntentDescription("intent.addMeal.description") }

    @Parameter(title: "intent.parameter.mealName")
    var mealName: String

    @Parameter(title: "intent.parameter.mealType", default: .lunch)
    var type: MealTypeOption

    @Parameter(title: "intent.parameter.time")
    var time: Date

    @Parameter(title: "intent.parameter.day")
    var day: Date?

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Shortcuts can pass an empty name; ask for one rather than add a meal with nothing to show.
        guard let name = mealName.trimmedNonEmpty else { throw $mealName.needsValueError() }
        let store = MealPlanStore.live()
        guard let plan = store.activePlan, let schedule = store.schedule else {
            return .result(dialog: IntentDialog("intent.addMeal.noPlan"))
        }
        let target = CalendarDay(day ?? .now)
        guard let dayIndex = schedule.dayIndex(on: target) else {
            return .result(dialog: IntentDialog("intent.addMeal.outsidePlan"))
        }
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        let meal = Meal(
            dayIndex: dayIndex,
            type: type.mealType,
            time: TimeOfDay(hour: clock.hour ?? 12, minute: clock.minute ?? 0),
            title: name
        )
        // The store bounds what it is given; say back the name as it was stored.
        let title = try store.addMeal(meal, toPlan: plan.id).title
        return .result(dialog: IntentDialog(LocalizedStringResource("intent.addMeal.result", defaultValue: "Added \(title).")))
    }
}
