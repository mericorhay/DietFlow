# Localization

DietFlow ships English (`en`, the source), Turkish (`tr`) and Spanish (`es`), from Apple String
Catalogs. The setup is built so that a language model can translate the whole app from one file
and cannot break anything while doing it.

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

4. **All three languages, in the same commit.** A key missing a language fails CI.

5. **Values are passed in, never glued on.** Use placeholders (`%@`, `%lld`), and number them
   when there is more than one (`%1$@`, `%2$lld`) so a translation can reorder them.
   `"\(count) meals"` built in Swift cannot be translated; a plural variation in the catalog can.

6. **English source is English.** No Turkish in the `en` value.

7. **What the person wrote is never translated.** Meal names, items and notes are their content,
   in their language.

Recurring words are fixed in [`tools/localization/glossary.json`](../tools/localization/glossary.json),
so a "meal" is not an "öğün" on one screen and a "yemek" on the next. Product names that must
survive untouched are `protectedTerms` in `localization.config.json`.

## Checking

```bash
node tools/localization/l10n.mjs validate
```

It fails on: a missing language, a string not marked translated, a key that does not follow the
naming, a missing comment, a dropped or added placeholder, a changed line break, a translated
protected term, or a language Xcode has not been told about. CI runs the same command.

## Translating with a model

```bash
node tools/localization/l10n.mjs export --locale tr --out tr.json
```

`tr.json` holds every string that still needs Turkish, each with its key, comment and English
source, plus the instructions and the glossary. Give the file to any model, ask for it back with
the `translation` fields filled in, then:

```bash
node tools/localization/l10n.mjs import tr.json
node tools/localization/l10n.mjs validate
```

`import` checks every line and writes nothing unless all of them pass. It also refuses a
translation whose English has changed since the export. Add `--all` to `export` to get every
string, including already translated ones, for a review pass.

## Adding a language

```bash
node tools/localization/l10n.mjs add-locale de German
node tools/localization/l10n.mjs export --locale de --out de.json
# translate de.json
node tools/localization/l10n.mjs import de.json
```

`add-locale` registers the language in the config and in the Xcode project. Add the new
language's words to the glossary before exporting, so the model uses them from the first string.

## Where catalogs live

One per module, next to the code that uses it:

```
DietFlow/Resources/Localizable.xcstrings          tab bar and anything else the app target draws
DietFlow/Resources/InfoPlist.xcstrings            app name and permission prompts
DietFlowWidget/Resources/Localizable.xcstrings    widget gallery name and description
Packages/DietFlowKit/Sources/<Module>/Resources/Localizable.xcstrings
```

The tooling finds every `.xcstrings` file in the repository on its own; a new module's catalog
needs no registration.
