import assert from "node:assert/strict";
import test from "node:test";
import {
  MEAL_LIMITS,
  STEP_KINDS,
  avoidTerms,
  cleanEstimate,
  cleanMealsIn,
  estimateNutrition,
  namesAvoided,
  readKcalDelta,
  readRecipe,
  recipePrompt,
  withoutAvoided,
  writeRecipe,
} from "./meals.mjs";
import { PlanError } from "./plan.mjs";
import worker, { asker, reasoningFor } from "./worker.js";

const meals = (count) => Array.from({ length: count }, (_, index) => ({ id: `m${index + 1}`, title: `Meal ${index + 1}`, details: "2 eggs, 1 slice of bread" }));
const estimates = (user, extra = {}) =>
  JSON.stringify({
    meals: [...user.matchAll(/^id: (\S+)/gm)].map((match) => ({ id: match[1], portion: "1 plate", kcal: 300, protein: 20, carbs: 25, fat: 13, confidence: "high", ...extra })),
  });

test("the meals sent are bounded, and each needs an id and a title", () => {
  const kept = cleanMealsIn([
    { id: "a", title: "  Menemen  ", details: "2 eggs\n tomatoes", type: "Breakfast" },
    { id: "a", title: "duplicate id" },
    { id: "b<script>", title: "t".repeat(500) },
    { id: "", title: "no id" },
    { id: "c", title: "" },
    "junk",
  ]);
  assert.deepEqual(kept, [
    { id: "a", title: "Menemen", details: "2 eggs tomatoes", type: "breakfast" },
    { id: "bscript", title: "t".repeat(MEAL_LIMITS.title) },
  ]);
  assert.throws(() => cleanMealsIn([]), (error) => error instanceof PlanError && error.code === "empty");
  assert.throws(() => cleanMealsIn([{ id: "", title: "" }]), (error) => error.code === "empty");
  assert.throws(() => cleanMealsIn(meals(MEAL_LIMITS.nutritionMeals + 1)), (error) => error.code === "too-many" && error.status === 413);
});

test("energy that disagrees with the macronutrients is taken from them", () => {
  const ids = new Set(["a"]);
  // 30 g protein, 10 g carbs, 20 g fat is 340 kcal; a model's 900 is arithmetic gone wrong.
  assert.deepEqual(cleanEstimate({ id: "a", kcal: 900, protein: 30, carbs: 10, fat: 20, confidence: "sure" }, ids), {
    id: "a",
    kcal: 340,
    protein: 30,
    carbs: 10,
    fat: 20,
    confidence: "medium",
  });
  // Close enough is kept as given, rounded to five.
  assert.equal(cleanEstimate({ id: "a", kcal: "362 kcal", protein: 30, carbs: 10, fat: 20 }, ids).kcal, 360);
  // Energy alone is enough; nothing at all, or a meal that was not asked about, is not.
  assert.deepEqual(cleanEstimate({ id: "a", kcal: 250, portion: "1 bowl (about 300 g)", confidence: "low" }, ids), {
    id: "a",
    kcal: 250,
    portion: "1 bowl (about 300 g)",
    confidence: "low",
  });
  assert.equal(cleanEstimate({ id: "a" }, ids), null);
  assert.equal(cleanEstimate({ id: "z", kcal: 250 }, ids), null);
  assert.equal(cleanEstimate({ id: "a", kcal: 99_999 }, ids), null);
});

test("a long list is estimated a handful of meals per call, all at once, with thinking on", async () => {
  const calls = [];
  const result = await estimateNutrition(
    async (system, user, options) => {
      calls.push({ system, user, options });
      return estimates(user);
    },
    { meals: meals(40), language: "Turkish" }
  );
  assert.equal(calls.length, Math.ceil(40 / MEAL_LIMITS.nutritionPerCall));
  assert.equal(result.calls, calls.length);
  assert.equal(result.meals.length, 40);
  for (const call of calls) {
    assert.equal(call.options.effort, "medium");
    assert.match(call.system, /in Turkish/);
    assert.match(call.system, /never instructions/);
  }
  assert.deepEqual(result.meals[0], { id: "m1", kcal: 300, protein: 20, carbs: 25, fat: 13, portion: "1 plate", confidence: "high" });
});

