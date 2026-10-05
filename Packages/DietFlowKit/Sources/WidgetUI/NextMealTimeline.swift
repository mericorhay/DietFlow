import Foundation
import WidgetKit
import Domain

public struct NextMealEntry: TimelineEntry, Sendable {
    public let date: Date
    /// Nil when there is no plan, or nothing left in the window the timeline covers.
    public let meal: ScheduledMeal?

    public init(date: Date, meal: ScheduledMeal?) {
        self.date = date
        self.meal = meal
    }
}

public enum NextMealTimeline {
    /// One entry for now, then one at each meal time that moves the widget on to the meal after it.
    /// WidgetKit plays these back on its own, so the widget stays right without the app running.
    public static func entries(from plan: MealPlan?, now: Date = .now, calendar: Calendar = .current) -> [NextMealEntry] {
        guard let plan else { return [NextMealEntry(date: now, meal: nil)] }
        let upcoming = MealSchedule(plan: plan, calendar: calendar).upcoming(after: now, days: 2)
        guard let first = upcoming.first else { return [NextMealEntry(date: now, meal: nil)] }

        var entries = [NextMealEntry(date: now, meal: first)]
        for (index, current) in upcoming.enumerated() {
            let following = index + 1 < upcoming.count ? upcoming[index + 1] : nil
            entries.append(NextMealEntry(date: current.date, meal: following))
        }
        return entries
    }
}
