#!/usr/bin/env node
// One tool for everything a translator — human or model — needs.
//
//   node tools/localization/l10n.mjs validate
//   node tools/localization/l10n.mjs status
//   node tools/localization/l10n.mjs export --locale de [--all] [--out de.json]
//   node tools/localization/l10n.mjs export --planned --out-dir translations/
//   node tools/localization/l10n.mjs import de.json [fr.json …]
//   node tools/localization/l10n.mjs add-locale de [fr …]
//
// `export` writes one flat JSON file holding every string that still needs the language, each with
// its key, its comment and the English source, plus everything a model needs to know about the
// language: its plural forms and which counts they cover, its writing direction, the glossary.
// Hand that file to any model, get it back with the `translation` fields filled in, and `import`
// checks every line before a catalog is touched. A language that is not shipping yet is only
// written once it is complete, so the app never shows a half-translated language.
import fs from "node:fs/promises";
import path from "node:path";
import {
  appleJSON,
  atomicWrite,
  catalogFiles,
  configPath,
  expectedPaths,
  glossaryPath,
  languageName,
  leafUnits,
  pluralCategories,
  pluralChoice,
  projectPath,
  readCatalog,
  readConfig,
  readGlossary,
  readLanguages,
  relative,
  repositoryRoot,
  setTranslation,
  sourceLeafFor,
  validatePair,
} from "./catalogs.mjs";

const [command, ...rest] = process.argv.slice(2);
const VALUE_OPTIONS = ["locale", "out", "out-dir"];
const option = (name) => {
  const index = rest.indexOf(`--${name}`);
  return index >= 0 ? rest[index + 1] : undefined;
};
const flag = (name) => rest.includes(`--${name}`);
const positional = rest.filter((value, index) => !value.startsWith("--") && !VALUE_OPTIONS.some(name => rest[index - 1] === `--${name}`));

const KEY_SHAPE = /^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$/;
// Keys Apple defines; they cannot follow our naming.
const SYSTEM_KEY = /^(CF|NS|UI)[A-Z]/;
// In an App Shortcuts catalog the key is the Siri phrase itself, as Apple defines it.
const PHRASE_CATALOG = /(^|\/)AppShortcuts\.xcstrings$/;
const APP_NAME_TOKEN = "${applicationName}";

const samePath = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function fail(message) {
  console.error(message);
  process.exit(1);
}

/** Every string of every catalog, with its source leaves and its leaves in `locale`. */
async function* entries(locale) {
  const config = await readConfig();
  for (const file of await catalogFiles()) {
    const catalog = await readCatalog(file);
    for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
      yield {
        file,
        catalog,
        name: relative(file),
        key,
        entry,
        sourceLeaves: leafUnits(entry.localizations?.[config.sourceLocale]),
        targetLeaves: locale ? leafUnits(entry.localizations?.[locale]) : [],
      };
    }
  }
}

/** How many of the strings a language needs it has, translated. */
async function coverage(locale, languages) {
  let total = 0;
  let done = 0;
  for await (const { sourceLeaves, targetLeaves } of entries(locale)) {
    for (const expected of expectedPaths(sourceLeaves, locale, languages)) {
      total += 1;
      const leaf = targetLeaves.find(candidate => samePath(candidate.path, expected));
      if (leaf?.stringUnit.state === "translated" && leaf.stringUnit.value?.trim()) done += 1;
    }
  }
  return { total, done };
}

// MARK: validate