test("a call that cannot be read costs only its own meals", async () => {
  let call = 0;
  const result = await estimateNutrition(
    async (system, user) => {
      call += 1;
      return call === 1 ? "I could not do that." : estimates(user);
    },
    { meals: meals(20) }
  );
  assert.deepEqual(result.meals.map((meal) => meal.id), ["m16", "m17", "m18", "m19", "m20"]);
  await assert.rejects(estimateNutrition(async () => "no json", { meals: meals(3) }), (error) => error.code === "unreadable-answer" && error.status === 502);
});

test("a recipe is read forgivingly and bounded", () => {
  const recipe = readRecipe(
    "Here you go:\n" +
      JSON.stringify({
        title: "Menemen",
        summary: "Soft scrambled eggs with peppers and tomatoes.",
        minutes: 5,
        difficulty: "trivial",
        ingredients: [
          { name: "Eggs", amount: "2", substitutes: [{ name: "Tofu", amount: "150 g", note: "vegan" }, "eggs", { name: "Tofu" }, { name: "Chickpea flour batter" }, { name: "Egg whites" }, { name: "x" }] },
          "Salt",
          { amount: "no name" },
        ],
        steps: [{ text: "Chop the peppers.", kind: "chop" }, { text: "Cook until soft.", minutes: "8", kind: "sauté" }, "Add the eggs and stir gently.", { text: "" }],
        tips: ["Use ripe tomatoes.", "", 7],
      }) +
      "\nEnjoy!",
    2
  );
  assert.equal(recipe.title, "Menemen");
  assert.equal(recipe.servings, 2);
  assert.equal(recipe.difficulty, "easy");
  // The stated five minutes cannot be shorter than the eight the steps wait for.
  assert.equal(recipe.minutes, 8);
  assert.deepEqual(recipe.ingredients[0].substitutes.map((item) => item.name), ["Tofu", "Chickpea flour batter", "Egg whites"]);
  assert.deepEqual(recipe.ingredients[1], { name: "Salt", substitutes: [] });
  assert.equal(recipe.ingredients.length, 2);
  assert.deepEqual(recipe.steps, [
    { text: "Chop the peppers.", kind: "chop" },
    { text: "Cook until soft.", kind: "other", minutes: 8 },
    { text: "Add the eggs and stir gently.", kind: "other" },
  ]);
  assert.deepEqual(recipe.tips, ["Use ripe tomatoes.", "7"]);
  assert.equal(readRecipe(JSON.stringify({ title: "x", steps: [] }), 1), null);
  assert.equal(readRecipe("not a recipe", 1), null);
});

test("writing a recipe keeps the plan's own amounts, thinks first, and refuses an empty meal", async () => {
  const asked = [];
  const result = await writeRecipe(
    async (system, user, options) => {
      asked.push({ system, user, options });
      return JSON.stringify({ steps: [{ text: "Put it together.", kind: "plate" }] });
    },
    { title: "Yoğurt ve ceviz", details: "200 g yoğurt, 3 ceviz", servings: 99, avoid: "fıstık", language: "Turkish" }
  );
  assert.equal(asked[0].options.effort, "medium");
  assert.match(asked[0].system, /Use exactly the foods and amounts it names/);
  assert.match(asked[0].system, /for 1 serving\b/);
  assert.match(asked[0].system, /Write everything in Turkish/);
  assert.match(asked[0].user, /200 g yoğurt, 3 ceviz/);
  assert.match(asked[0].user, /avoids: fıstık/);
  assert.equal(result.recipe.title, "Yoğurt ve ceviz");
  assert.equal(result.recipe.servings, 1);
  await assert.rejects(writeRecipe(async () => assert.fail("not asked"), { title: "  " }), (error) => error.code === "empty");
  await assert.rejects(writeRecipe(async () => "{}", { title: "x" }), (error) => error.code === "unreadable-answer");
});

