# Architecture

## The one idea

A **plan** is a cycle of days that repeats from a start date. Everything the person sees — the
widget, the Today screen, the reminders — is that plan asked one question: *what comes next?*
`Domain.MealSchedule` answers it, and nothing else is allowed to.

A plan becomes the active plan in exactly one place, `AppDependencies.activate(_:)`, which saves
it, reloads the widget and reschedules the reminders. It does not matter whether the plan was
typed, imported, proposed by the assistant or pulled from the MCP server.

## Layers

Dependencies point one way: down this list.

| Layer | Modules | May import |
|---|---|---|
| App | `DietFlow/`, `DietFlowWidget/` | anything |
| Features | `OnboardingFeature`, `TodayFeature`, `PlanFeature`, `ImportFeature`, `AssistantFeature`, `SettingsFeature`, `PaywallFeature` | `Domain`, `DesignSystem`, the engines they need |
| Shared UI | `DesignSystem`, `WidgetUI` | `Domain` |
| Engines | `Persistence`, `AIServices`, `PlanImport`, `PlanSync`, `MealReminders`, `Purchases`, `Analytics` | `Domain` (and what `Package.swift` lists) |
| Domain | `Domain` | Foundation only |

Rules that keep it that way:

- **Features never import each other.** The app target routes between them.
- **Engines have no SwiftUI.** They are nonisolated and testable without a simulator screen.
- **`Domain` has no dependencies at all**, so its tests are plain logic tests.
- **UI modules default to the main actor**; engines and `WidgetUI` do not (see `Package.swift`).

## Adding a module

1. Create `Packages/DietFlowKit/Sources/<Name>/` with at least one Swift file.
2. Add it to `appModules` in `Package.swift`, and declare it with `engine(...)` or `feature(...)`.
3. A feature also needs `Resources/Localizable.xcstrings` (see [LOCALIZATION.md](LOCALIZATION.md)).

Nothing in `project.pbxproj` changes.

## The widget

The extension (`DietFlowWidget/`) only connects WidgetKit to the `WidgetUI` module. It links the
`DietFlowWidgetKit` product — `Domain`, `Persistence`, `WidgetUI` — and nothing else, because an
extension has a small memory budget and may only use extension-safe API.

App and widget are separate processes. The only thing they share is one file, `plan.json`, in the
App Group container `group.com.orhay.dietflow` (`Persistence.PlanStore`). The widget builds a full
timeline from it up front, so it moves from meal to meal on its own.

## The assistant

The in-app assistant talks to our Worker (`backend/assistant`), never to a model provider
directly. The provider key and the system prompt live server-side: a key compiled into an app can
be extracted, and a server-side prompt changes without an app release. The app only knows the
Worker's URL and an app token, which CI writes into the bundle from repository secrets.

The assistant can *propose* a plan (`AssistantReply.proposedPlan`). The person accepts it; the
assistant never replaces a plan on its own.

## MCP

A phone cannot be an MCP server: nothing outside can reach it. So the MCP server is ours
(`backend/mcp`), and the phone is one of its clients:

```
Claude ──MCP tools──▶ backend/mcp ◀──pair once, then pull── DietFlow on the phone
        (get_plan, set_plan, …)        (PlanSync)
```

The person adds the server to Claude as a connector, pairs their phone with a short code, and
from then on a plan Claude writes shows up on the widget. `PlanSync.PlanSyncClient` is the phone's
side of that; a pulled plan goes through the same `activate(_:)` as any other.

## Versions

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `Config/Shared.xcconfig`, shared by the
app and the widget, because App Store Connect rejects an extension whose numbers differ from its
app's. The iOS floor is set in two places that must agree: that file and `Package.swift`.
