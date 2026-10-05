import Foundation

/// A realistic plan for development, previews, the widget gallery and "Reset Sample Data".
/// Fourteen days, so cycling, day changes and long plans all get exercised.
public enum SamplePlan {
    public static func keto(startingOn startDay: CalendarDay, repeats: Bool = true) -> MealPlan {
        var meals: [Meal] = []
        for (index, day) in days.enumerated() {
            for entry in day {
                meals.append(Meal(
                    dayIndex: index,
                    type: entry.type,
                    time: entry.time,
                    title: entry.title,
                    details: entry.details,
                    nutrition: Nutrition(calories: entry.calories, protein: entry.protein, carbohydrates: entry.carbs, fat: entry.fat)
                ))
            }
        }
        return MealPlan(
            name: "14-Day Keto Plan",
            schedule: PlanSchedule(kind: .cycle, startDay: startDay, length: days.count, repeats: repeats),
            meals: meals
        )
    }

    private struct Entry {
        var type: MealType
        var time: TimeOfDay
        var title: String
        var details: String?
        var calories: Int?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
    }

    private static func breakfast(_ title: String, _ details: String? = nil, _ calories: Int? = nil, at hour: Int = 10) -> Entry {
        Entry(type: .breakfast, time: TimeOfDay(hour: hour, minute: 0), title: title, details: details, calories: calories)
    }

    private static func lunch(_ title: String, _ details: String? = nil, _ calories: Int? = nil, at hour: Int = 14) -> Entry {
        Entry(type: .lunch, time: TimeOfDay(hour: hour, minute: 0), title: title, details: details, calories: calories)
    }

    private static func snack(_ title: String, _ details: String? = nil, _ calories: Int? = nil) -> Entry {
        Entry(type: .snack, time: TimeOfDay(hour: 16, minute: 30), title: title, details: details, calories: calories)
    }

    private static func dinner(_ title: String, _ details: String? = nil, _ calories: Int? = nil, at hour: Int = 19, minute: Int = 0) -> Entry {
        Entry(type: .dinner, time: TimeOfDay(hour: hour, minute: minute), title: title, details: details, calories: calories)
    }

    private static let days: [[Entry]] = [
        [
            breakfast("Halloumi, olives and avocado salad", "Halloumi · kalamata olives · avocado", 430),
            Entry(type: .lunch, time: TimeOfDay(hour: 14, minute: 0), title: "Grilled Chicken Caesar Salad", details: "Chicken breast · romaine · parmesan", calories: 510, protein: 42, carbs: 9, fat: 34),
            snack("Celery with almond butter", "2 tbsp almond butter", 190),
            dinner("Steak and Mediterranean salad", "Sirloin · tomato · cucumber · olive oil", 640),
        ],
        [
            breakfast("Feta, cucumber and walnut salad", "Feta · cucumber · walnuts · dill", 410),
            lunch("Grilled chicken with Greek salad", "Chicken thigh · tomato · olives", 560),
            dinner("Beef taco salad, no tortilla", "Ground beef · lettuce · cheddar · salsa", 620),
        ],
        [
            breakfast("Spinach and goat cheese omelette", "Three eggs · spinach · goat cheese", 450),
            lunch("Tuna niçoise, no potatoes", "Tuna · egg · green beans · olives", 520),
            snack("Greek yogurt with walnuts", "Full-fat yogurt · walnuts", 230),
            dinner("Salmon with roasted asparagus", "Salmon fillet · asparagus · lemon butter", 610),
        ],
        [
            breakfast("Smoked salmon and cream cheese roll-ups", "Smoked salmon · cream cheese · chives", 390),
            lunch("Chicken shawarma bowl with tahini", "Chicken · cabbage · tahini", 580),
            dinner("Lamb köfte with cacık", "Lamb köfte · yogurt · cucumber", 650),
        ],
        [
            breakfast("Menemen with feta", "Eggs · peppers · tomato · feta", 420),
            lunch("Shrimp and avocado salad", "Shrimp · avocado · lime", 480),
            dinner("Grilled sea bass with greens", "Sea bass · rocket · olive oil", 560),
        ],
        [
            breakfast("Eggs Benedict on portobello", "Poached eggs · portobello · hollandaise", 520, at: 11),
            lunch("Burger bowl with pickles", "Beef patty · lettuce · pickles · mustard", 610, at: 15),
            dinner("Chicken thighs with cauliflower mash", "Chicken thighs · cauliflower · butter", 640, at: 19, minute: 30),
        ],
        [
            breakfast("Turkish breakfast plate, no bread", "Eggs · white cheese · olives · tomato", 470),
            lunch("Cobb salad", "Chicken · bacon · egg · blue cheese", 590),
            dinner("Ribeye with creamed spinach", "Ribeye · spinach · cream", 720),
        ],
        [
            breakfast("Chia pudding with coconut milk", "Chia · coconut milk · raspberries", 380),
            lunch("Turkey lettuce wraps", "Turkey · avocado · lettuce · mayonnaise", 500),
            snack("Cheese and cucumber slices", "Cheddar · cucumber", 210),
            dinner("Pork chops with green beans", "Pork chop · green beans · garlic butter", 630),
        ],
        [
            breakfast("Bacon and eggs with avocado", "Two eggs · bacon · half an avocado", 540),
            lunch("Salmon poke bowl, cauliflower rice", "Salmon · cauliflower rice · edamame · sesame", 560),
            dinner("Zucchini noodles with meatballs", "Beef meatballs · zucchini · tomato sauce", 600),
        ],
        [
            breakfast("Cottage cheese with cucumber and dill", "Cottage cheese · cucumber · dill", 300),
            lunch("Chicken soup with vegetables", "Chicken · celery · carrot · broth", 450),
            snack("Handful of macadamia nuts", "30 g macadamia", 220),
            dinner("Grilled lamb chops with tzatziki", "Lamb chops · yogurt · cucumber", 690),
        ],
        [
            breakfast("Avocado and egg salad", "Eggs · avocado · lemon", 420),
            lunch("Beef kebab with shepherd's salad", "Beef · tomato · cucumber · onion", 580),
            dinner("Baked cod with pesto", "Cod · pesto · cherry tomatoes", 520),
        ],
        [
            breakfast("Mushroom and cheddar omelette", "Three eggs · mushrooms · cheddar", 470),
            lunch("Chicken and halloumi skewers", "Chicken · halloumi · peppers", 600),
            dinner("Stuffed peppers with ground beef", "Peppers · ground beef · cheese", 610),
        ],
        [
            breakfast("Yogurt with hazelnuts and cinnamon", "Full-fat yogurt · hazelnuts", 350),
            lunch("Tuna-stuffed avocado", "Tuna · avocado · mayonnaise · lemon", 520),
            snack("Olives and white cheese", "Olives · white cheese", 200),
            dinner("Roast chicken with broccoli", "Chicken leg · broccoli · butter", 640),
        ],
        [
            breakfast("Sucuk and eggs", "Sucuk · two eggs", 520),
            lunch("Greek salad with grilled halloumi", "Halloumi · tomato · cucumber · olives", 540),
            dinner("Steak with garlic mushrooms", "Sirloin · mushrooms · garlic butter", 700),
        ],
    ]
}
