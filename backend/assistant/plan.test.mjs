import assert from "node:assert/strict";
import test from "node:test";
import { LIMITS, PlanError, cleanTime, create, mergeDays, organize, readModelPlan, splitText, toPayload } from "./plan.mjs";
import worker, { asker, candidates } from "./worker.js";

const answer = (days, extra = {}) => JSON.stringify({ name: "", repeats: false, days, ...extra });
const meal = (title, more = {}) => ({ time: "08:00", type: "breakfast", title, details: "", kcal: 0, ...more });

test("a short text is one part", () => {
  assert.deepEqual(splitText("Breakfast: eggs\nLunch: soup"), ["Breakfast: eggs\nLunch: soup"]);
  assert.deepEqual(splitText("   "), []);
});

test("a long text is cut where a day begins, and nothing is lost", () => {
  const day = (n) => `Day ${n}\nBreakfast: eggs and tomatoes with olive oil\nLunch: lentil soup, salad\nDinner: grilled chicken, rice`;
  const text = Array.from({ length: 30 }, (_, index) => day(index + 1)).join("\n");
  const parts = splitText(text, 1_000, 10);
  assert.ok(parts.length > 1);
  for (const part of parts) {
    assert.ok(part.length <= 1_000, `part of ${part.length} characters`);
    assert.match(part, /^Day \d+/, "every part starts on a day line");
  }
  assert.equal(parts.join("\n"), text);
});

test("a single endless line is still cut", () => {
  const parts = splitText("x".repeat(12_000), 5_000, 10);
  assert.deepEqual(parts.map((part) => part.length), [5_000, 5_000, 2_000]);
});

test("times are 24-hour or nothing", () => {
  assert.equal(cleanTime("8:05"), "08:05");
  assert.equal(cleanTime("19.30"), "19:30");
  assert.equal(cleanTime("25:00"), undefined);
  assert.equal(cleanTime("8"), undefined);
  assert.equal(cleanTime(""), undefined);
  assert.equal(cleanTime(null), undefined);
});

test("a model's answer is read out of whatever surrounds it", () => {
  const plan = readModelPlan("Sure! Here it is:\n```json\n" + answer([{ day: 2, meals: [meal("Menemen", { kcal: 430, protein: "22 g" })] }], { name: "Keto" }) + "\n```");
  assert.equal(plan.name, "Keto");
  assert.deepEqual(plan.days, [{ day: 2, meals: [{ title: "Menemen", time: "08:00", type: "breakfast", calories: 430, protein: 22 }] }]);
});

test("what cannot be used is dropped, and everything is bounded", () => {
  const plan = readModelPlan(
    JSON.stringify({
      name: "n".repeat(500),
      repeats: "yes",
      days: [
        { day: 1, meals: [{ title: "" }, { title: "t".repeat(900), time: "noon", kcal: -5, fat: 1e9 }, "junk", null] },
        { day: 99999, meals: [{ details: "only details" }] },
        { day: 3, meals: [] },
        "junk",
      ],
    })
  );
  assert.equal(plan.name.length, LIMITS.planName);
  assert.equal(plan.repeats, false);
  assert.equal(plan.days.length, 2);
  assert.deepEqual(Object.keys(plan.days[0].meals[0]), ["title"]);
  assert.equal(plan.days[0].meals[0].title.length, LIMITS.title);
  // A day number out of range falls back to the day's position in the list.
  assert.deepEqual(plan.days[1], { day: 2, meals: [{ title: "only details" }] });
});

test("an answer with no JSON is not a plan", () => {
  assert.equal(readModelPlan("I cannot help with that."), null);
  assert.equal(readModelPlan("{ not json }"), null);
});

test("a day that came in two parts is joined, and days come out in order", () => {
  const days = mergeDays([[{ day: 2, meals: [{ title: "a" }] }], [{ day: 1, meals: [{ title: "z" }] }, { day: 2, meals: [{ title: "b" }] }]]);
  assert.deepEqual(days, [
    { day: 1, meals: [{ title: "z" }] },
    { day: 2, meals: [{ title: "a" }, { title: "b" }] },
  ]);
});

test("the payload is the app's interchange format", () => {
  assert.deepEqual(toPayload({ name: "Keto", days: [{ day: 3, meals: [{ title: "a" }] }], repeats: true }), {
    schemaVersion: 1,
    repeatCycle: { lengthInDays: 3, repeats: true },
    days: [{ dayIndex: 3, meals: [{ title: "a" }] }],
    name: "Keto",
  });
});

