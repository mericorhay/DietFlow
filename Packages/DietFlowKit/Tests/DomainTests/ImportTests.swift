import Foundation
import Testing
import Domain

let importDefaults = ImportDefaults(planName: "Imported plan", startDay: day(2026, 10, 5))

struct PayloadDecodingTests {
    @Test func readsTheCanonicalFormat() throws {
        let json = """
        {
          "schemaVersion": 1,
          "name": "14-Day Keto Plan",
          "startDate": "2026-10-06",
          "repeatCycle": { "lengthInDays": 14, "repeats": false },
          "days": [
            { "dayIndex": 1, "meals": [
              { "time": "10:00", "type": "breakfast", "title": "Halloumi salad", "calories": 430 },
              { "time": "14:00", "type": "lunch", "title": "Chicken Caesar", "protein": 42, "carbs": 9, "fat": 34 }
            ] },
            { "dayIndex": 2, "meals": [
              { "time": "19:00", "type": "dinner", "title": "Taco salad", "notes": "No tortilla" }
            ] }
          ]
        }
        """
        let payload = try MealPlanPayload.decode(Data(json.utf8))
        let draft = try PlanImportNormalizer.draft(from: payload, defaults: importDefaults)
        #expect(draft.issues.isEmpty)
        #expect(draft.plan.name == "14-Day Keto Plan")
        #expect(draft.plan.schedule == PlanSchedule(kind: .cycle, startDay: day(2026, 10, 6), length: 14, repeats: false))
        #expect(draft.plan.meals.count == 3)
        let lunch = try #require(draft.plan.meals.first { $0.title == "Chicken Caesar" })
        #expect(lunch.type == .lunch)
        #expect(lunch.time == TimeOfDay(hour: 14, minute: 0))
        #expect(lunch.nutrition == Nutrition(protein: 42, carbohydrates: 9, fat: 34))
        #expect(draft.plan.meals.first { $0.title == "Taco salad" }?.dayIndex == 1)
    }

    @Test func forgivesTheWaysModelsWriteIt() throws {
        let json = """
        {
          "planName": "Weekday plan",
          "repeat_cycle": 7,
          "days": [
            { "day": "1", "meals": [
              { "time": "8am", "mealType": "Breakfast", "name": "Oats", "kcal": "350 kcal", "carbohydrates": "40,5 g" },
              { "at": "1:30 PM", "meal": "Öğle yemeği", "dish": "Mercimek çorbası" }
            ] }
          ]
        }
        """
        let draft = try PlanImportNormalizer.draft(from: MealPlanPayload.decode(Data(json.utf8)), defaults: importDefaults)
        #expect(draft.plan.name == "Weekday plan")
        #expect(draft.plan.schedule.length == 7)
        #expect(draft.plan.schedule.repeats)
        let oats = try #require(draft.plan.meals.first)
        #expect(oats.time == TimeOfDay(hour: 8, minute: 0))
        #expect(oats.nutrition.calories == 350)
        #expect(oats.nutrition.carbohydrates == 40.5)
        let soup = try #require(draft.plan.meals.last)
        #expect(soup.type == .lunch)
        #expect(soup.time == TimeOfDay(hour: 13, minute: 30))
    }

    @Test func readsAFlatListOfMeals() throws {
        let json = #"{"name":"Flat","meals":[{"day":2,"time":"12:00","title":"B"},{"day":1,"time":"09:00","title":"A"}]}"#
        let draft = try PlanImportNormalizer.draft(from: MealPlanPayload.decode(Data(json.utf8)), defaults: importDefaults)
        #expect(draft.plan.meals.map(\.title) == ["A", "B"])
        #expect(draft.plan.meals.map(\.dayIndex) == [0, 1])
    }

