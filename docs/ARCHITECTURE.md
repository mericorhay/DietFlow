# Architecture

## The one idea

A **plan** is a run of days — Day 1, Day 2, … from a start date, repeating or not, or a set of fixed
dates — each with its meals. Everything the person sees — the widget, the Today screen, the
reminders, Siri — is that plan asked one question: *what comes next?* `Domain.MealSchedule`
answers it, and nothing else is allowed to.

Days are wall-calendar days (`CalendarDay`, "2026-10-05") and meal times are wall-clock times
(`TimeOfDay`, "14:00"). Only the current time zone turns them into instants, so a plan follows
the person across time zones and through daylight-saving jumps without shifting a day.

What happened to a meal on a given day (`OccurrenceState`: done, skipped) is stored apart from the
plan's template, keyed by meal and day (`OccurrenceKey`). Marking Tuesday's lunch done never edits
the plan, so a repeating plan stays as it was written.

## Where a change goes

Every change — from a screen, a Shortcut, the widget's Done button, an import, later an MCP bridge —
goes through one type, `AppCore.MealPlanStore`, and its operations named for the plan:
`createPlan`, `replacePlan`, `addMeal`, `updateMeal`, `deleteMeal`, `markMealCompleted`,
`getActivePlan`, `getPlanForDate`. After storing a change it, in this order:

1. writes the widget snapshot to the App Group (`Persistence.WidgetSnapshotWriter`),
2. asks WidgetKit to reload,
3. reschedules the meal reminders (`MealReminders`, planned by `Domain.ReminderPlanner`).

So nothing that shows the plan can fall behind it.

## Layers

Dependencies point one way: down this list.

| Layer | Modules | May import |
|---|---|---|
| App | `DietFlow/`, `DietFlowWidget/`, `Shared/` | anything |
| Features | `TodayFeature`, `PlanFeature`, `MealFeature`, `ImportFeature`, `WidgetsFeature`, `SettingsFeature`, `OnboardingFeature` (and the unused `AssistantFeature`, `PaywallFeature`) | `Domain`, `DesignSystem`, `AppCore`, the engines they need |
| Shared UI | `DesignSystem`, `WidgetUI` | `Domain` |
| App core | `AppCore` | `Domain`, `Persistence`, `MealReminders` |
| Engines | `Persistence`, `MealReminders`, `PlanImport`, `PlanSync`, `AIServices`, `Purchases`, `Analytics` | `Domain` (and what `Package.swift` lists) |
| Domain | `Domain` | Foundation only |

Rules that keep it that way:

- **Features never import each other.** The app target routes between them (`RootView`), passing
  each screen closures for "open settings", "add a meal", and so on.
- **Engines have no SwiftUI.** They are nonisolated and testable without a simulator screen.
- **`Domain` has no dependencies**, so its tests are plain logic tests: the schedule, daylight
  saving and time zones, the widget timeline, the import format and the pasted-plan reader.
- **UI modules default to the main actor**; engines, `DesignSystem` and `WidgetUI` do not (see
  `Package.swift`), so the widget can use them off the main actor.
- Values the screens read (`AppSettings`, `PlanSummary`) live in `Domain`, so a feature never needs
  to import `Persistence`.

## Storage

- **SwiftData** (`Persistence.PlanStore`) is the canonical store: plans, meals, and recorded
  states. It lives in the App Group container `group.com.orhay.dietflow`, because the widget's
  Done button runs in the widget's process and writes to the same store. Each operation works in a
  fresh `ModelContext`, so a change written by the other process is never hidden behind a cache.
- **The widget snapshot** (`widget-snapshot.json`, `Domain.WidgetSnapshot`) is what the widget
  reads. It holds the active plan trimmed to what is drawn, the recorded states for a couple of
  weeks around today, and the widget preferences. Because it holds the plan rather than a list of
  upcoming meals, the widget keeps going for as long as the plan runs, even if the app is not
  opened for weeks.
- **Settings** (`Domain.AppSettings`) are JSON in the App Group's defaults.

## The widget

