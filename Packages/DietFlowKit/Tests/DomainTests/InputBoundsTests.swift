import Foundation
import Testing
import Domain

/// What the app does with input that is wrong, hostile or simply enormous. Every plan change goes
/// through `MealPlan.sanitized()` and `Meal.sanitized()`, so these are the rules for all of them.
struct InputBoundsTests {
    private func meal(_ title: String, day: Int = 0, id: UUID = UUID()) -> Meal {
        Meal(id: id, dayIndex: day, type: .lunch, time: TimeOfDay(hour: 13, minute: 0), title: title)
    }

    @Test func aMealWithoutANameIsNotAMeal() {
        #expect(meal("").sanitized() == nil)
        #expect(meal("  \n\t ").sanitized() == nil)
    }

    @Test func aNameIsOneTrimmedLine() {
        #expect(meal("  Grilled\nchicken  ").sanitized()?.title == "Grilled chicken")
    }

    @Test func textIsCutToItsLimit() {
        var long = meal(String(repeating: "a", count: 5_000))
        long.details = String(repeating: "b", count: 50_000)
        long.notes = String(repeating: "c", count: 50_000)
        long.portion = String(repeating: "d", count: 5_000)
        long.customTypeName = String(repeating: "e", count: 5_000)
        let stored = long.sanitized()
        #expect(stored?.title.count == PlanLimits.mealTitleLength)
        #expect(stored?.details?.count == PlanLimits.detailsLength)
        #expect(stored?.notes?.count == PlanLimits.notesLength)
        #expect(stored?.portion?.count == PlanLimits.portionLength)
        #expect(stored?.customTypeName?.count == PlanLimits.typeNameLength)
    }

    @Test func numbersOutOfRangeAreDroppedNotClamped() {
        var odd = meal("Soup")
        odd.nutrition = Nutrition(calories: 99_999_999, protein: -4, carbohydrates: .infinity, fat: 12.5)
        let nutrition = odd.sanitized()?.nutrition
        #expect(nutrition?.calories == nil)
        #expect(nutrition?.protein == nil)
        #expect(nutrition?.carbohydrates == nil)
        #expect(nutrition?.fat == 12.5)
    }

    @Test func aPlanKeepsOnlyNamedMealsAndOneOfEachID() {
        let repeated = UUID()
        let plan = MealPlan(
            name: "  Keto\nweek  ",
            schedule: PlanSchedule(startDay: CalendarDay(year: 2026, month: 10, day: 5), length: 7, repeats: true),
            meals: [meal("Eggs", id: repeated), meal("   "), meal("Eggs again", id: repeated), meal("Fish", day: 3)]
        ).sanitized()
        #expect(plan.name == "Keto week")
        #expect(plan.meals.map(\.title) == ["Eggs", "Fish"])
    }

    @Test func aPlanNeverHoldsMoreMealsThanTheLimit() {
        let schedule = PlanSchedule(startDay: CalendarDay(year: 2026, month: 10, day: 5), length: 1, repeats: true)
        let meals = (0..<(PlanLimits.mealsPerPlan + 50)).map { meal("Meal \($0)") }
        #expect(MealPlan(name: "Huge", schedule: schedule, meals: meals).sanitized().meals.count == PlanLimits.mealsPerPlan)
    }
}

struct ImportBoundsTests {
    @Test func groupedThousandsAreNotReadAsDecimals() {
        // "1,200 kcal" read as 1.2 would become one calorie and pass every range check.
        for text in ["Lunch: Chicken salad (1,200 kcal)", "Lunch: Chicken salad (1.200 kcal)"] {
            let meal = PastedPlanParser.parse(text)?.days.first?.meals.first
            #expect(meal?.calories == 1_200)
            #expect(meal?.title == "Chicken salad")
        }
    }

    @Test func decimalsStayDecimals() {
        let meal = PastedPlanParser.parse("Lunch: Chicken salad (430 kcal, 30,5 g protein)")?.days.first?.meals.first
        #expect(meal?.calories == 430)
        #expect(meal?.protein == 30.5)
    }

    @Test func groupedThousandsInAFileAreReadToo() throws {
        let json = #"{"days":[{"dayIndex":1,"meals":[{"time":"13:00","title":"Pasta","calories":"1.250 kcal"}]}]}"#
        let payload = try MealPlanPayload.decode(Data(json.utf8))
        #expect(payload.days.first?.meals.first?.calories == 1_250)
    }

    @Test func textTooLongToBeAPlanIsNotRead() {
        let line = "13:00 Lunch: Chicken salad\n"
        let endless = String(repeating: line, count: PlanLimits.importTextLength / line.count + 10)
        #expect(PastedPlanParser.parse(endless) == nil)
    }

    @Test func aFileWithMoreMealsThanAPlanCanHoldIsRefusedWhole() {
        let meals = (0..<(PlanLimits.mealsPerPlan + 1)).map { MealPayload(time: "13:00", title: "Meal \($0)") }
        let payload = MealPlanPayload(days: [DayPayload(dayIndex: 1, meals: meals)])
        let defaults = ImportDefaults(planName: "Imported plan", startDay: CalendarDay(year: 2026, month: 10, day: 5))
        #expect(throws: PlanImportError.unreadable) {
            try PlanImportNormalizer.draft(from: payload, defaults: defaults)
        }
    }

    @Test func importedTextIsBounded() throws {
        let meal = MealPayload(time: "13:00", title: String(repeating: "x", count: 9_000), description: String(repeating: "y", count: 90_000))
        let payload = MealPlanPayload(days: [DayPayload(dayIndex: 1, meals: [meal])])
        let defaults = ImportDefaults(planName: "Imported plan", startDay: CalendarDay(year: 2026, month: 10, day: 5))
        let stored = try PlanImportNormalizer.draft(from: payload, defaults: defaults).plan.meals.first
        #expect(stored?.title.count == PlanLimits.mealTitleLength)
        #expect(stored?.details?.count == PlanLimits.detailsLength)
    }
}
