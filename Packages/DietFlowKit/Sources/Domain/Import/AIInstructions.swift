import Foundation

extension MealPlanPayload {
    /// What "Copy AI Instructions" puts on the clipboard. The person pastes it into ChatGPT,
    /// Claude or any other assistant together with their plan, and pastes the reply back into
    /// Paste Plan. Kept in English on purpose: every model follows English instructions, and the
    /// instructions tell it to keep the plan's own language for meal names.
    public static let aiInstructions = #"""
    Convert my meal plan into JSON for my meal planner app. Reply with only the JSON, no other text.

    Format:
    {
      "schemaVersion": 1,
      "name": "Plan name",
      "startDate": "YYYY-MM-DD",
      "repeatCycle": { "lengthInDays": 14, "repeats": true },
      "days": [
        {
          "dayIndex": 1,
          "meals": [
            {
              "time": "HH:MM",
              "type": "breakfast | snack | lunch | dinner | other",
              "title": "Short meal name",
              "description": "Ingredients or portion, optional",
              "calories": 430,
              "protein": 22,
              "carbs": 9,
              "fat": 34,
              "notes": "Optional"
            }
          ]
        }
      ]
    }

    Rules:
    - dayIndex starts at 1. Include every day of the plan, in order.
    - time uses 24-hour HH:MM. If the plan gives no time, leave "time" out; do not guess.
    - Use "other" for a meal that is not breakfast, a snack, lunch or dinner, and put its name in the title.
    - Only include calories, protein, carbs and fat when the plan states them. Never estimate them.
    - Keep meal names and descriptions in the plan's own language.
    - If the plan repeats (for example the same week every week), set "repeats" to true; if it ends after the last day, set it to false.
    - Leave "startDate" out unless the plan says when it starts.

    My plan:
    """#
}