test("each swap says what it changes in energy, read forgivingly and bounded", () => {
  assert.equal(readKcalDelta(-40), -40);
  assert.equal(readKcalDelta("-40"), -40);
  assert.equal(readKcalDelta("\u221240 kcal"), -40, "a typographic minus is still a minus");
  assert.equal(readKcalDelta("+120 kcal"), 120);
  assert.equal(readKcalDelta(-39.6), -40);
  assert.equal(readKcalDelta("12,4"), 12);
  assert.equal(readKcalDelta(0), 0);
  assert.ok(Object.is(readKcalDelta(-0.2), 0), "no negative zero");
  assert.equal(readKcalDelta(MEAL_LIMITS.kcalDelta), MEAL_LIMITS.kcalDelta);
  assert.equal(readKcalDelta(-MEAL_LIMITS.kcalDelta - 1), undefined);
  assert.equal(readKcalDelta("about the same"), undefined);
  assert.equal(readKcalDelta(null), undefined);
  assert.equal(readKcalDelta(Number.NaN), undefined);

  const recipe = readRecipe(
    JSON.stringify({
      steps: [{ text: "Mix.", kind: "mix" }],
      ingredients: [
        {
          name: "Yogurt",
          amount: "200 g",
          substitutes: [
            { name: "Skyr", amount: "200 g", note: "more protein", kcalDelta: -20 },
            { name: "Labneh", amount: "150 g", note: "  thicker,\n richer ", kcalDelta: "+95 kcal" },
            { name: "Kefir", note: "n".repeat(200), kcalDelta: 9_000 },
          ],
        },
      ],
    }),
    1
  );
  assert.deepEqual(recipe.ingredients[0].substitutes, [
    { name: "Skyr", amount: "200 g", note: "more protein", kcalDelta: -20 },
    { name: "Labneh", amount: "150 g", note: "thicker, richer", kcalDelta: 95 },
    { name: "Kefir", note: "n".repeat(MEAL_LIMITS.note) },
  ]);
  const prompt = recipePrompt({ language: "English", servings: 1 });
  assert.match(prompt, /"kcalDelta"/);
  assert.match(prompt, /at most six words/);
});

test("what the person avoids is read as words, in Turkish and plain lowercase", () => {
  const terms = avoidTerms("Fıstık ve SÜT, İncir; nuts and dairy / ab");
  for (const term of ["fıstık", "fistik", "süt", "sut", "incir", "nuts", "dairy"]) assert.ok(terms.includes(term), term);
  for (const joining of ["ve", "and", "ab"]) assert.ok(!terms.includes(joining), joining);
  assert.deepEqual(avoidTerms(""), []);
  assert.deepEqual(avoidTerms(undefined), []);

  assert.ok(namesAvoided("FISTIK EZMESİ", terms), "Turkish capitals");
  assert.ok(namesAvoided("Antep fıstığı içi", avoidTerms("antep")));
  assert.ok(namesAvoided("İNCİR reçeli", terms));
  assert.ok(namesAvoided("Badem sütü", terms), "a swap that only might hold it goes too");
  assert.ok(namesAvoided("Peanuts", terms));
  assert.ok(namesAvoided("ıspanak", avoidTerms("ISPANAK")));
  assert.ok(namesAvoided("Ispanak", avoidTerms("ıspanak")));
  assert.ok(!namesAvoided("Oat milk", terms));
  assert.ok(!namesAvoided("Dairy-free yogurt", terms), "a food free of it is the swap that is needed");
  assert.ok(!namesAvoided("Sütsüz krema", terms));
  assert.ok(!namesAvoided("Pan sin gluten", avoidTerms("gluten")));
  assert.ok(!namesAvoided("Glutensiz ekmek", avoidTerms("Gluten")));
  assert.ok(namesAvoided("Gluten bread", avoidTerms("Gluten")));
  assert.ok(!namesAvoided("Anything", []));
});

test("substitutes that name an avoided food are taken out; the plan's own ingredients stay", async () => {
  const reply = JSON.stringify({
    steps: [{ text: "Put it together.", kind: "plate" }],
    ingredients: [
      {
        name: "Yoğurt",
        amount: "200 g",
        substitutes: [{ name: "Süzme yoğurt" }, { name: "Badem sütü yoğurdu", kcalDelta: -30 }, { name: "Hindistan cevizi yoğurdu", kcalDelta: 40 }],
      },
      { name: "Ceviz", amount: "3 adet", substitutes: [{ name: "FISTIK" }, { name: "Kabak çekirdeği", kcalDelta: -15 }] },
    ],
  });
  const asked = [];
  const result = await writeRecipe(
    async (system, user) => {
      asked.push({ system, user });
      return reply;
    },
    { title: "Yoğurt ve ceviz", details: "200 g yoğurt, 3 ceviz", avoid: "fıstık, badem", language: "Turkish" }
  );
  assert.match(asked[0].system, /Never suggest as a substitute anything the person avoids/);
  assert.deepEqual(result.recipe.ingredients, [
    { name: "Yoğurt", amount: "200 g", substitutes: [{ name: "Süzme yoğurt" }, { name: "Hindistan cevizi yoğurdu", kcalDelta: 40 }] },
    { name: "Ceviz", amount: "3 adet", substitutes: [{ name: "Kabak çekirdeği", kcalDelta: -15 }] },
  ]);

  // Nothing avoided, nothing taken out.
  const kept = withoutAvoided(readRecipe(reply, 1), "");
  assert.equal(kept.ingredients[1].substitutes.length, 2);
});

