// DietFlow plan assistant — a Cloudflare Worker.
//
// The app never holds a model provider's key. It posts a pasted list, or a few wishes, here; this
// Worker holds the key, owns the prompts (plan.mjs), asks the model, checks and bounds what comes
// back, and returns a plan in the app's interchange format. The app then shows that plan for
// review like any other import: nothing the model writes is saved without the person seeing it.
//
// Nothing a person sends is stored or logged. Logs hold status codes, sizes and model names only.
//
// Secrets (set with `wrangler secret put`, never committed):
//   APP_TOKEN        must match "appToken" in the app's AssistantEndpoint.json
//   GROQ_API_KEY     the provider key, or
//   OPENAI_API_KEY   which takes over when set, or
//   LLM_API_KEY      with LLM_BASE_URL and LLM_MODEL, for any other OpenAI-compatible provider
//
// POST /v1/plan/organize  { text, language? }                          -> { plan, parts }
// POST /v1/plan/create    { days, mealsPerDay, wishes?, language? }    -> { plan, parts }
// GET  /health                                                         -> what is configured
//
// Errors are { error: "<code>" } with a matching status; the app words them for the person.

import { LIMITS, PlanError, create, organize } from "./plan.mjs";

const GROQ_URL = "https://api.groq.com/openai/v1";
const GROQ_MODELS = ["qwen/qwen3.8-27b", "openai/gpt-oss-120b", "openai/gpt-oss-20b"];
const OPENAI_URL = "https://api.openai.com/v1";
const OPENAI_MODEL = "gpt-6-luna";
// Room for one part of a plan: about a week of meals.
const MAX_ANSWER_TOKENS = 3500;
// Requests a day from one install, when a KV namespace is bound as USAGE.
const DAILY_REQUESTS = 40;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

/// The models to try, in order. A provider with a key is used; without any, nothing is.
export function candidates(env) {
  if (env.LLM_API_KEY && env.LLM_BASE_URL && env.LLM_MODEL) {
    return [{ url: env.LLM_BASE_URL.replace(/\/+$/, ""), key: env.LLM_API_KEY, model: env.LLM_MODEL }];
  }
  if (env.OPENAI_API_KEY) {
    return [{ url: OPENAI_URL, key: env.OPENAI_API_KEY, model: env.OPENAI_MODEL || OPENAI_MODEL }];
  }
  if (env.GROQ_API_KEY) {
    const models = env.GROQ_MODEL ? [env.GROQ_MODEL, ...GROQ_MODELS.filter((model) => model !== env.GROQ_MODEL)] : GROQ_MODELS;
    return models.map((model) => ({ url: GROQ_URL, key: env.GROQ_API_KEY, model }));
  }
  return [];
}

// A provider connection must not keep the app's spinner turning forever.
async function fetchUpstream(url, options, timeoutMilliseconds = 90_000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMilliseconds);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } catch (error) {
    console.log("upstream fetch failed", error && error.name ? error.name : "network");
    return new Response("", { status: 504 });
  } finally {
    clearTimeout(timer);
  }
}

/// One question to the model, one answer back as text. Tries each candidate in turn.
export function asker(env, send = fetchUpstream) {
  const models = candidates(env);
  return async function ask(system, user) {
    if (!models.length) throw new PlanError("not-configured", 503);
    let status = 502;
    for (const { url, key, model } of models) {
      const call = (asJSON) =>
        send(`${url}/chat/completions`, {
          method: "POST",
          headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
          body: JSON.stringify({
            model,
            max_completion_tokens: MAX_ANSWER_TOKENS,
            messages: [
              { role: "system", content: system },
              { role: "user", content: user },
            ],
            ...(asJSON ? { response_format: { type: "json_object" } } : {}),
            ...(model.startsWith("openai/gpt-oss") ? { reasoning_effort: "low" } : {}),
            // Qwen thinks out loud unless told not to show it; only the JSON is wanted.
            ...(model.startsWith("qwen/") ? { reasoning_format: "hidden", temperature: 0.4, top_p: 0.95 } : {}),
          }),
        });

      let upstream = await call(true);
      // A per-minute limit that clears in a few seconds is worth one wait: a long plan is asked
      // for in several calls, and the second one often arrives inside the same minute.
      if (upstream.status === 429) {
        const wait = Number(upstream.headers.get("retry-after") || 0);
        if (wait > 0 && wait <= 20) {
          await new Promise((resolve) => setTimeout(resolve, wait * 1000));
          upstream = await call(true);
        }
      }
      // JSON mode can refuse an answer it could not make valid; ask again without it and let
      // plan.mjs find the object in whatever comes back.
      if (upstream.status === 400) upstream = await call(false);

      if (upstream.ok) {
        const result = await upstream.json().catch(() => null);
        const reply = result && result.choices && result.choices[0] && result.choices[0].message && result.choices[0].message.content;
        if (typeof reply === "string" && reply.trim()) return reply;
        console.log(model, "empty reply");
        status = 502;
        continue;
      }
      console.log(model, "error", upstream.status);
      status = upstream.status;
      // A bad key will not get better on another model.
      if (upstream.status === 401 || upstream.status === 403) break;
    }
    throw new PlanError(status === 429 ? "busy" : "upstream", status === 429 ? 429 : 502);
  };
}

