# DietFlow

**Meal Widget** — set a meal plan once, and a Home Screen widget tells you what to eat now and
next, moving with the time of day on its own.

The plan can be typed in, or imported from a dietitian's list (pasted text, a file, a photo or a
PDF) or from ChatGPT or Claude using the copyable AI format. After that the widget, the Today
screen and the optional meal reminders all run off the same plan without the app being opened.
Everything stays on the device.

iPhone only, iOS 26 and up. Swift 6, SwiftUI, SwiftData, WidgetKit, App Intents.

## Layout

```
DietFlow/                 app target: entry point, composition root, routing, App Shortcuts
DietFlowWidget/           widget extension: a thin shell over the WidgetUI module
Shared/                   App Intents compiled into both the app and the widget
Packages/DietFlowKit/     everything else, as one Swift package of small modules
Config/                   build settings (xcconfig) and the widget's Info.plist
backend/                  Cloudflare Workers: the assistant proxy and the MCP server
tools/localization/       string catalog tooling: validate, export for translation, import
fastlane/, .github/       TestFlight and CI
docs/                     architecture and localization guides
```

Both Xcode targets use file-system-synchronised folders: a file added to `DietFlow/` or
`DietFlowWidget/` is part of its target, and one added to `Shared/` is part of both, without
touching `project.pbxproj`.

The display name is set once, as `APP_DISPLAY_NAME` in `Config/Shared.xcconfig`.

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
