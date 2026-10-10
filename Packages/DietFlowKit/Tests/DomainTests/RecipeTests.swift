import Foundation
import Testing
import Domain

/// Reads a recipe the way the app reads the server's answer and its own kept copy.
private func decodeRecipe(_ json: String) throws -> Recipe {
    try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
}

/// One ingredient with the given swaps written as raw JSON, so each test states only what it is about.
private func recipeWithSwaps(_ swaps: String) -> String {
    #"""
    {"title":"Yoğurt ve ceviz","servings":1,"minutes":5,"difficulty":"easy",
     "ingredients":[{"name":"Yoğurt","amount":"200 g","substitutes":[\#(swaps)]}],
     "steps":[{"text":"Put it together.","kind":"plate"}],
     "tips":[]}
    """#
}

struct RecipeTests {
    @Test func stepsForgiveMinutesAndKindsTheyCannotUse() throws {
        let recipe = try decodeRecipe(#"""
        {"title":"Menemen","servings":2,"minutes":15,"difficulty":"easy","ingredients":[],
         "steps":[
           {"text":"Chop the peppers.","kind":"chop"},
           {"text":"Soften them.","minutes":8,"kind":"sauté"},
           {"text":"Add the eggs.","minutes":"three","kind":null},
           {"text":"Stir.","minutes":-4},
           {"text":"Serve.","minutes":0,"kind":"plate"},
           {"text":"Wait.","minutes":null,"kind":7}
         ],
         "tips":[]}
        """#)
        #expect(recipe.steps.map(\.kind) == [.chop, .other, .other, .other, .plate, .other])
        #expect(recipe.steps.map(\.minutes) == [nil, 8, nil, nil, nil, nil])
        #expect(recipe.timedSteps == 1)
    }

    @Test(arguments: Recipe.StepKind.allCases)
    func everyStepKindTheServerNamesIsRead(_ kind: Recipe.StepKind) throws {
        let recipe = try decodeRecipe(#"""
        {"title":"x","servings":1,"minutes":1,"difficulty":"easy","ingredients":[],
         "steps":[{"text":"Do it.","kind":"\#(kind.rawValue)"}],"tips":[]}
        """#)
        #expect(recipe.steps.first?.kind == kind)
    }

    @Test func aStepWithoutTextIsNotAStep() {
        #expect(throws: (any Error).self) {
            try decodeRecipe(#"{"title":"x","servings":1,"minutes":1,"difficulty":"easy","ingredients":[],"steps":[{"kind":"mix"}],"tips":[]}"#)
        }
    }

    @Test func aSwapSaysWhatItChangesInEnergy() throws {
        let recipe = try decodeRecipe(recipeWithSwaps(#"""
        {"name":"Süzme yoğurt","amount":"200 g","note":"Daha fazla protein","kcalDelta":-40},
        {"name":"Labne","amount":"150 g","kcalDelta":95},
        {"name":"Kefir","kcalDelta":0}
        """#))
        let swaps = try #require(recipe.ingredients.first?.substitutes)
        #expect(swaps.map(\.kcalDelta) == [-40, 95, 0])
        #expect(swaps.first?.note == "Daha fazla protein")
        #expect(swaps.first?.amount == "200 g")
    }

    @Test func aSwapWithoutAReadableDifferenceStillOpens() throws {
        let recipe = try decodeRecipe(recipeWithSwaps(#"""
        {"name":"Missing"},
        {"name":"Null","kcalDelta":null},
        {"name":"Words","kcalDelta":"about the same"},
        {"name":"Too big","kcalDelta":9000},
        {"name":"Too small","kcalDelta":-2001},
        {"name":"Fraction","kcalDelta":-39.6},
        {"name":"Huge","kcalDelta":1e300},
        {"name":"Note in a number","note":12,"amount":3}
        """#))
        let swaps = try #require(recipe.ingredients.first?.substitutes)
        #expect(swaps.map(\.name) == ["Missing", "Null", "Words", "Too big", "Too small", "Fraction", "Huge", "Note in a number"])
        #expect(swaps.map(\.kcalDelta) == [nil, nil, nil, nil, nil, -40, nil, nil])
        #expect(swaps.last?.note == nil)
        #expect(swaps.last?.amount == nil)
    }

    @Test func anIngredientWithoutSwapsHasNone() throws {
        let recipe = try decodeRecipe(#"""
        {"title":"x","servings":1,"minutes":1,"difficulty":"easy",
         "ingredients":[{"name":"Salt"},{"name":"Water","amount":"1 cup","substitutes":"none"}],
         "steps":[{"text":"Boil.","kind":"boil","minutes":10}],"tips":[]}
        """#)
        #expect(recipe.ingredients.map(\.substitutes) == [[], []])
        #expect(recipe.ingredients.last?.amount == "1 cup")
    }

    @Test func aKeptRecipeComesBackTheSame() throws {
        let recipe = Recipe(
            title: "Tavuklu salata",
            summary: "Hafif bir öğle yemeği.",
            servings: 2,
            minutes: 25,
            difficulty: .medium,
            ingredients: [
                .init(name: "Tavuk göğsü", amount: "300 g", substitutes: [
                    .init(name: "Hindi göğsü", amount: "300 g", note: "Daha yağsız", kcalDelta: -30),
                    .init(name: "Nohut", amount: "1 su bardağı"),
                ]),
                .init(name: "Tuz"),
            ],
            steps: [
                .init(text: "Tavuğu ızgarada pişir.", minutes: 12, kind: .grill),
                .init(text: "Servis et.", kind: .plate),
            ],
            tips: ["Sosu ayrı sakla."]
        )
        let copy = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe))
        #expect(copy == recipe)
        #expect(copy.ingredients.first?.substitutes.map(\.kcalDelta) == [-30, nil])
    }

    @Test func aDifferenceBeyondTheLimitIsNotKept() {
        #expect(Recipe.Substitute(name: "a", kcalDelta: Recipe.Substitute.kcalDeltaLimit).kcalDelta == 2_000)
        #expect(Recipe.Substitute(name: "a", kcalDelta: -Recipe.Substitute.kcalDeltaLimit).kcalDelta == -2_000)
        #expect(Recipe.Substitute(name: "a", kcalDelta: 2_001).kcalDelta == nil)
        #expect(Recipe.Substitute(name: "a", kcalDelta: Int.min).kcalDelta == nil)
        #expect(Recipe.Substitute(name: "a").kcalDelta == nil)
    }
}