async function validate() {
  const config = await readConfig();
  const languages = await readLanguages();
  const errors = [];
  const warnings = [];
  const units = Object.fromEntries(config.locales.map(locale => [locale, 0]));
  let strings = 0;

  for (const locale of [...config.locales, ...(config.plannedLocales ?? [])]) {
    if (!languages[locale]) errors.push(`${locale} is not in languages.json; add its name, direction and plural forms`);
  }
  for (const locale of config.plannedLocales ?? []) {
    if (config.locales.includes(locale)) errors.push(`${locale} is both shipping and planned; remove it from plannedLocales`);
  }

  const seenCatalogs = new Set();
  for await (const { catalog, name, key, entry, sourceLeaves } of entries()) {
    if (!seenCatalogs.has(name)) {
      seenCatalogs.add(name);
      if (catalog.sourceLanguage !== config.sourceLocale) errors.push(`${name}: sourceLanguage must be ${config.sourceLocale}`);
    }
    strings += 1;
    const where = `${name} :: ${key}`;
    const isPhraseCatalog = PHRASE_CATALOG.test(name);
    if (!SYSTEM_KEY.test(key)) {
      if (!isPhraseCatalog && !KEY_SHAPE.test(key)) errors.push(`${where}: key must look like screen.element.role`);
      if (!entry.comment?.trim()) errors.push(`${where}: missing comment (the translator's only context)`);
    }
    if (sourceLeaves.length === 0) {
      errors.push(`${where}: missing ${config.sourceLocale} source`);
      continue;
    }

    for (const locale of Object.keys(entry.localizations ?? {})) {
      if (!config.locales.includes(locale)) {
        warnings.push(`${where}: has ${locale} text, but ${locale} is not shipping; import a complete ${locale} file to ship it`);
      }
    }

    for (const locale of config.locales) {
      const targetLeaves = leafUnits(entry.localizations?.[locale]);
      const expected = locale === config.sourceLocale ? sourceLeaves.map(leaf => leaf.path) : expectedPaths(sourceLeaves, locale, languages);
      for (const unitPath of expected) {
        const label = pluralChoice(unitPath) ? `${locale}, ${pluralChoice(unitPath)}` : locale;
        const leaf = targetLeaves.find(candidate => samePath(candidate.path, unitPath));
        if (!leaf) {
          errors.push(`${where} [${label}]: missing`);
          continue;
        }
        units[locale] += 1;
        if (leaf.stringUnit.state !== "translated") errors.push(`${where} [${label}]: state is ${leaf.stringUnit.state ?? "missing"}`);
        if (locale === config.sourceLocale) continue;

        const source = sourceLeafFor(sourceLeaves, unitPath).stringUnit.value;
        const target = leaf.stringUnit.value;
        for (const issue of validatePair(source, target, config.protectedTerms)) errors.push(`${where} [${label}]: ${issue}`);
        if (isPhraseCatalog && source.includes(APP_NAME_TOKEN) && !target.includes(APP_NAME_TOKEN)) {
          errors.push(`${where} [${label}]: Siri phrase lost ${APP_NAME_TOKEN}`);
        }
        const isProtected = config.protectedTerms.some(term => source.includes(term));
        if (source === target && /[A-Za-z]{4}/.test(source) && !isProtected) warnings.push(`${where} [${label}]: unchanged from source`);
      }
      if (locale !== config.sourceLocale) {
        for (const leaf of targetLeaves) {
          if (!expected.some(unitPath => samePath(unitPath, leaf.path))) {
            warnings.push(`${where} [${locale}]: ${pluralChoice(leaf.path) ?? "variation"} is not a form ${languageName(locale, languages, config)} uses`);
          }
        }
      }
    }
  }

  const project = await fs.readFile(projectPath, "utf8");
  const regions = project.match(/knownRegions\s*=\s*\(([\s\S]*?)\);/)?.[1] ?? "";
  for (const locale of config.locales) {
    if (!new RegExp(`(^|\\s)"?${locale}"?,`).test(regions)) errors.push(`Xcode knownRegions is missing ${locale}`);
  }

  console.log(`${strings} strings`);
  for (const locale of config.locales) console.log(`  ${locale}: ${units[locale]} units`);
  if (warnings.length) {
    console.warn(`Worth a look (${warnings.length}):`);
    for (const warning of warnings.slice(0, 30)) console.warn(`  - ${warning}`);
  }
  if (errors.length) {
    console.error(`Errors (${errors.length}):`);
    for (const error of errors.slice(0, 100)) console.error(`  - ${error}`);
    process.exit(1);
  }
  console.log("Localization validation passed.");
}

// MARK: status

