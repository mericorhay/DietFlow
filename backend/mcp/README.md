# MCP Worker

A remote MCP server, so Claude (or any MCP client) can read and write a person's plan. Not written
yet; this is the contract it has to meet.

## Why a server

A phone cannot be reached from outside, so it cannot be the MCP server. The server is ours and
holds the plan; the phone pairs with it once and pulls.

## Tools

| Tool | Does |
|---|---|
| `get_plan` | Returns the active plan. |
| `set_plan` | Replaces the plan with a full new one. |
| `set_day` | Replaces one day of the cycle. |
| `get_today` | Returns today's meals for the person's time zone, with the next one marked. |

Plans use the same JSON shape as `Domain.MealPlan` in the app.

## Pairing

1. The app asks for a pairing code and shows it.
2. The person adds the server to Claude as a connector and signs in with that code.
3. The server issues the phone a device token (`PlanSync.SyncCredential`).
4. After a tool writes a plan, the phone pulls it and activates it like any other plan.

A plan written through MCP belongs to one paired account; a token never reads another's.