test("organising asks once for a short text", async () => {
  const asked = [];
  const result = await organize(
    async (system, user) => {
      asked.push({ system, user });
      return answer([{ day: 1, meals: [meal("Yumurta")] }], { repeats: true });
    },
    { text: "sabah yumurta", language: "Turkish" }
  );
  assert.equal(asked.length, 1);
  assert.equal(asked[0].user, "sabah yumurta");
  assert.match(asked[0].system, /Copy, never invent/);
  assert.equal(result.parts, 1);
  assert.deepEqual(result.plan.repeatCycle, { lengthInDays: 1, repeats: true });
});

test("a long text is organised part by part, and each part is told where the last one ended", async () => {
  const line = "Kahvaltı: 2 yumurta, domates, salatalık, zeytin, tam buğday ekmeği";
  const text = Array.from({ length: 20 }, (_, index) => `${index + 1}. Gün\n${line}\n${line}\n${line}\n${line}\n${line}`).join("\n");
  assert.ok(text.length > LIMITS.partChars);
  const systems = [];
  const result = await organize(
    async (system, user) => {
      systems.push(system);
      const days = [...user.matchAll(/^(\d+)\. Gün/gm)].map((match) => ({ day: Number(match[1]), meals: [meal("Kahvaltı")] }));
      return answer(days);
    },
    { text, language: "Turkish" }
  );
  assert.ok(systems.length > 1);
  assert.equal(result.parts, systems.length);
  assert.match(systems[1], /part 2 of/);
  assert.match(systems[1], /ended on day \d+/);
  assert.deepEqual(result.plan.days.map((day) => day.dayIndex), Array.from({ length: 20 }, (_, index) => index + 1));
});

test("organising refuses what it cannot or should not read", async () => {
  const never = async () => assert.fail("the model must not be asked");
  await assert.rejects(organize(never, { text: "  " }), (error) => error instanceof PlanError && error.code === "empty");
  await assert.rejects(organize(never, { text: "x".repeat(LIMITS.textChars + 1) }), (error) => error.code === "too-long" && error.status === 413);
  await assert.rejects(organize(async () => answer([]), { text: "hello there" }), (error) => error.code === "no-plan" && error.status === 422);
  await assert.rejects(organize(async () => "no json here", { text: "hello there" }), (error) => error.code === "unreadable-answer");
});

test("a thirty-day plan is written a week at a time, each call told what came before", async () => {
  const calls = [];
  const result = await create(
    async (system, user) => {
      const [, from, to] = system.match(/Write days (\d+) to (\d+)/).map(Number);
      calls.push({ from, to, system, user });
      const days = [];
      for (let day = from; day <= to; day += 1) days.push({ day, meals: [meal(`Meal ${day}`, { kcal: 400 })] });
      return answer(days, { name: "Thirty days" });
    },
    { days: 30, mealsPerDay: 4, wishes: "keto, no fish", language: "English" }
  );
  assert.deepEqual(calls.map((call) => [call.from, call.to]), [[1, 7], [8, 14], [15, 21], [22, 28], [29, 30]]);
  assert.match(calls[0].user, /keto, no fish/);
  assert.match(calls[1].system, /Meal 7/);
  assert.equal(result.plan.days.length, 30);
  assert.deepEqual(result.plan.repeatCycle, { lengthInDays: 30, repeats: false });
  assert.equal(result.plan.name, "Thirty days");
  assert.equal(result.plan.days[29].meals[0].calories, 400);
  // Figures in a written plan are estimates, and say so.
  assert.equal(result.plan.days[29].meals[0].estimated, true);
  assert.match(calls[0].system, /portion/);
  assert.match(calls[0].system, /4 × protein/);
});

test("a written meal without figures is not marked as an estimate, and a portion is kept", async () => {
  const result = await create(async () => answer([{ day: 1, meals: [meal("Soup", { portion: "1 bowl" }), meal("Bread")] }]), { days: 1, mealsPerDay: 2 });
  const [soup, bread] = result.plan.days[0].meals;
  assert.equal(soup.portion, "1 bowl");
  assert.equal(soup.estimated, undefined);
  assert.equal(bread.estimated, undefined);
});

test("organising copies a stated portion and never marks anything as estimated", async () => {
  const result = await organize(async () => answer([{ day: 1, meals: [meal("Oats", { portion: "50 g", kcal: 190 })] }]), { text: "Day 1: oats 50 g, 190 kcal" });
  const [oats] = result.plan.days[0].meals;
  assert.equal(oats.portion, "50 g");
  assert.equal(oats.calories, 190);
  assert.equal(oats.estimated, undefined);
});