async function status() {
  const config = await readConfig();
  const languages = await readLanguages();
  const rows = [];
  for (const [state, list] of [["shipping", config.locales], ["planned", config.plannedLocales ?? []]]) {
    for (const locale of list) {
      const { total, done } = await coverage(locale, languages);
      rows.push({ locale, name: languageName(locale, languages, config), state, done, total });
    }
  }
  const width = Math.max(...rows.map(row => row.name.length));
  for (const row of rows) {
    const percent = row.total ? Math.floor((row.done / row.total) * 100) : 0;
    const direction = languages[row.locale]?.direction === "rtl" ? " rtl" : "";
    console.log(`${row.locale.padEnd(8)}${row.name.padEnd(width + 2)}${row.state.padEnd(10)}${String(row.done).padStart(4)}/${row.total} ${String(percent).padStart(3)}%${direction}`);
  }
  const planned = rows.filter(row => row.state === "planned");
  if (planned.length) {
    console.log(`\n${planned.length} planned. Translate them all with:`);
    console.log("  node tools/localization/l10n.mjs export --planned --out-dir translations");
    console.log("  …fill in every \"translation\"…");
    console.log("  node tools/localization/l10n.mjs import translations/*.json");
  }
}

// MARK: export

async function exportDocument(locale, everything) {
  const config = await readConfig();
  const languages = await readLanguages();
  const glossary = await readGlossary();
  const language = languages[locale];
  const name = languageName(locale, languages, config);
  const categories = pluralCategories(locale, languages);

  const units = [];
  for await (const { name: catalog, key, entry, sourceLeaves, targetLeaves } of entries(locale)) {
    for (const unitPath of expectedPaths(sourceLeaves, locale, languages)) {
      const current = targetLeaves.find(candidate => samePath(candidate.path, unitPath));
      if (current?.stringUnit.value?.trim() && current.stringUnit.state === "translated" && !everything) continue;
      const unit = {
        catalog,
        key,
        path: unitPath,
        comment: entry.comment ?? "",
        source: sourceLeafFor(sourceLeaves, unitPath).stringUnit.value,
        translation: current?.stringUnit.value ?? "",
      };
      const category = pluralChoice(unitPath);
      if (category) unit.plural = { category, counts: language?.pluralExamples?.[category] ?? "" };
      units.push(unit);
    }
  }

  const instructions = [
    `Translate each "source" from English into ${name} and write it into "translation".`,
    "Change nothing else: catalog, key, path, comment, plural and source identify the string.",
    "Read the comment first; it says where the text appears and how much room it has. Widget and button text must stay about as short as the English.",
    "Keep every placeholder (%@, %lld, %1$@ …) exactly; you may reorder numbered ones.",
    "Keep line breaks. Do not add quotes or trailing punctuation the source does not have.",
    `Never translate these terms: ${config.protectedTerms.join(", ")}. Keep \${applicationName} as it is.`,
    "Use the glossary for recurring words so the same thing has one name on every screen. Fill in any empty glossary translation first, and use it everywhere.",
    "Write the way a native speaker's phone talks to them: short, plain, warm, with the formality Apple's own iPhone apps use in this language.",
    "Meal names, foods and plan names in examples stay natural for the language; never translate the person's own text (it never appears here).",
  ];
  if (categories.length > 1 || units.some(unit => unit.plural)) {
    instructions.push(`${name} has these plural forms: ${categories.join(", ")}. A unit with "plural" is one form of a counted phrase; "counts" says which numbers use it. Write the phrase as it reads for those numbers, keeping the placeholder.`);
  }
  if (language?.direction === "rtl") {
    instructions.push(`${name} is written right to left. Write naturally; the app mirrors its layout itself. Do not add direction marks.`);
  }

  return {
    locale,
    language: name,
    nativeName: language?.native ?? name,
    direction: language?.direction ?? "ltr",
    pluralForms: Object.fromEntries(categories.map(category => [category, language?.pluralExamples?.[category] ?? ""])),
    instructions,
    glossary: Object.fromEntries(Object.entries(glossary.terms).map(([term, entry]) => [term, { note: entry.note, english: term, translation: entry[locale] ?? "" }])),
    units,
  };
}

