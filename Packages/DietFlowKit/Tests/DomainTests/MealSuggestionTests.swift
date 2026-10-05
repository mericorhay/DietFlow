import Foundation
import Testing
import Domain

struct MealSuggestionTests {
    @Test func anEmptyDayStartsWithBreakfast() {
        let suggestion = MealSuggestion.next(after: [])
        #expect(suggestion.type == .breakfast)
        #expect(suggestion.time == MealType.breakfast.typicalTime)
    }

    @Test func theNextMealComesAboutThreeHoursLater() {
        let breakfast = MealSuggestion.next(after: [meal(0, .breakfast, 8, 0, "Eggs")])
        #expect(breakfast.time == TimeOfDay(hour: 11, minute: 0))
        #expect(breakfast.type == .snack)

        let lunch = MealSuggestion.next(after: [meal(0, .breakfast, 8, 0, "Eggs"), meal(0, .snack, 10, 40, "Nuts")])
        #expect(lunch.time == TimeOfDay(hour: 13, minute: 30))
        #expect(lunch.type == .lunch)

        let dinner = MealSuggestion.next(after: [meal(0, .lunch, 15, 50, "Soup")])
        #expect(dinner.time == TimeOfDay(hour: 19, minute: 0))
        #expect(dinner.type == .dinner)
    }

    @Test func aLateDayStaysInTheEvening() {
        let suggestion = MealSuggestion.next(after: [meal(0, .dinner, 21, 0, "Fish")])
        #expect(suggestion.time == TimeOfDay(hour: 22, minute: 0))
        #expect(suggestion.type == .snack)
        let later = MealSuggestion.next(after: [meal(0, .snack, 23, 15, "Tea")])
        #expect(later.time == TimeOfDay(hour: 23, minute: 30))
    }

    @Test func typesFollowTheClock() {
        #expect(MealType.suggested(for: TimeOfDay(hour: 7, minute: 30)) == .breakfast)
        #expect(MealType.suggested(for: TimeOfDay(hour: 11, minute: 0)) == .snack)
        #expect(MealType.suggested(for: TimeOfDay(hour: 12, minute: 30)) == .lunch)
        #expect(MealType.suggested(for: TimeOfDay(hour: 16, minute: 0)) == .snack)
        #expect(MealType.suggested(for: TimeOfDay(hour: 19, minute: 30)) == .dinner)
        #expect(MealType.suggested(for: TimeOfDay(hour: 23, minute: 0)) == .snack)
    }
}
