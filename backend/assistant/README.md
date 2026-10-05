# Assistant Worker

The in-app assistant's server side. Not written yet; this is the contract it has to meet.

- The app sends the conversation and the current plan; the Worker wraps them in our system prompt,
  calls the model, and returns the reply and, when the model proposed one, a plan.
- The provider key and the prompt live here. Change the prompt here, never in the app.
- Requests carry the app token CI writes into the bundle (`DIETFLOW_ASSISTANT_TOKEN`).
- It also serves plan import: text, a photo or a PDF in, a plan out, in the same JSON shape as
  `Domain.MealPlan`.

The plan JSON is the shared contract between this Worker, the MCP server and the app. Its field
names and the `MealSlot` raw values are never renamed.
