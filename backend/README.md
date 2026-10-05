# Backend

Two Cloudflare Workers. Neither holds anything in the repository that is secret: keys are set
with `wrangler secret put`.

| Worker | For | The app's side |
|---|---|---|
| [`assistant/`](assistant/README.md) | The in-app AI. Holds the provider key and the system prompt. | `AIServices` |
| [`mcp/`](mcp/README.md) | The MCP server Claude connects to, and the plan sync the phone pulls from. | `PlanSync` |

They are separate because they fail differently and are trusted differently: the assistant is
called by the app with an app token, the MCP server is called by a third party on a person's behalf.
