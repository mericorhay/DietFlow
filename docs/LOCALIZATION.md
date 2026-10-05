# Localization

English (`en`) is the source language. Turkish (`tr`) and Spanish (`es`) ship today, and thirty
more are queued in [`tools/localization/localization.config.json`](../tools/localization/localization.config.json)
(`plannedLocales`), ready for a language model to translate. Everything is built so that a model
can translate the whole app from one file per language and cannot break anything while doing it.

| | Languages |
|---|---|
| Shipping | English, Turkish, Spanish |
| Planned | German, French, Italian, Portuguese (Brazil), Dutch, Swedish, Danish, Norwegian, Finnish, Polish, Czech, Slovak, Hungarian, Romanian, Greek, Russian, Ukrainian, Croatian, Catalan, Arabic, Hebrew, Hindi, Thai, Vietnamese, Indonesian, Malay, Japanese, Korean, Chinese (Simplified), Chinese (Traditional) |

[`tools/localization/languages.json`](../tools/localization/languages.json) describes each language
for the translator: its name, whether it is written right to left, and its plural forms with the
counts each one covers (Arabic has six forms of "%lld meals", Russian four, Japanese one).

## Rules for every string

1. **No text in Swift.** Code holds a key; the words live in the module's
   `Resources/Localizable.xcstrings`.

   ```swift
   Text("today.nextMeal.title", bundle: .module)          // in a package module
   Text("tab.today")                                      // in the app or widget target
   String(localized: "import.error.noMeals", bundle: .module)
   ```

2. **Keys say where and what, not the words:** `screen.element.role`, lowerCamelCase segments,
   at least two. `today.nextMeal.title`, `import.photo.button`, `settings.reminders.footer`.
   A key never changes when the wording does.

3. **Every key has a comment.** It is the translator's only context. Say where the text appears,
   what it does, and how much room it has: *"Button under the photo preview. Starts the import.
   Two words at most."* The validator rejects a key without one.

4. **Every shipping language, in the same commit.** A key missing a language fails CI.

5. **Values are passed in, never glued on.** Use placeholders (`%@`, `%lld`), and number them
   when there is more than one (`%1$@`, `%2$lld`) so a translation can reorder them.
   `"\(count) meals"` built in Swift cannot be translated; a plural variation in the catalog can.

6. **English source is English.** No Turkish in the `en` value.

7. **What the person wrote is never translated.** Meal names, items and notes are their content,
   in their language.

8. **Leave room.** German runs a third longer than English and Finnish longer still; Arabic and
   Hebrew run right to left. So: no fixed widths on text, let labels wrap, use `leading` and
   `trailing` (never left and right), and prefer symbols that mirror (`chevron.forward`, not
   `chevron.right`). Dates, times and numbers always go through a formatter, so they follow the
   person's region rather than the language.

Recurring words are fixed in [`tools/localization/glossary.json`](../tools/localization/glossary.json),
so a "meal" is not an "öğün" on one screen and a "yemek" on the next. Product names that must
survive untouched are `protectedTerms` in `localization.config.json`.

Siri phrases live in `DietFlow/Resources/AppShortcuts.xcstrings`, where Apple makes the phrase
itself the key. The validator does not ask those keys to follow the naming, but checks that every
translation keeps `${applicationName}`. Siri understands fewer languages than the app ships;
phrases in a language Siri lacks are simply not offered.

## Checking

```bash
node tools/localization/l10n.mjs validate
node tools/localization/l10n.mjs status
```

`validate` fails on: a missing language or plural form, a string not marked translated, a key that
does not follow the naming, a missing comment, a dropped or added placeholder, a changed line
break, a translated protected term, or a language Xcode has not been told about. CI runs it, with
the tooling's own tests (`node --test tools/localization/catalogs.test.mjs`).

`status` lists every shipping and planned language with how much of it is translated.

## Translating the planned languages with a model

```bash
node tools/localization/l10n.mjs export --planned --out-dir translations
```

This writes `translations/<code>.json` for each planned language. Each file holds the language's
plural forms, its writing direction, the instructions, the glossary, and one unit per string:
key, comment, English source and an empty `translation`. A plural unit also says which form it is
and which counts use it.

Give each file to a model and ask for it back with every `translation` filled in, the glossary's
first. Then:

```bash
node tools/localization/l10n.mjs import translations/*.json
node tools/localization/l10n.mjs validate
```

`import` checks every unit and writes nothing from a file unless all of it passes. It refuses a
translation whose English has changed since the export. A planned language is only written once
it is complete; it then becomes a shipping language by itself — the config, the glossary and the
Xcode project's known regions are all updated — so the app never shows a half-translated language.
Commit the catalogs, `localization.config.json`, `glossary.json` and `project.pbxproj` together.

One language at a time works the same way:

```bash
node tools/localization/l10n.mjs export --locale de --out de.json
node tools/localization/l10n.mjs import de.json
```

Add `--all` to `export` to get every string, including already translated ones, for a review pass
of a shipping language.

## Adding a language that is not in the plan

1. Add it to `languages.json`: its Xcode code (`pt-PT`, `zh-HK`), English and native name,
   `"direction": "rtl"` if it is written right to left, and its CLDR plural categories with
   the counts each covers.
2. Add the code to `plannedLocales`.
3. Translate it as above.

## How the app picks a language

iOS chooses: the person's preferred languages, or the language set for this app alone in
**Settings › Meal Widget › Language**. The app's own Settings screen shows the current language and
opens that page; nothing in the code lists languages, so a newly shipped language appears there
without a code change. The widget and the Siri phrases follow the app. A right-to-left language
mirrors the whole layout, which SwiftUI does on its own as long as rule 8 is kept.

To check that a screen has room, run the app with Xcode's *Double-Length Pseudolanguage* or
*Right-to-Left Pseudolanguage* (Scheme › Run › Options › App Language).

## Where catalogs live

One per module, next to the code that uses it:

```
DietFlow/Resources/Localizable.xcstrings          tab bar and anything else the app target draws
DietFlow/Resources/InfoPlist.xcstrings            app name and permission prompts
DietFlow/Resources/AppShortcuts.xcstrings         Siri phrases for the App Shortcuts
DietFlowWidget/Resources/Localizable.xcstrings    widget gallery name and description
Packages/DietFlowKit/Sources/<Module>/Resources/Localizable.xcstrings
```

The tooling finds every `.xcstrings` file in the repository on its own; a new module's catalog
needs no registration.