async function exportUnits() {
  const config = await readConfig();
  const languages = await readLanguages();
  const everything = flag("all");

  if (flag("planned")) {
    const directory = option("out-dir") ?? fail("export --planned needs --out-dir <folder>");
    await fs.mkdir(directory, { recursive: true });
    let files = 0;
    for (const locale of config.plannedLocales ?? []) {
      if (!languages[locale]) fail(`${locale} is not in languages.json`);
      const document = await exportDocument(locale, everything);
      if (document.units.length === 0) continue;
      await fs.writeFile(path.join(directory, `${locale}.json`), `${JSON.stringify(document, null, 2)}\n`, "utf8");
      files += 1;
      console.error(`${locale}: ${document.units.length} units`);
    }
    console.error(`${files} files written to ${directory}`);
    return;
  }

  const locale = option("locale") ?? fail("export needs --locale <code> or --planned --out-dir <folder>");
  if (locale === config.sourceLocale) fail(`${locale} is the source language`);
  if (!languages[locale]) console.error(`Note: ${locale} is not in languages.json, so English's plural forms are assumed. Add it there first.`);
  const document = await exportDocument(locale, everything);
  const text = `${JSON.stringify(document, null, 2)}\n`;
  const out = option("out");
  if (out) {
    await fs.writeFile(out, text, "utf8");
    console.error(`${document.units.length} units written to ${out}`);
  } else {
    process.stdout.write(text);
  }
}

// MARK: import

async function importFile(file, config, languages, catalogs, glossary) {
  const document = JSON.parse(await fs.readFile(file, "utf8"));
  const locale = document.locale ?? fail(`${file}: no locale`);
  if (locale === config.sourceLocale) fail(`${file}: ${locale} is the source language`);
  if (!languages[locale]) fail(`${file}: ${locale} is not in languages.json; add its name and plural forms first`);

  const errors = [];
  const writes = [];
  for (const unit of document.units ?? []) {
    const where = `${unit.catalog} :: ${unit.key}${pluralChoice(unit.path ?? []) ? ` [${pluralChoice(unit.path)}]` : ""}`;
    const absolute = path.join(repositoryRoot, unit.catalog);
    if (!catalogs.has(absolute)) {
      try { catalogs.set(absolute, await readCatalog(absolute)); }
      catch { errors.push(`${where}: no such catalog`); continue; }
    }
    const catalog = catalogs.get(absolute);
    const entry = catalog.strings?.[unit.key];
    if (!entry) { errors.push(`${where}: no such key`); continue; }

    const sourceLeaves = leafUnits(entry.localizations?.[config.sourceLocale]);
    const unitPath = unit.path ?? [];
    if (!expectedPaths(sourceLeaves, locale, languages).some(candidate => samePath(candidate, unitPath))) {
      errors.push(`${where}: not a string or plural form ${languageName(locale, languages, config)} needs`);
      continue;
    }
    // The English may have changed since the export. A translation of the old sentence must not
    // be filed under the new one.
    const sourceLeaf = sourceLeafFor(sourceLeaves, unitPath);
    if (!sourceLeaf || sourceLeaf.stringUnit.value !== unit.source) { errors.push(`${where}: source changed since export`); continue; }

    const issues = validatePair(unit.source, unit.translation, config.protectedTerms);
    if (PHRASE_CATALOG.test(unit.catalog) && unit.source.includes(APP_NAME_TOKEN) && !String(unit.translation).includes(APP_NAME_TOKEN)) {
      issues.push(`Siri phrase lost ${APP_NAME_TOKEN}`);
    }
    if (issues.length) { errors.push(`${where}: ${issues.join(", ")}`); continue; }
    writes.push({ catalog, key: unit.key, path: unitPath, value: unit.translation });
  }

  // All or nothing: a half-imported language is harder to notice than a rejected file.
  if (errors.length) {
    console.error(`${file}: nothing was written. Fix these ${errors.length} and import again:`);
    for (const error of errors.slice(0, 100)) console.error(`  - ${error}`);
    process.exit(1);
  }
  for (const write of writes) setTranslation(write.catalog, write.key, write.path, locale, write.value);

  for (const [term, entry] of Object.entries(document.glossary ?? {})) {
    const translation = entry?.translation?.trim();
    if (translation && glossary.terms[term]) glossary.terms[term][locale] = translation;
  }
  return { locale, written: writes.length };
}

/** What a language still lacks after the pending writes, across every catalog. */
function missingUnits(locale, catalogs, config, languages) {
  const missing = [];
  for (const [absolute, catalog] of catalogs) {
    for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
      const sourceLeaves = leafUnits(entry.localizations?.[config.sourceLocale]);
      const targetLeaves = leafUnits(entry.localizations?.[locale]);
      for (const unitPath of expectedPaths(sourceLeaves, locale, languages)) {
        const leaf = targetLeaves.find(candidate => samePath(candidate.path, unitPath));
        if (!leaf?.stringUnit.value?.trim()) missing.push(`${relative(absolute)} :: ${key}`);
      }
    }
  }
  return missing;
}

