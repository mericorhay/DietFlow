import Foundation

/// A meal placed on a real date.
public struct ScheduledMeal: Hashable, Sendable {
    public let meal: Meal
    public let date: Date

    public init(meal: Meal, date: Date) {
        self.meal = meal
        self.date = date
    }
}

/// Turns a repeating plan into dated meals. The widget, the Today screen and the reminders all ask
/// this one type, so they cannot disagree about what comes next.
public struct MealSchedule: Sendable {
    public let plan: MealPlan
    public var calendar: Calendar

    public init(plan: MealPlan, calendar: Calendar = .current) {
        self.plan = plan
        self.calendar = calendar
    }

    /// The day of the cycle that falls on `date`, or nil before the plan starts.
    public func day(on date: Date) -> DayPlan? {
        guard !plan.days.isEmpty else { return nil }
        let start = calendar.startOfDay(for: plan.startDate)
        let target = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        guard offset >= 0 else { return nil }
        return plan.days[offset % plan.days.count]
    }

    /// That day's meals in clock order.
    public func meals(on date: Date) -> [ScheduledMeal] {
        guard let day = day(on: date) else { return [] }
        let startOfDay = calendar.startOfDay(for: date)
        return day.meals
            .sorted { $0.time < $1.time }
            .compactMap { meal in
                calendar
                    .date(bySettingHour: meal.time.hour, minute: meal.time.minute, second: 0, of: startOfDay)
                    .map { ScheduledMeal(meal: meal, date: $0) }
            }
    }

    /// Meals strictly after `date`, looking `days` calendar days ahead including today.
    public func upcoming(after date: Date, days: Int = 2) -> [ScheduledMeal] {
        var result: [ScheduledMeal] = []
        for offset in 0..<max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            result += meals(on: day).filter { $0.date > date }
        }
        return result
    }

    public func next(after date: Date) -> ScheduledMeal? {
        upcoming(after: date, days: 2).first
    }
}