The extension (`DietFlowWidget/`) connects WidgetKit to `WidgetUI`. Its provider reads the
snapshot and hands WidgetKit every moment the widget's face changes, worked out up front by
`Domain.WidgetTimelineBuilder`: each meal's time (it becomes "Now"), the end of its "now" window
(90 minutes, or the next meal, whichever is sooner), a countdown in five-minute steps during the
hour before a meal ("in 15 min"), and midnight. Moments that would look the same are merged.
WidgetKit plays them back on its own, the way the Calendar widget moves from event to event; the
timeline asks to be rebuilt every twelve hours, and the app reloads it after every change.

A corrupt or newer snapshot shows "open the app to update"; a missing one shows "no plan".

The families are small, medium, large, Lock Screen rectangular and inline. The medium and large
widgets have a Done button: `MarkMealDoneIntent`, which runs in the widget's process.

## Links, files and reminders

Everything that opens the app from outside lands in `RootView`, which owns the tabs and their
navigation paths:

- **Links.** `Domain.AppLink` names a place: `dietflow://today`, `dietflow://meal/<occurrence>`,
  `dietflow://plan`, `dietflow://widgets`, `dietflow://import`. The widget opens the meal it shows;
  the scheme is registered in `Config/DietFlow-Info.plist`.
- **Files.** Plans are shared as `.mealplan` files (`UTType.mealPlan`, JSON in the import format,
  declared in the same plist). Opening one — or any JSON file — with the app goes straight to
  Import's review.
- **Reminders.** Each carries Done and Skip buttons (`MealReminderAction`), answered by
  `ReminderResponder` without opening the app; tapping the reminder opens that meal.

## Language

iOS picks the language from the person's preferred languages, or from the one chosen for this app
in the Settings app. Settings › Language & Region shows it (`Domain.AppLanguage`) and leads there;
nothing in the code lists languages. How strings are written, checked and translated — and how the
thirty planned languages get added — is in [LOCALIZATION.md](LOCALIZATION.md).

## App Intents

`Shared/Intents` is a folder synchronised into both the app and the widget target, so the widget
can run `MarkMealDoneIntent` and Shortcuts can run all of them: mark a meal done, say the next meal,
add a meal. `DietFlow/Intents` holds what only the app runs: the Import Plan intent (which hands
the text to the app for review) and the App Shortcuts. Every intent goes through `MealPlanStore`.

## Importing

Every source — a `.json`/`.mealplan` file, pasted text, a photo or a PDF — becomes a
`Domain.MealPlanPayload`, the interchange format, and then a draft (`PlanImportNormalizer`) with
a list of anything that was filled in or left out. The draft is always shown for review before it
is saved. Pasted text is read by `PastedPlanParser` (any JSON in it first, then lines in English,
Turkish or Spanish), and by Apple's on-device model where the device has it. Photos and PDFs are
read with Vision on the device. Nothing is sent anywhere.

"Copy AI Instructions" puts the format on the clipboard so ChatGPT or Claude can write a payload.
An MCP server would produce the same payload and call the same `MealPlanStore` operations.

## The assistant and the backend

`AIServices`, `AssistantFeature`, `PlanSync` and `backend/` are kept from the first skeleton but no
screen uses them: the app works entirely on the device and sends no plan anywhere. Whether to bring
an assistant or a server back is a product decision for later.

## Checking the screens

Debug builds open a known state from launch arguments (`DietFlow/DebugLaunch.swift`): the sample
plan or a first run in memory, a tab, a sheet, a meal, an onboarding page. Nothing is read from or
written to the person's data. CI uses them when run with `screenshots: true`
(`scripts/ci-screenshots.sh`): the main screens in English, Turkish and Spanish, in dark mode, at a
large text size, and in Xcode's long and right-to-left pseudolanguages, printed into the job log
as small images.

## Versions

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `Config/Shared.xcconfig`, shared by the
app and the widget, because App Store Connect rejects an extension whose numbers differ from its
app's. The iOS floor (26) is set in two places that must agree: that file and `Package.swift`.

The name under the icon is `APP_DISPLAY_NAME` in `Config/Shared.xcconfig` (and its translations in
`DietFlow/Resources/InfoPlist.xcstrings`). Code reads it from the bundle (`Domain.AppBrand`); no
string in the code names the app.