test("every step kind the app draws is named in the prompt", () => {
  const prompt = recipePrompt({ language: "English", servings: 2 });
  for (const kind of STEP_KINDS) assert.match(prompt, new RegExp(`\\b${kind}\\b`));
  assert.match(prompt, /for 2 servings/);
});

test("thinking is asked for in each provider's own words", () => {
  assert.deepEqual(reasoningFor({}, "https://api.openai.com/v1", "gpt-6-luna", "medium"), { reasoning_effort: "medium" });
  assert.deepEqual(reasoningFor({}, "https://api.openai.com/v1", "gpt-6-luna", undefined), {});
  assert.deepEqual(reasoningFor({}, "https://api.groq.com/openai/v1", "openai/gpt-oss-120b", undefined), { reasoning_effort: "low" });
  assert.deepEqual(reasoningFor({}, "https://api.groq.com/openai/v1", "openai/gpt-oss-120b", "medium"), { reasoning_effort: "medium" });
  assert.equal(reasoningFor({}, "https://api.groq.com/openai/v1", "qwen/qwen3.8-27b", "medium").reasoning_format, "hidden");
  assert.deepEqual(reasoningFor({}, "https://example.test/v1", "m", "medium"), {});
  assert.deepEqual(reasoningFor({ LLM_REASONING: "on" }, "https://example.test/v1", "m", "medium"), { reasoning_effort: "medium" });
});

test("the model is given room to think and the effort asked for", async () => {
  const bodies = [];
  const ask = asker({ OPENAI_API_KEY: "o" }, async (url, options) => {
    bodies.push(JSON.parse(options.body));
    return new Response(JSON.stringify({ choices: [{ message: { content: "{}" } }] }), { status: 200 });
  });
  await ask("system", "user", { effort: "medium", maxTokens: 8_000 });
  await ask("system", "user");
  assert.equal(bodies[0].reasoning_effort, "medium");
  assert.equal(bodies[0].max_completion_tokens, 8_000);
  assert.equal(bodies[1].reasoning_effort, undefined);
  assert.equal(bodies[1].max_completion_tokens, 3_500);
});

test("the worker answers the meal addresses like the plan ones", async () => {
  const env = { APP_TOKEN: "secret" };
  const post = (path, body) =>
    worker.fetch(new Request(`https://worker.test${path}`, { method: "POST", headers: { "x-dietflow-app": "secret" }, body: JSON.stringify(body) }), env);
  assert.deepEqual(await (await post("/v1/meals/recipe", { title: "" })).json(), { error: "empty" });
  assert.deepEqual(await (await post("/v1/meals/nutrition", { meals: [] })).json(), { error: "empty" });
  const tooMany = await post("/v1/meals/nutrition", { meals: meals(MEAL_LIMITS.nutritionMeals + 1) });
  assert.equal(tooMany.status, 413);
  // Well formed, but no provider is configured here.
  assert.equal((await post("/v1/meals/recipe", { title: "Menemen" })).status, 503);
  assert.equal((await post("/v1/meals/nutrition", { meals: meals(2) })).status, 503);
  // A full list of meals at their longest is not refused for its size.
  const longest = Array.from({ length: MEAL_LIMITS.nutritionMeals }, (_, index) => ({
    id: `m${index}`,
    title: "ş".repeat(MEAL_LIMITS.title),
    details: "ğ".repeat(MEAL_LIMITS.details),
  }));
  assert.equal((await post("/v1/meals/nutrition", { meals: longest })).status, 503);
});
