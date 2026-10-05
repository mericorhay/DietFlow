import Foundation

/// What a new meal on a day most likely is, so the form opens on it: the first meal of an empty
/// day is breakfast; otherwise the next sitting, about three hours after the day's last meal.
public enum MealSuggestion {
    public static func next(after meals: [Meal]) -> (type: MealType, time: TimeOfDay) {
        guard let last = meals.map(\.time).max() else {
            return (.breakfast, MealType.breakfast.typicalTime)
        }
        let latest = 22 * 60
        var minutes = last.minutesSinceMidnight + 3 * 60
        // On the half hour, and not after ten in the evening unless the day already runs later.
        minutes = (minutes + 15) / 30 * 30
        if minutes > latest {
            minutes = max(latest, last.minutesSinceMidnight + 30)
        }
        let time = TimeOfDay(minutesSinceMidnight: min(minutes, 23 * 60 + 30))
        return (MealType.suggested(for: time), time)
    }
}
