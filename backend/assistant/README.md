# Assistant Worker

The plan assistant's server side: it turns a pasted list, however untidy, into a plan, and writes
new plans of up to 30 days from a few wishes.

The app posts text here; this Worker holds the provider key and the prompts, asks the model,
checks and bounds the answer, and returns a plan in the app's interchange format
(`Domain.MealPlanPayload`). The app shows it for review before anything is saved.

| File | Holds |
|---|---|
| `worker.js` | The HTTP side: the app token, rate limits, the provider calls and their fallbacks. |
| `plan.mjs` | Everything else: prompts, cutting a long text into parts, reading and bounding answers. |
| `plan.test.mjs` | Tests for both, with a model stood in for. `node --test backend/assistant/plan.test.mjs` |

Change a prompt in `plan.mjs` and deploy; no app release is needed.

## Endpoints

```
POST /v1/plan/organize  { text, language? }                        -> { plan, parts }
POST /v1/plan/create    { days, mealsPerDay, wishes?, language? }  -> { plan, parts }
GET  /health
```

Requests carry `x-dietflow-app: <APP_TOKEN>` and `x-dietflow-install: <random id>`. Errors are
`{ "error": "<code>" }`: `unauthorized` 401, `too-long` 413, `no-plan` 422 (the text held no
meals), `busy` and `daily-limit` 429, `not-configured` 503, `upstream` 502.

A long text is read in parts of about 5,000 characters, cut where a day begins, and each part is
told which day the last one ended on. A new plan is written a week per model call, each call told
which meals came before so the weeks differ. Either way it is one request from the app.

## What is kept

Nothing a person sends is stored or logged. Logs hold status codes, counts and model names. With
the optional `USAGE` namespace, a request counter per install and day is kept for two days.

## Deploying

```bash
cd backend/assistant
npx wrangler deploy
npx wrangler secret put APP_TOKEN
npx wrangler secret put GROQ_API_KEY
```

Then give the app the address and the token, as repository secrets the TestFlight workflow writes
into the bundle:

```bash
gh secret set DIETFLOW_ASSISTANT_URL -R mericorhay/DietFlow     # https://dietflow-assistant.<account>.workers.dev
gh secret set DIETFLOW_ASSISTANT_TOKEN -R mericorhay/DietFlow   # the APP_TOKEN value
```

`curl https://…/health` shows what is configured. Without both secrets the app hides the
assistant instead of offering something that cannot work.

## Providers

Whichever key is set is used: `GROQ_API_KEY` (Qwen first, then two fallbacks), `OPENAI_API_KEY`
(takes over when set), or `LLM_API_KEY` + `LLM_BASE_URL` + `LLM_MODEL` for any other
OpenAI-compatible service. Groq's free tier allows about 8,000 tokens a minute per model; the part
sizes above are chosen to fit inside it, and a rate-limited call is retried once after the wait
the provider asks for.

## Not done here

The Worker does not check that the caller has paid: the app counts uses against the person's
allowance, and the Worker limits each address and install. Checking the App Store's signed
transaction on the server is the next step if the key is ever abused.

## The provider is named to the person

The app asks for permission before it sends anything here, and names the company whose model
reads the text ("Send this to OpenAI?"). That name is `AssistantProvider.name` in
`Packages/DietFlowKit/Sources/Domain/AppBrand.swift`, and it is also written in `docs/privacy.md`,
`docs/terms.md` and `docs/support.md`. If the Worker is ever pointed at another provider
(`GROQ_API_KEY`, `LLM_BASE_URL`), change all of those in the same release: what the app says and
what the server does have to be the same thing.