    @Test func exportReadsBackTheSame() throws {
        let plan = SamplePlan.keto(startingOn: day(2026, 10, 5), repeats: false)
        let data = try MealPlanPayload(plan: plan).encodedJSON()
        let draft = try PlanImportNormalizer.draft(from: MealPlanPayload.decode(data), defaults: importDefaults)
        #expect(draft.issues.isEmpty)
        #expect(draft.plan.schedule == plan.schedule)
        #expect(draft.plan.meals.count == plan.meals.count)
        #expect(draft.plan.meals.map(\.title).sorted() == plan.meals.map(\.title).sorted())
    }

    @Test func rejectsWhatIsNotAPlan() {
        #expect(throws: (any Error).self) { try MealPlanPayload.decode(Data("[1, 2, 3]".utf8)) }
        #expect(throws: PlanImportError.noMeals) {
            try PlanImportNormalizer.draft(from: MealPlanPayload(days: []), defaults: importDefaults)
        }
    }
}

struct NormalizerTests {
    func draft(_ meals: [MealPayload], dayIndex: Int? = 1) throws -> ImportedPlanDraft {
        try PlanImportNormalizer.draft(from: MealPlanPayload(days: [DayPayload(dayIndex: dayIndex, meals: meals)]), defaults: importDefaults)
    }

    @Test func aMissingTimeIsFilledInAndReported() throws {
        let result = try draft([MealPayload(type: "dinner", title: "Fish")])
        #expect(result.plan.meals[0].time == MealType.dinner.typicalTime)
        #expect(result.issues == [.timeMissing(day: 1, title: "Fish", assigned: MealType.dinner.typicalTime)])
        #expect(result.mealsWithAssignedTimes.contains(result.plan.meals[0].id))
    }

    @Test func anUnreadableTimeIsReported() throws {
        let result = try draft([MealPayload(time: "after gym", type: "snack", title: "Shake")])
        #expect(result.issues == [.timeUnreadable(day: 1, title: "Shake", text: "after gym", assigned: MealType.snack.typicalTime)])
    }

    @Test func aMealWithoutAnyNameIsDropped() throws {
        let result = try draft([MealPayload(time: "10:00"), MealPayload(time: "13:00", title: "Soup")])
        #expect(result.plan.meals.map(\.title) == ["Soup"])
        #expect(result.issues.contains(.untitledMealDropped(day: 1)))
    }

    @Test func theDescriptionStandsInForAMissingTitle() throws {
        let result = try draft([MealPayload(time: "10:00", description: "Two eggs and avocado")])
        #expect(result.plan.meals[0].title == "Two eggs and avocado")
        #expect(result.plan.meals[0].details == nil)
    }

    @Test func anUnknownTypeKeepsItsName() throws {
        let result = try draft([MealPayload(time: "17:00", type: "pre-workout", title: "Banana")])
        #expect(result.plan.meals[0].type == .other)
        #expect(result.plan.meals[0].customTypeName == "Pre-workout")
        #expect(result.plan.meals[0].typeLabel == "Pre-workout")
    }

    @Test func noTypeIsGuessedFromTheTime() throws {
        let result = try draft([MealPayload(time: "07:30", title: "A"), MealPayload(time: "12:30", title: "B"), MealPayload(time: "19:30", title: "C"), MealPayload(time: "16:00", title: "D")])
        #expect(result.plan.meals.map(\.type) == [.breakfast, .lunch, .snack, .dinner])
    }

    @Test func impossibleNutritionIsDroppedAndReported() throws {
        let result = try draft([MealPayload(time: "13:00", title: "Soup", calories: 90_000, protein: 30)])
        #expect(result.plan.meals[0].nutrition == Nutrition(protein: 30))
        #expect(result.issues == [.nutritionDropped(day: 1, title: "Soup")])
    }

    @Test func fixedDatesArePlacedByDate() throws {
        let payload = MealPlanPayload(kind: "fixedDates", days: [
            DayPayload(date: "2026-10-12", meals: [MealPayload(time: "12:00", title: "Later")]),
            DayPayload(date: "2026-10-10", meals: [MealPayload(time: "12:00", title: "First")]),
        ])
        let result = try PlanImportNormalizer.draft(from: payload, defaults: importDefaults)
        #expect(result.plan.schedule.kind == .fixedDates)
        #expect(result.plan.schedule.startDay == day(2026, 10, 10))
        #expect(result.plan.schedule.length == 3)
        #expect(result.plan.schedule.repeats == false)
        #expect(result.plan.meals.map(\.dayIndex) == [0, 2])
    }