/// Counts today's requests from one install. Without a USAGE namespace nothing is counted.
async function withinDailyLimit(env, install) {
  if (!env.USAGE || !install) return true;
  const key = `d:${install}:${new Date().toISOString().slice(0, 10)}`;
  const used = Number((await env.USAGE.get(key)) || 0);
  if (used >= Number(env.DAILY_REQUESTS || DAILY_REQUESTS)) return false;
  // Kept two days, so yesterday's count is gone by itself.
  await env.USAGE.put(key, String(used + 1), { expirationTtl: 172_800 });
  return true;
}

function health(env) {
  const models = candidates(env);
  return json({
    ok: true,
    appTokenConfigured: Boolean(env.APP_TOKEN),
    provider: models.length ? new URL(models[0].url).host : "none",
    models: models.map((entry) => entry.model),
    perMinuteLimit: env.LIMITER ? "on" : "off",
    dailyLimit: env.USAGE ? Number(env.DAILY_REQUESTS || DAILY_REQUESTS) : "off",
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "");
    if (request.method === "GET" && path === "/health") return health(env);
    if (request.method !== "POST") return json({ error: "method" }, 405);
    if (!env.APP_TOKEN || request.headers.get("x-dietflow-app") !== env.APP_TOKEN) {
      console.log("unauthorized: app token missing or different from APP_TOKEN");
      return json({ error: "unauthorized" }, 401);
    }

    // One address sending more than the limit is told to wait instead of spending the key.
    if (env.LIMITER) {
      const { success } = await env.LIMITER.limit({ key: request.headers.get("cf-connecting-ip") || "unknown" });
      if (!success) return json({ error: "busy" }, 429);
    }

    // The largest honest request is a full-length text and a little JSON around it.
    const maxBody = LIMITS.textChars * 4 + 2_000;
    if (Number(request.headers.get("content-length") || 0) > maxBody) return json({ error: "too-long" }, 413);
    let body;
    try {
      const raw = await request.text();
      if (raw.length > maxBody) return json({ error: "too-long" }, 413);
      body = JSON.parse(raw);
    } catch {
      return json({ error: "bad-json" }, 400);
    }
    if (!body || typeof body !== "object") return json({ error: "bad-json" }, 400);

    const handler = path === "/v1/plan/organize" ? organize : path === "/v1/plan/create" ? create : null;
    if (!handler) return json({ error: "not-found" }, 404);

    const install = String(request.headers.get("x-dietflow-install") || "").replace(/[^A-Za-z0-9-]/g, "").slice(0, 64);
    if (!(await withinDailyLimit(env, install))) return json({ error: "daily-limit" }, 429);

    const language = typeof body.language === "string" ? body.language.replace(/[^\p{L} ()-]/gu, "").slice(0, 40) : "";
    try {
      const result = await handler(asker(env), { ...body, language });
      console.log(path, "ok", "parts", result.parts, "days", result.plan.days.length);
      return json(result);
    } catch (error) {
      if (error instanceof PlanError) {
        console.log(path, "refused", error.code);
        return json({ error: error.code }, error.status);
      }
      console.log(path, "failed", error && error.name ? error.name : "error");
      return json({ error: "failed" }, 500);
    }
  },
};
