#if DEBUG
import Foundation
import AIServices
import AppCore
import Domain
import Purchases

/// Launch arguments that open the app in a known state, so every screen can be checked — in every
/// language, in dark mode, at large text sizes — without tapping through. Debug builds only; CI
/// uses them for screenshots (scripts/ci-screenshots.sh).
///
///     -DebugSeed sample|now|empty|onboarding
///                                          in-memory data: the sample plan; a day built around the
///                                          current time (one meal done, one on now, one next); nothing;
///                                          or first run
///     -DebugTab today|plan|widgets
///     -DebugSheet settings|import|write|organize|newMeal|newPlan|plus|plusIntro
///     -DebugMeal next                      opens the meal in front on Today
///     -DebugCook next                      opens cook mode on the meal in front (canned recipe)
///     -DebugOnboardingPage 0…3
///     -DebugOnboardingTime <seconds>       stops the last page's animation at that moment
///     -DebugPlus monthly|trial|yearly|lifetime
///                                          as if that were held, for Settings' Plus section
///     -DebugWidgetLook <colour>.<tone>     e.g. blue.bold, green.soft: the widget's colour and tone
///     -DebugWidget <kind>.<size>           e.g. today.large, progress.small: the preview the Widgets tab opens on
enum DebugLaunch {
    /// The Plus screen without the App Store: the prices as set in App Store Connect, in dollars.
    static func standInStore(entitlement: PlusEntitlement?) -> PlusStore {
        PlusStore(
            standInOffers: [
                .init(id: PlusStore.monthlyID, kind: .monthly, displayPrice: "$3.99", trial: entitlement == nil ? BillingCycle.Span(value: 7, unit: .day) : nil),
                .init(id: PlusStore.yearlyID, kind: .yearly, displayPrice: "$24.99", pricePerMonth: "$2.08"),
                .init(id: PlusStore.lifetimeID, kind: .lifetime, displayPrice: "$34.99"),
            ],
            yearlySavingPercent: 48,
            entitlement: entitlement
        )
    }

    static func seededEntitlement(now: Date = .now) -> PlusEntitlement? {
        let started = now.addingTimeInterval(-3 * 86_400)
        switch value("DebugPlus") {
        case "monthly":
            return PlusEntitlement(kind: .monthly, periodStart: started, periodEnd: BillingCycle.date(byAdding: .init(value: 1, unit: .month), to: started), willRenew: true, isTrial: false)
        case "trial":
            return PlusEntitlement(kind: .monthly, periodStart: started, periodEnd: BillingCycle.date(byAdding: .init(value: 7, unit: .day), to: started), willRenew: true, isTrial: true)
        case "yearly":
            return PlusEntitlement(kind: .yearly, periodStart: started, periodEnd: BillingCycle.date(byAdding: .init(value: 1, unit: .year), to: started), willRenew: false, isTrial: false)
        case "lifetime":
            return PlusEntitlement(kind: .lifetime, periodStart: started, periodEnd: nil, willRenew: false, isTrial: false)
        default:
            return nil
        }
    }

    /// An assistant that is there to be shown and reaches nothing: its rows appear in screenshots.
    static func standInAssistant() -> PlanAssistantClient? {
        guard let url = URL(string: "https://assistant.invalid") else { return nil }
        return PlanAssistantClient(endpoint: AssistantEndpoint(url: url, appToken: ""), installID: "debug")
    }

    /// A meal assistant that answers at once with canned figures and one well-made recipe, so the
    /// estimate and cook mode screens can be seen without a network.
    static func standInMealAssistant() -> any MealAssistant {
        CannedMealAssistant()
    }

    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-\(name)"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// A store holding only what the seed asks for, or nil for the real one. Seeded stores live in
    /// memory and never touch the person's data, settings or widget.
    static func seededStore() -> MealPlanStore? {
        let store: MealPlanStore
        switch value("DebugSeed") {
        case "sample":
            store = .preview(withSample: true, settings: AppSettings(hasCompletedOnboarding: true))
        case "now":
            store = storeAroundNow()
        case "empty":
            store = .preview(withSample: false, settings: AppSettings(hasCompletedOnboarding: true))
        case "onboarding":
            store = .preview(withSample: false, settings: AppSettings())
        default:
            return nil
        }
        if let look = value("DebugWidgetLook")?.split(separator: ".").map(String.init), look.count == 2 {
            store.updateSettings { settings in
                settings.widgetAccent = WidgetAccent(rawValue: look[0]) ?? settings.widgetAccent
                settings.widgetBackground = WidgetBackgroundStyle(rawValue: look[1]) ?? settings.widgetBackground
            }
        }
        return store
    }