    @Test func anUnreadableStartDateFallsBackAndIsReported() throws {
        let payload = MealPlanPayload(startDate: "next Monday", days: [DayPayload(dayIndex: 1, meals: [MealPayload(time: "12:00", title: "A")])])
        let result = try PlanImportNormalizer.draft(from: payload, defaults: importDefaults)
        #expect(result.plan.schedule.startDay == importDefaults.startDay)
        #expect(result.issues == [.startDateUnreadable(text: "next Monday")])
    }

    @Test func aLongTitleIsKeptWholeUpToTwoHundredCharacters() throws {
        let long = String(repeating: "Grilled chicken with vegetables ", count: 4).trimmingCharacters(in: .whitespaces)
        #expect(long.count > 100)
        let result = try draft([MealPayload(time: "13:00", title: long)])
        #expect(result.plan.meals[0].title == long)
    }
}

struct TimeParserTests {
    @Test(arguments: [
        ("14:00", 14, 0), ("14.30", 14, 30), ("1400", 14, 0), ("14h", 14, 0), ("14h30", 14, 30),
        ("2 PM", 14, 0), ("2:30pm", 14, 30), ("7 a.m.", 7, 0), ("12am", 0, 0), ("12 pm", 12, 0), ("08:00:00", 8, 0), ("8", 8, 0),
    ])
    func readsClockTimes(text: String, hour: Int, minute: Int) {
        #expect(TimeParser.parse(text) == TimeOfDay(hour: hour, minute: minute))
    }

    @Test(arguments: ["25:00", "13pm", "noon", "", "12:75"])
    func rejectsNonsense(text: String) {
        #expect(TimeParser.parse(text) == nil)
    }
}

struct MealTypeParserTests {
    @Test(arguments: [
        ("Breakfast", MealType.breakfast), ("KAHVALTI", .breakfast), ("Kahvaltı", .breakfast), ("Desayuno", .breakfast),
        ("Öğle yemeği", .lunch), ("Almuerzo", .lunch), ("Lunch (light)", .lunch),
        ("Akşam", .dinner), ("supper", .dinner), ("Cena", .dinner),
        ("Ara öğün", .snack), ("Afternoon snack", .snack), ("Merienda", .snack),
        ("Other", .other),
    ])
    func readsMealNames(text: String, type: MealType) {
        #expect(MealTypeParser.type(of: text) == type)
    }

    @Test func doesNotInventATypeFromAMealName() {
        #expect(MealTypeParser.type(of: "Grilled chicken") == nil)
        #expect(MealTypeParser.exactType(of: "Lunch with friends") == nil)
    }
}

struct PastedPlanTests {
    let monday = day(2026, 10, 5)

    func draft(_ text: String) throws -> ImportedPlanDraft {
        let payload = try #require(PastedPlanParser.parse(text, today: day(2026, 10, 7)))
        return try PlanImportNormalizer.draft(from: payload, defaults: importDefaults)
    }