async function importUnits() {
  if (positional.length === 0) fail("import needs one or more files produced by export");
  const config = await readConfig();
  const languages = await readLanguages();
  const glossary = await readGlossary();

  // Every catalog is loaded, so a language's completeness is judged on all of them.
  const catalogs = new Map();
  for (const file of await catalogFiles()) catalogs.set(file, await readCatalog(file));

  const results = [];
  for (const file of positional) results.push(await importFile(file, config, languages, catalogs, glossary));

  const newLocales = [...new Set(results.map(result => result.locale))].filter(locale => !config.locales.includes(locale));
  for (const locale of newLocales) {
    const missing = missingUnits(locale, catalogs, config, languages);
    if (missing.length) {
      console.error(`${languageName(locale, languages, config)} (${locale}) is not shipping yet and would still miss ${missing.length} strings, so nothing was written. Export it again and translate every unit:`);
      for (const item of missing.slice(0, 20)) console.error(`  - ${item}`);
      process.exit(1);
    }
  }

  for (const [absolute, catalog] of catalogs) {
    const before = await fs.readFile(absolute, "utf8");
    const after = appleJSON(catalog);
    if (before !== after) await atomicWrite(absolute, after);
  }
  await atomicWrite(glossaryPath, `${JSON.stringify(glossary, null, 2)}\n`);
  if (newLocales.length) await registerLocales(newLocales, config, languages);

  for (const result of results) console.log(`${result.written} ${result.locale} translations written.`);
  if (newLocales.length) console.log(`Now shipping: ${newLocales.join(", ")}.`);
  console.log("Now run: node tools/localization/l10n.mjs validate");
}

// MARK: add-locale

/** Makes languages shipping: the config's locales, out of planned, and Xcode's knownRegions. */
async function registerLocales(locales, config, languages) {
  for (const locale of locales) {
    if (!config.locales.includes(locale)) config.locales.push(locale);
    config.plannedLocales = (config.plannedLocales ?? []).filter(candidate => candidate !== locale);
    config.localeNames[locale] = languageName(locale, languages, config);
  }
  await atomicWrite(configPath, `${JSON.stringify(config, null, 2)}\n`);

  let project = await fs.readFile(projectPath, "utf8");
  for (const locale of locales) {
    const regions = project.match(/knownRegions\s*=\s*\(([\s\S]*?)\);/)?.[1] ?? "";
    if (new RegExp(`(^|\\s)"?${locale}"?,`).test(regions)) continue;
    const updated = project.replace(/(knownRegions\s*=\s*\(\r?\n)([\s\S]*?)(\t+)Base,/, (_, open, existing, indent) => {
      const entry = /^[A-Za-z0-9_]+$/.test(locale) ? locale : `"${locale}"`;
      return `${open}${existing}${indent}${entry},\n${indent}Base,`;
    });
    if (updated === project) fail("could not find knownRegions in the Xcode project");
    project = updated;
  }
  await atomicWrite(projectPath, project);
}

async function addLocale() {
  const config = await readConfig();
  const languages = await readLanguages();
  // Kept for the old form: add-locale de German.
  const codes = positional.filter(value => languages[value] || /^[a-z]{2,3}(-[A-Za-z0-9]+)?$/.test(value));
  if (codes.length === 0) fail("add-locale needs language codes from languages.json, e.g. add-locale de fr");
  for (const code of codes) {
    if (!languages[code]) fail(`${code} is not in languages.json; add its name, direction and plural forms first`);
    if (config.locales.includes(code)) fail(`${code} is already shipping`);
  }
  await registerLocales(codes, config, languages);
  console.log(`Registered ${codes.join(", ")}. Validation fails until each is fully translated:`);
  for (const code of codes) console.log(`  node tools/localization/l10n.mjs export --locale ${code} --out ${code}.json`);
  console.log("Prefer export → translate → import: import ships a language by itself once it is complete.");
}

const commands = { validate, status, export: exportUnits, import: importUnits, "add-locale": addLocale };
if (!commands[command]) {
  fail("usage: l10n.mjs validate | status | export --locale <code> [--all] [--out file] | export --planned --out-dir <folder> | import <file>… | add-locale <code>…");
}
await commands[command]();