    /// Today's meals placed around the current time, so the screens show every state at once:
    /// breakfast done, lunch on now, a snack next, dinner later.
    private static func storeAroundNow(now: Date = .now) -> MealPlanStore {
        let store = MealPlanStore.preview(withSample: false, settings: AppSettings(hasCompletedOnboarding: true))
        let minutes = Calendar.current.dateComponents([.hour, .minute], from: now)
        let current = (minutes.hour ?? 12) * 60 + (minutes.minute ?? 0)
        func at(_ offset: Int) -> TimeOfDay { TimeOfDay(minutesSinceMidnight: current + offset) }
        let sample = SamplePlan.keto(startingOn: .today())
        let firstDay = sample.meals.filter { $0.dayIndex == 0 }.sorted { $0.time < $1.time }
        let offsets = [-180, -20, 40, 240]
        var plan = sample
        plan.meals = sample.meals.filter { $0.dayIndex != 0 }
        for (meal, offset) in zip(firstDay, offsets) {
            var moved = meal
            moved.time = at(offset)
            plan.meals.append(moved)
        }
        store.attempt { try store.createPlan(plan) }
        if let first = firstDay.first {
            store.attempt { try store.markMealCompleted(OccurrenceKey(mealID: first.id, day: .today())) }
        }
        return store
    }
}