    @Test func readsAChatbotStylePlan() throws {
        let text = """
        14-Day Keto Plan

        **Day 1**
        - 10:00 Breakfast: Halloumi, olives and avocado salad (430 kcal)
        - 14:00 Lunch - Grilled Chicken Caesar Salad
        - Dinner (19:00): Steak and Mediterranean salad

        **Day 2**
        - 10:00 Breakfast: Feta, cucumber and walnut salad
        - 14:00 Lunch: Grilled chicken with Greek salad, 30 g protein
        - 19:00 Dinner: Beef taco salad without tortilla
        """
        let result = try draft(text)
        #expect(result.plan.name == "14-Day Keto Plan")
        #expect(result.plan.schedule.length == 2)
        #expect(result.plan.meals.count == 6)
        #expect(result.issues.isEmpty)
        let first = try #require(result.plan.meals.first)
        #expect(first.title == "Halloumi, olives and avocado salad")
        #expect(first.type == .breakfast)
        #expect(first.nutrition.calories == 430)
        let dinner = try #require(result.plan.meals.first { $0.dayIndex == 0 && $0.type == .dinner })
        #expect(dinner.time == TimeOfDay(hour: 19, minute: 0))
        #expect(dinner.title == "Steak and Mediterranean salad")
        let protein = try #require(result.plan.meals.first { $0.title == "Grilled chicken with Greek salad" })
        #expect(protein.nutrition.protein == 30)
        #expect(result.plan.meals.filter { $0.dayIndex == 1 }.count == 3)
    }

    @Test func readsATurkishDietitianList() throws {
        let text = """
        1. Gün
        Kahvaltı (08:00):
        - 2 haşlanmış yumurta
        - Yarım avokado
        Öğle yemeği 13:00 - Izgara tavuk salata
        Akşam: Izgara köfte, cacık

        2. Gün
        Kahvaltı 08:30 - Menemen
        """
        let result = try draft(text)
        #expect(result.plan.schedule.length == 2)
        let breakfast = try #require(result.plan.meals.first)
        #expect(breakfast.type == .breakfast)
        #expect(breakfast.time == TimeOfDay(hour: 8, minute: 0))
        #expect(breakfast.title == "2 haşlanmış yumurta, Yarım avokado")
        let lunch = try #require(result.plan.meals.first { $0.type == .lunch })
        #expect(lunch.time == TimeOfDay(hour: 13, minute: 0))
        #expect(lunch.title == "Izgara tavuk salata")
        let dinner = try #require(result.plan.meals.first { $0.type == .dinner })
        #expect(dinner.title == "Izgara köfte, cacık")
        #expect(result.issues == [.timeMissing(day: 1, title: "Izgara köfte, cacık", assigned: MealType.dinner.typicalTime)])
        #expect(result.plan.meals.first { $0.dayIndex == 1 }?.time == TimeOfDay(hour: 8, minute: 30))
    }

    @Test func weekdayHeadingsMakeAWeeklyPlan() throws {
        let text = """
        Lunes
        Desayuno 9:00 - Huevos revueltos
        Cena: Pescado al horno
        Martes
        Desayuno 9:00 - Yogur con nueces
        """
        let result = try draft(text)
        #expect(result.plan.schedule.length == 7)
        #expect(result.plan.schedule.repeats)
        // Today in this test is Wednesday 7 October; Monday is day 1.
        #expect(result.plan.schedule.startDay == monday)
        #expect(result.plan.meals.map(\.dayIndex) == [0, 0, 1])
    }

    @Test func aSingleDayRepeatsEveryDay() throws {
        let result = try draft("08:00 Oats with berries\n13:00 Lentil soup\n19:00 Grilled fish")
        #expect(result.plan.schedule.length == 1)
        #expect(result.plan.schedule.repeats)
        #expect(result.plan.meals.map(\.type) == [.breakfast, .lunch, .dinner])
    }

    @Test func jsonInAReplyWinsOverLineReading() throws {
        let text = """
        Here is your plan:
        ```json
        {"schemaVersion": 1, "name": "From JSON", "days": [{"dayIndex": 1, "meals": [{"time": "09:00", "type": "breakfast", "title": "Eggs"}]}]}
        ```
        Enjoy!
        """
        let result = try draft(text)
        #expect(result.plan.name == "From JSON")
        #expect(result.plan.meals.map(\.title) == ["Eggs"])
    }

    @Test func proseIsNotAPlan() {
        #expect(PastedPlanParser.parse("Remember to drink water and walk every day.") == nil)
        #expect(PastedPlanParser.parse("   ") == nil)
    }
}
