import Foundation
import WidgetKit
import Domain

/// One timeline entry: from `date` on, the widget shows `content`.
public struct MealWidgetEntry: TimelineEntry, Sendable {
    public let date: Date
    public let content: WidgetContent
    public let preferences: WidgetPreferences
    /// The moment `content` describes. The same as `date`, except for the gallery's example,
    /// which always shows lunchtime whenever it is looked at.
    public let reference: Date
    /// Countdowns are worked out once from `reference` instead of running with the clock: the
    /// gallery's example would otherwise count towards a lunch that is not today's.
    public let isFrozen: Bool
    /// 0–100: how much it matters that this widget is on top of a Smart Stack from `date`.
    public let score: Double

    public init(date: Date, content: WidgetContent, preferences: WidgetPreferences, reference: Date? = nil, isFrozen: Bool = false, score: Double = 0) {
        self.date = date
        self.content = content
        self.preferences = preferences
        self.reference = reference ?? date
        self.isFrozen = isFrozen
        self.score = score
    }

    /// Lets a Smart Stack bring the widget to the top around mealtimes.
    public var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: Float(score))
    }

    /// The sample plan on its first day: onboarding's example, at any time of that day.
    public static func sample(now: Date = .now, preferences: WidgetPreferences = WidgetPreferences()) -> MealWidgetEntry {
        let snapshot = WidgetSnapshot.sample(now: now, preferences: preferences)
        let content = WidgetTimelineBuilder.content(for: snapshot, at: now)
        return MealWidgetEntry(date: now, content: content, preferences: preferences, score: WidgetTimelineBuilder.relevance(of: content, at: now))
    }

    /// The entry for `now` from a snapshot, for previews inside the app.
    public static func current(for snapshot: WidgetSnapshot?, now: Date = .now) -> MealWidgetEntry {
        let content = WidgetTimelineBuilder.content(for: snapshot, at: now)
        return MealWidgetEntry(date: now, content: content, preferences: snapshot?.preferences ?? WidgetPreferences(), score: WidgetTimelineBuilder.relevance(of: content, at: now))
    }

    /// What the widget gallery shows before there is a plan: an example day in the person's
    /// language, at 12:55 with lunch on now, in the colour they chose. Fixed, so the gallery
    /// always shows the widget at its best moment rather than at whatever time it is opened.
    public static func gallery(preferences: WidgetPreferences = WidgetPreferences(), now: Date = .now, timeZone: TimeZone = .current) -> MealWidgetEntry {
        let today = CalendarDay(now, in: timeZone)
        let plan = WidgetGallery.plan(today: today)
        let lunchtime = TimeOfDay(hour: 12, minute: 55).date(on: today, in: timeZone)
        let schedule = MealSchedule(plan: plan, timeZone: timeZone, currentWindow: preferences.mealWindow)
        var states: OccurrenceStates = [:]
        if let breakfast = schedule.occurrences(on: today).first {
            states[breakfast.key] = .completed
        }
        let snapshot = WidgetSnapshot(plan: plan, states: states, preferences: preferences, generatedAt: lunchtime, timeZone: timeZone)
        let content = WidgetTimelineBuilder.content(for: snapshot, at: lunchtime, timeZone: timeZone)
        return MealWidgetEntry(date: now, content: content, preferences: preferences, reference: lunchtime, isFrozen: true)
    }
}

/// The example day of the widget gallery, in the language the widget is drawn in.
enum WidgetGallery {
    static func plan(today: CalendarDay) -> MealPlan {
        // Day 3 of a week: the header reads like one in use.
        let start = today.adding(days: -2)
        let meals = (0..<7).flatMap { day in
            [
                Meal(dayIndex: day, type: .breakfast, time: TimeOfDay(hour: 8, minute: 30), title: String(localized: "widget.gallery.breakfast", bundle: .module), nutrition: Nutrition(calories: 380)),
                Meal(dayIndex: day, type: .lunch, time: TimeOfDay(hour: 12, minute: 30), title: String(localized: "widget.gallery.lunch", bundle: .module), nutrition: Nutrition(calories: 520)),
                Meal(dayIndex: day, type: .snack, time: TimeOfDay(hour: 16, minute: 0), title: String(localized: "widget.gallery.snack", bundle: .module), nutrition: Nutrition(calories: 190)),
                Meal(dayIndex: day, type: .dinner, time: TimeOfDay(hour: 19, minute: 30), title: String(localized: "widget.gallery.dinner", bundle: .module), nutrition: Nutrition(calories: 560)),
            ]
        }
        return MealPlan(
            name: String(localized: "widget.gallery.planName", bundle: .module),
            schedule: PlanSchedule(startDay: start, length: 7, repeats: true),
            meals: meals
        )
    }
}

/// Turns the shared snapshot into WidgetKit entries. The widget extension reads the file and calls
/// this; everything about what to show when is decided in `WidgetTimelineBuilder`, where it is tested.
public enum MealWidgetTimeline {
    public static func entries(snapshot: WidgetSnapshot?, isUnreadable: Bool, now: Date = .now, timeZone: TimeZone = .current) -> [MealWidgetEntry] {
        let preferences = snapshot?.preferences ?? WidgetPreferences()
        if isUnreadable {
            return [MealWidgetEntry(date: now, content: .needsRefresh, preferences: preferences)]
        }
        return WidgetTimelineBuilder.moments(for: snapshot, from: now, timeZone: timeZone).map {
            MealWidgetEntry(date: $0.date, content: $0.content, preferences: preferences, score: $0.relevance)
        }
    }

    /// When WidgetKit should ask for a fresh timeline: well before `entries` run out.
    public static func reloadDate(after entries: [MealWidgetEntry], from now: Date = .now) -> Date {
        WidgetTimelineBuilder.reloadDate(after: entries.map { WidgetMoment(date: $0.date, content: $0.content, relevance: $0.score) }, from: now)
    }
}