/// Answers like the real assistant, from what is written here. Debug builds only.
nonisolated struct CannedMealAssistant: MealAssistant {
    func estimateNutrition(_ questions: [NutritionQuestion], language: String) async throws -> [String: NutritionEstimate] {
        try await Task.sleep(for: .milliseconds(700))
        let words = Words(language: language)
        var answers: [String: NutritionEstimate] = [:]
        for question in questions {
            let (calories, protein, carbs, fat): (Int, Double, Double, Double) = switch question.type {
            case .breakfast: (420, 24, 12, 30)
            case .lunch: (560, 42, 18, 34)
            case .snack: (200, 8, 10, 14)
            case .dinner: (620, 46, 16, 40)
            case .other: (300, 15, 20, 17)
            }
            answers[question.id] = NutritionEstimate(calories: calories, protein: protein, carbohydrates: carbs, fat: fat, portion: words.portion, confidence: .medium)
        }
        return answers
    }

    func recipe(_ request: RecipeRequest, avoiding: String?) async throws -> Recipe {
        try await Task.sleep(for: .milliseconds(900))
        return Words(language: request.language).recipe(title: request.title, servings: request.servings)
    }

    /// The canned text, in the three languages the screenshots are taken in.
    nonisolated private struct Words {
        let code: String

        init(language: String) {
            code = switch language {
            case "Turkish": "tr"
            case "Spanish": "es"
            default: "en"
            }
        }

        var portion: String {
            switch code {
            case "tr": "1 tabak (yaklaşık 350 g)"
            case "es": "1 plato (unos 350 g)"
            default: "1 plate (about 350 g)"
            }
        }

        func recipe(title: String, servings: Int) -> Recipe {
            typealias I = Recipe.Ingredient
            typealias S = Recipe.Substitute
            typealias Step = Recipe.Step
            switch code {
            case "tr":
                return Recipe(
                    title: title,
                    summary: "Izgara tavuk, çıtır marul ve hafif bir sosla doyurucu, düşük karbonhidratlı bir öğle yemeği.",
                    servings: servings,
                    minutes: 25,
                    difficulty: .easy,
                    ingredients: [
                        I(name: "Tavuk göğsü", amount: "150 g", substitutes: [S(name: "Tavuk but", amount: "150 g", note: "Daha sulu, biraz daha yağlı"), S(name: "Hindi göğsü", amount: "150 g", note: "Daha yağsız")]),
                        I(name: "Göbek marul", amount: "1 küçük baş", substitutes: [S(name: "Roka", amount: "2 avuç", note: "Daha keskin bir tat")]),
                        I(name: "Parmesan", amount: "20 g", substitutes: [S(name: "Eski kaşar", amount: "20 g"), S(name: "Besin mayası", amount: "1 yemek kaşığı", note: "Süt ürünü yemeyenler için")]),
                        I(name: "Zeytinyağı", amount: "1 yemek kaşığı"),
                        I(name: "Limon suyu", amount: "1 yemek kaşığı", substitutes: [S(name: "Elma sirkesi", amount: "1 tatlı kaşığı")]),
                        I(name: "Yoğurt", amount: "2 yemek kaşığı", substitutes: [S(name: "Mayonez", amount: "1 yemek kaşığı", note: "Daha kremamsı, daha kalorili")]),
                        I(name: "Sarımsak", amount: "1 diş"),
                        I(name: "Tuz ve karabiber", amount: "Damak zevkine göre"),
                    ],
                    steps: [
                        Step(text: "Tavuğu kurulayıp tuz, karabiber ve yarım yemek kaşığı zeytinyağıyla ovun.", kind: .season),
                        Step(text: "Izgara tavayı orta-yüksek ateşte iyice ısıtın.", minutes: 3, kind: .heat),
                        Step(text: "Tavuğu her iki yüzü de altın rengi olana kadar pişirin; ortası artık pembe olmamalı.", minutes: 12, kind: .grill),
                        Step(text: "Tavuğu kesmeden önce dinlendirin, suyu içinde kalsın.", minutes: 5, kind: .rest),
                        Step(text: "Yoğurt, ezilmiş sarımsak, limon suyu ve kalan zeytinyağını çırparak sosu hazırlayın.", kind: .mix),
                        Step(text: "Marulu doğrayın, tavuğu dilimleyin, sosla karıştırıp üzerine parmesanı rendeleyin.", kind: .plate),
                    ],
                    tips: ["Tavuğu bir gece önceden marine ederseniz daha yumuşak olur.", "Sosu ayrı kapta saklarsanız salata ertesi gün de çıtır kalır."]
                )
            case "es":
                return Recipe(
                    title: title,
                    summary: "Un almuerzo saciante y bajo en carbohidratos: pollo a la plancha, lechuga crujiente y un aliño ligero.",
                    servings: servings,
                    minutes: 25,
                    difficulty: .easy,
                    ingredients: [
                        I(name: "Pechuga de pollo", amount: "150 g", substitutes: [S(name: "Muslo de pollo", amount: "150 g", note: "Más jugoso, algo más graso"), S(name: "Pechuga de pavo", amount: "150 g", note: "Más magra")]),
                        I(name: "Lechuga romana", amount: "1 cogollo", substitutes: [S(name: "Rúcula", amount: "2 puñados", note: "Sabor más intenso")]),
                        I(name: "Parmesano", amount: "20 g", substitutes: [S(name: "Levadura nutricional", amount: "1 cucharada", note: "Sin lácteos")]),
                        I(name: "Aceite de oliva", amount: "1 cucharada"),
                        I(name: "Zumo de limón", amount: "1 cucharada", substitutes: [S(name: "Vinagre de manzana", amount: "1 cucharadita")]),
                        I(name: "Yogur natural", amount: "2 cucharadas", substitutes: [S(name: "Mayonesa", amount: "1 cucharada", note: "Más cremosa y calórica")]),
                        I(name: "Ajo", amount: "1 diente"),
                        I(name: "Sal y pimienta", amount: "Al gusto"),
                    ],
                    steps: [
                        Step(text: "Seca el pollo y frótalo con sal, pimienta y media cucharada de aceite.", kind: .season),
                        Step(text: "Calienta bien una plancha a fuego medio-alto.", minutes: 3, kind: .heat),
                        Step(text: "Cocina el pollo hasta que esté dorado por ambos lados y sin rosa en el centro.", minutes: 12, kind: .grill),
                        Step(text: "Deja reposar el pollo antes de cortarlo para que conserve su jugo.", minutes: 5, kind: .rest),
                        Step(text: "Bate el yogur, el ajo machacado, el limón y el resto del aceite para el aliño.", kind: .mix),
                        Step(text: "Trocea la lechuga, corta el pollo, mezcla con el aliño y ralla el parmesano por encima.", kind: .plate),
                    ],
                    tips: ["Marinar el pollo la noche anterior lo deja más tierno.", "Guarda el aliño aparte y la ensalada seguirá crujiente al día siguiente."]
                )
            default:
                return Recipe(
                    title: title,
                    summary: "A filling, low-carb lunch: grilled chicken, crisp lettuce and a light dressing.",
                    servings: servings,
                    minutes: 25,
                    difficulty: .easy,
                    ingredients: [
                        I(name: "Chicken breast", amount: "150 g", substitutes: [S(name: "Chicken thigh", amount: "150 g", note: "Juicier, a little more fat"), S(name: "Turkey breast", amount: "150 g", note: "Leaner")]),
                        I(name: "Romaine lettuce", amount: "1 small head", substitutes: [S(name: "Rocket", amount: "2 handfuls", note: "Peppery")]),
                        I(name: "Parmesan", amount: "20 g", substitutes: [S(name: "Nutritional yeast", amount: "1 tbsp", note: "Dairy-free")]),
                        I(name: "Olive oil", amount: "1 tbsp"),
                        I(name: "Lemon juice", amount: "1 tbsp", substitutes: [S(name: "Cider vinegar", amount: "1 tsp")]),
                        I(name: "Plain yogurt", amount: "2 tbsp", substitutes: [S(name: "Mayonnaise", amount: "1 tbsp", note: "Creamier, more calories")]),
                        I(name: "Garlic", amount: "1 clove"),
                        I(name: "Salt and pepper", amount: "To taste"),
                    ],
                    steps: [
                        Step(text: "Pat the chicken dry and rub it with salt, pepper and half the olive oil.", kind: .season),
                        Step(text: "Heat a grill pan over medium-high heat until it is properly hot.", minutes: 3, kind: .heat),
                        Step(text: "Grill the chicken until golden on both sides and no longer pink in the middle.", minutes: 12, kind: .grill),
                        Step(text: "Rest the chicken before slicing so it keeps its juices.", minutes: 5, kind: .rest),
                        Step(text: "Whisk the yogurt, crushed garlic, lemon juice and the rest of the oil into a dressing.", kind: .mix),
                        Step(text: "Chop the lettuce, slice the chicken, toss with the dressing and grate the parmesan over.", kind: .plate),
                    ],
                    tips: ["Marinate the chicken the night before for a softer bite.", "Keep the dressing apart and the salad stays crisp until tomorrow."]
                )
            }
        }
    }
}
#endif
