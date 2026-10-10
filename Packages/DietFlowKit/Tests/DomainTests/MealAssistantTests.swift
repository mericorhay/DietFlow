import Foundation
import Testing
import Domain

private func meal(_ day: Int, _ hour: Int, _ title: String, details: String? = nil, calories: Int? = nil, type: MealType = .lunch) -> Meal {
    Meal(dayIndex: day, type: type, time: TimeOfDay(hour: hour, minute: 0), title: title, details: details, nutrition: Nutrition(calories: calories))
}

private func estimate(_ calories: Int) -> NutritionEstimate {
    NutritionEstimate(calories: calories, protein: 20, carbohydrates: 30, fat: 10, portion: "1 bowl", confidence: .medium)
}

struct NutritionRequestPlanTests {
    @Test func aDishThatRepeatsIsAskedAboutOnceAndAnsweredForEveryDay() throws {
        let oats = (0..<7).map { meal($0, 8, "Oats with berries", details: "50 g oats", type: .breakfast) }
        let request = NutritionRequestPlan(meals: oats)
        #expect(request.dishCount == 1)
        let question = try #require(request.batches.first?.first)
        #expect(question.title == "Oats with berries")
        #expect(question.details == "50 g oats")

        let answers = request.estimates(from: [question.id: estimate(320)])
        #expect(answers.count == 7)
        #expect(Set(answers.keys) == Set(oats.map(\.id)))
    }

    @Test func mealsWithTheirOwnFiguresAreNeverAskedAbout() {
        let stated = meal(0, 13, "Chicken salad", calories: 480)
        let missing = meal(0, 19, "Lentil soup")
        let request = NutritionRequestPlan(meals: [stated, missing])
        #expect(request.dishCount == 1)
        #expect(request.batches.flatMap { $0 }.map(\.title) == ["Lentil soup"])
    }

    @Test func aPlanWithNothingMissingAsksNothing() {
        let request = NutritionRequestPlan(meals: [meal(0, 13, "Chicken salad", calories: 480)])
        #expect(request.isEmpty)
        #expect(request.estimates(from: [:]).isEmpty)
    }

    @Test func questionsAreSplitIntoRequestsTheServerAccepts() {
        let meals = (0..<130).map { meal($0 / 4, 8 + $0 % 4, "Dish \($0)") }
        let request = NutritionRequestPlan(meals: meals, batchSize: 60)
        #expect(request.batches.map(\.count) == [60, 60, 10])
        #expect(request.dishCount == 130)
        // Every id is different, so an answer can only land on its own dish.
        let ids = request.batches.flatMap { $0 }.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func dishesBeyondTheLimitAreCountedNotAskedAbout() {
        let meals = (0..<12).map { meal(0, 8, "Dish \($0)") }
        let request = NutritionRequestPlan(meals: meals, batchSize: 5, dishLimit: 10)
        #expect(request.dishCount == 10)
        #expect(request.skippedDishes == 2)
    }

    @Test func anAnswerForAnUnknownIdIsIgnored() {
        let request = NutritionRequestPlan(meals: [meal(0, 19, "Lentil soup")])
        #expect(request.estimates(from: ["d99": estimate(300)]).isEmpty)
    }

    @Test func questionsGoInPlanOrder() {
        let late = meal(1, 8, "Second day breakfast")
        let early = meal(0, 19, "First day dinner")
        let request = NutritionRequestPlan(meals: [late, early])
        #expect(request.batches.flatMap { $0 }.map(\.title) == ["First day dinner", "Second day breakfast"])
    }
}

struct EstimateFillingTests {
    @Test func anEstimateFillsAnEmptyMealAndIsMarked() {
        let filled = meal(0, 19, "Lentil soup").filling(estimate(310))
        #expect(filled.nutrition.calories == 310)
        #expect(filled.nutrition.isEstimated)
        #expect(filled.portion == "1 bowl")
    }

    @Test func anEstimateNeverReplacesWhatThePlanSaid() {
        var stated = meal(0, 13, "Chicken salad", calories: 480)
        stated.portion = "200 g"
        let after = stated.filling(estimate(900))
        #expect(after == stated)
    }

    @Test func aStatedPortionStaysWhenFiguresAreFilledIn() {
        var soup = meal(0, 19, "Lentil soup")
        soup.portion = "1 large bowl"
        #expect(soup.filling(estimate(310)).portion == "1 large bowl")
    }

    @Test func estimatedEnergyIsShownAsAnEstimate() throws {
        let english = Locale(identifier: "en_US")
        let estimated = try #require(EnergyUnit.kilocalories.format(Nutrition(calories: 510, estimated: true), locale: english))
        let stated = try #require(EnergyUnit.kilocalories.format(Nutrition(calories: 510), locale: english))
        #expect(estimated.hasPrefix("≈"))
        #expect(!stated.hasPrefix("≈"))
        #expect(estimated.hasSuffix(stated))
        #expect(EnergyUnit.kilocalories.format(Nutrition(), locale: english) == nil)
    }
}
