# DietFlow

**Meal Planner Widget: DietFlow** — set a diet plan once, and a widget tells you what to eat next and when.

The plan can come from anywhere: typed in, imported from a dietitian's list (text, photo or PDF),
written by the built-in assistant, or pushed from Claude through MCP. After that the widget, the
Today screen and the meal-time reminders all run off the same plan without the app being opened.

iPhone only, iOS 18 and up. Swift 6, SwiftUI, WidgetKit.

## Layout

```
DietFlow/                 app target: entry point, composition root, routing between features
DietFlowWidget/           widget extension: a thin shell over the WidgetUI module
Packages/DietFlowKit/     everything else, as one Swift package of small modules
Config/                   build settings (xcconfig) and the widget's Info.plist
backend/                  Cloudflare Workers: the assistant proxy and the MCP server
tools/localization/       string catalog tooling: validate, export for translation, import
fastlane/, .github/       TestFlight and CI
docs/                     architecture and localization guides
```

Both Xcode targets use file-system-synchronised folders: a file added to `DietFlow/` or
`DietFlowWidget/` is part of its target without touching `project.pbxproj`.

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before adding a module and
[docs/LOCALIZATION.md](docs/LOCALIZATION.md) before adding a string.

## Building

There is no local build on Windows; builds run on GitHub's macOS runners.

```bash
gh workflow run ci.yml -R mericorhay/DietFlow          # compile + package tests + localization
gh workflow run testflight.yml -R mericorhay/DietFlow  # signed build to TestFlight
```

The localization checks run anywhere Node does:

```bash
node --test tools/localization/catalogs.test.mjs
node tools/localization/l10n.mjs validate
```

## TestFlight setup, once

In the Apple Developer portal, under team `XYB3NLV654`:

1. Register the App Group `group.com.orhay.dietflow`.
2. Register two App IDs with the App Groups capability, both assigned to that group:
   `com.orhay.dietflow` and `com.orhay.dietflow.widget`.
3. Create an App Store provisioning profile for each, using the existing distribution certificate.
4. Create the app in App Store Connect with bundle id `com.orhay.dietflow`.

Then load the secrets (the list is at the top of `.github/workflows/testflight.yml`):

```bash
bash scripts/set-secrets.sh
```