test("days a model numbers wrongly are put back where they were asked for", async () => {
  const result = await create(async () => answer([{ day: 1, meals: [meal("a")] }, { day: 2, meals: [meal("b")] }]), { days: 9, mealsPerDay: 3 });
  // Three calls (1-7, 8-9, and nothing left over): the second call's "day 1, day 2" become 8 and 9.
  assert.deepEqual(result.plan.days.map((day) => day.dayIndex), [1, 2, 8, 9]);
});

test("creating refuses numbers out of range before asking anything", async () => {
  const never = async () => assert.fail("the model must not be asked");
  await assert.rejects(create(never, { days: 31, mealsPerDay: 3 }), (error) => error.code === "bad-days");
  await assert.rejects(create(never, { days: 0, mealsPerDay: 3 }), (error) => error.code === "bad-days");
  await assert.rejects(create(never, { days: 7, mealsPerDay: 99 }), (error) => error.code === "bad-meals");
  await assert.rejects(create(never, { days: 7, mealsPerDay: 3, wishes: "w".repeat(LIMITS.wishesChars + 1) }), (error) => error.code === "too-long");
});

test("the provider with a key is the one used", () => {
  assert.deepEqual(candidates({}), []);
  assert.deepEqual(candidates({ GROQ_API_KEY: "g" }).map((entry) => entry.model), ["qwen/qwen3.8-27b", "openai/gpt-oss-120b", "openai/gpt-oss-20b"]);
  assert.equal(candidates({ GROQ_API_KEY: "g", OPENAI_API_KEY: "o" })[0].url, "https://api.openai.com/v1");
  assert.deepEqual(candidates({ LLM_API_KEY: "k", LLM_BASE_URL: "https://example.test/v1/", LLM_MODEL: "m" }), [{ url: "https://example.test/v1", key: "k", model: "m" }]);
});

test("a model that fails hands over to the next; a bad key stops at once", async () => {
  const reply = (content) => new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 });
  const tried = [];
  const ask = asker({ GROQ_API_KEY: "g" }, async (url, options) => {
    const model = JSON.parse(options.body).model;
    tried.push(model);
    return model === "qwen/qwen3.8-27b" ? new Response("", { status: 500 }) : reply("{}");
  });
  assert.equal(await ask("system", "user"), "{}");
  assert.deepEqual(tried, ["qwen/qwen3.8-27b", "openai/gpt-oss-120b"]);

  let calls = 0;
  const denied = asker({ GROQ_API_KEY: "bad" }, async () => {
    calls += 1;
    return new Response("", { status: 401 });
  });
  await assert.rejects(denied("system", "user"), (error) => error.code === "upstream");
  assert.equal(calls, 1);

  await assert.rejects(asker({})("system", "user"), (error) => error.code === "not-configured" && error.status === 503);
});

test("the worker answers only the app, and words every refusal as a code", async () => {
  const env = { APP_TOKEN: "secret" };
  const post = (path, body, headers = {}) =>
    worker.fetch(new Request(`https://worker.test${path}`, { method: "POST", headers: { "x-dietflow-app": "secret", ...headers }, body: JSON.stringify(body) }), env);

  const wrongToken = await worker.fetch(new Request("https://worker.test/v1/plan/organize", { method: "POST", headers: { "x-dietflow-app": "nope" }, body: "{}" }), env);
  assert.equal(wrongToken.status, 401);

  assert.equal((await worker.fetch(new Request("https://worker.test/v1/plan/organize"), env)).status, 405);
  assert.equal((await post("/v1/unknown", {})).status, 404);
  assert.deepEqual(await (await post("/v1/plan/organize", { text: "" })).json(), { error: "empty" });
  // No provider key: the request is well formed, the service is simply not set up.
  const unconfigured = await post("/v1/plan/organize", { text: "sabah yumurta" });
  assert.equal(unconfigured.status, 503);
  assert.deepEqual(await unconfigured.json(), { error: "not-configured" });

  const health = await (await worker.fetch(new Request("https://worker.test/health"), env)).json();
  assert.equal(health.provider, "none");
  assert.equal(health.appTokenConfigured, true);
});

test("an install over its daily limit is told so, and the model is not asked", async () => {
  const counts = new Map();
  const env = {
    APP_TOKEN: "secret",
    DAILY_REQUESTS: "2",
    USAGE: { get: async (key) => counts.get(key), put: async (key, value) => counts.set(key, value) },
  };
  const post = () =>
    worker.fetch(
      new Request("https://worker.test/v1/plan/organize", { method: "POST", headers: { "x-dietflow-app": "secret", "x-dietflow-install": "abc-123" }, body: JSON.stringify({ text: "" }) }),
      env
    );
  assert.equal((await post()).status, 400);
  assert.equal((await post()).status, 400);
  const third = await post();
  assert.equal(third.status, 429);
  assert.deepEqual(await third.json(), { error: "daily-limit" });
});
