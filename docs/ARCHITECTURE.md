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
| Features | `TodayFeature`, `PlanFeature`, `MealFeature`, `ImportFeature`, `WidgetsFeature`, `SettingsFeature`, `OnboardingFeature`, `PaywallFeature` (and the unused `AssistantFeature`) | `Domain`, `DesignSystem`, `AppCore`, the engines they need |
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
(an hour unless the person chose otherwise, or the next meal, whichever is sooner), a countdown in five-minute steps during the
hour before a meal ("in 15 min"), and midnight. Moments that would look the same are merged.
WidgetKit plays them back on its own, the way the Calendar widget moves from event to event; the
timeline asks to be rebuilt every twelve hours, and the app reloads it after every change.

A corrupt or newer snapshot shows "open the app to update"; a missing one shows "no plan".

The families are small, medium, large, Lock Screen rectangular and inline.

**Nothing has to be tapped.** A meal whose time has come stays in front for its window, then gives
way to the next one, and after the day's last meal the widget shows tomorrow's first. Marking a
meal done is optional everywhere, and a meal left unmarked is simply earlier in the day, not a
task undone. The window (30 minutes to 2 hours, an hour by default) is chosen on the Widgets tab
and travels in the snapshot, so Today and the widget use the same one. A Done button for the medium
and large widgets can be turned on there for moving on sooner: `MarkMealDoneIntent`, which runs in
the widget's process.

**Colour and tone** are chosen on the Widgets tab too: one of ten colours (`WidgetAccent`) and a
background (`WidgetBackgroundStyle`: automatic, a soft wash of the colour, the colour itself with
white text, or dark). `WidgetUI.WidgetTheme` turns the pair into the few colours the widget views
ask for and hands it down through the environment; `WidgetThemeBackground` is the background both
the extension and the app's previews draw, so the preview is what appears. Lock Screen widgets, and
Home Screen widgets under tinted icons, are coloured by iOS and take none of it.

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
read with Vision on the device. None of that sends anything anywhere; only the assistant, below,
does.

"Copy AI Instructions" puts the format on the clipboard so ChatGPT or Claude can write a payload.
An MCP server would produce the same payload and call the same `MealPlanStore` operations.

## What comes in from outside

A plan can be typed, pasted, opened from a file, read off a photo, handed over by a Shortcut, and
later written by an MCP client. None of those is trusted to be small or well formed:

- **Size is checked before anything is read.** `Domain.PlanLimits` holds every bound: a file is
  measured before it is loaded, pasted or recognised text past the limit is refused, and a plan
  with more meals than a year can hold is refused whole rather than cut short.
- **`MealPlanStore` bounds what it stores.** `createPlan`, `replacePlan`, `addMeal` and
  `updateMeal` pass everything through `MealPlan.sanitized()` / `Meal.sanitized()`: names become
  one trimmed line, text is cut to its limit, numbers out of range are dropped, and a meal without
  a name is rejected. The rule lives there, not in each screen, so a new way in cannot skip it.
- **A link never costs the person their work.** `dietflow://` links can come from any app or web
  page; while a form is open they are ignored. A reminder or link naming a meal that no longer
  exists does nothing.
- **Only the app's own Inbox is cleaned up.** A file opened with the app is deleted after reading
  only if it is the copy iOS placed in `Documents/Inbox`.

## DietFlow Plus

What is paid for is one table, `Domain.AccessPolicy`, and nowhere else:

| | Free | Plus |
|---|---|---|
| Plans kept | 1 | any number |
| Assistant requests | 2 a calendar month | 60 a billing month |
| Everything else — every widget, reminders, importing on the device | yes | yes |

- **`Purchases.PlusStore`** is StoreKit: three products (monthly with a free trial, yearly, a
  one-time lifetime purchase), the purchase, restore, offer codes, and what is held now. It reads
  the current entitlements at every launch and follows `Transaction.updates`, so a renewal, a
  refund or a purchase on another device arrives without the person doing anything. Nothing in it
  is worded for the screen.
- **`AppCore.AccessModel`** is the tier in force and what has been used of its allowances. It is
  asked before anything paid runs (`check`, `use`), gives a use back when an attempt fails
  (`refund`), and remembers the store's last answer so a subscriber is on Plus from the first frame.
  Counts live in the Keychain, so reinstalling does not reset them.
- **`Domain.BillingCycle`** works out the dates: when a trial started now would end, and the
  window an allowance is counted over. A monthly subscription uses the period the App Store
  charged for, trial included. A year or a lifetime is counted month by month from the day it was
  bought. Windows are measured from that day itself, never from the window before, so a billing day
  on the 31st goes 28 February, 31 March rather than slipping to the 28th for good. All of it is
  counted in UTC, and all of it is tested.
- **`PaywallFeature.PaywallScreen`** is shown once on first launch as the app's introduction, from
  Settings, and when something is refused. It can always be closed. Every price on it comes from
  the App Store; every date is worked out from what the App Store said.

A refusal is recorded on `AccessModel.request`; `RootView` turns it into what the person sees
(`AppDependencies.answer`), and `PlusPresenter`, attached to the tabs and to every sheet, shows it
from whatever is in front. On Plus the only refusal is a used-up allowance, and an alert says when
it comes back instead of selling anything.

## The assistant

The assistant does two things, both from Import: it puts a pasted list in order however untidy it
is, and it writes a new plan of up to 30 days from a few wishes.

`AIServices.PlanAssistantClient` posts to our Worker (`backend/assistant`), never to a model
provider: the key and the prompts stay server-side, so a prompt changes without an app release.
The Worker reads a long list in parts and writes a long plan a week at a time; to the app either
is one request. What comes back is a `MealPlanPayload`, and it goes through `PlanImportNormalizer`
and the review screen like a file or a pasted list — nothing a model writes is saved unseen.

A build made without the Worker's address has no assistant: its rows, its line on the Plus screen
and its paragraph on the Privacy screen are all left out, rather than offer something that cannot
work. With it, the Privacy screen says exactly what is sent.

## Anonymous usage data

`Analytics` is the one place the app talks to PostHog. Sharing is on unless the person turns it
off in Settings; off, nothing is sent or queued. A build without the key (`Analytics.json`, written
by CI from a repository secret) sends nothing and leaves the switch out.

An event is a name and a few plain values, and the type system keeps it that way: a property is an
`AnalyticsValue` — a fixed word, a number or a flag — so nothing the person wrote can ride along by
accident. An error is sent as one of a fixed set of reasons, never as its own description, which
can quote the text it failed on.

| Event | Carries |
|---|---|
| `app_launched` | how many plans, how many meals in the active one, whether reminders are on |
| `paywall_shown` | why: intro, settings, assistant limit, a second plan |
| `plus_purchase`, `plus_restore` | the product, whether it had a trial, the outcome |
| `plan_imported`, `plan_import_failed` | the way in (paste, file, photo, PDF, assistant), sizes, the reason |
| `plan_saved` | the way in |
| `allowance_used_up` | the limit |

Every event also carries the tier, the app's language and the build. PostHog adds app opened,
backgrounded, installed and updated. There is no screen or tap capture and no session replay, and
seeded screenshot states send nothing. The app's privacy manifest declares all of it.

`PlanSync` and `backend/mcp` are still only a contract: an MCP server would produce the same
payload and call the same `MealPlanStore` operations.

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
