#!/usr/bin/env node
// One tool for everything a translator — human or model — needs.
//
//   node tools/localization/l10n.mjs validate
//   node tools/localization/l10n.mjs export --locale de [--all] [--out de.json]
//   node tools/localization/l10n.mjs import de.json
//   node tools/localization/l10n.mjs add-locale de German
//
// `export` writes one flat JSON file holding every string that still needs the locale, each with
// its key, its comment and the English source. Hand that file to any model, get it back with the
// `translation` fields filled in, and `import` checks every line before a catalog is touched.
import fs from "node:fs/promises";
import path from "node:path";
import {
  appleJSON,
  atomicWrite,
  catalogFiles,
  configPath,
  leafUnits,
  projectPath,
  readCatalog,
  readConfig,
  readGlossary,
  relative,
  repositoryRoot,
  setTranslation,
  validatePair,
} from "./catalogs.mjs";

const [command, ...rest] = process.argv.slice(2);
const option = (name) => {
  const index = rest.indexOf(`--${name}`);
  return index >= 0 ? rest[index + 1] : undefined;
};
const flag = (name) => rest.includes(`--${name}`);
const positional = rest.filter((value, index) => !value.startsWith("--") && !(rest[index - 1] ?? "").match(/^--(locale|out)$/));

const KEY_SHAPE = /^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$/;
// Keys Apple defines; they cannot follow our naming.
const SYSTEM_KEY = /^(CF|NS|UI)[A-Z]/;
// In an App Shortcuts catalog the key is the Siri phrase itself, as Apple defines it.
const PHRASE_CATALOG = /(^|\/)AppShortcuts\.xcstrings$/;
const APP_NAME_TOKEN = "${applicationName}";

function fail(message) {
  console.error(message);
  process.exit(1);
}

async function validate() {
  const config = await readConfig();
  const errors = [];
  const warnings = [];
  const coverage = Object.fromEntries(config.locales.map(locale => [locale, 0]));
  let strings = 0;

  for (const file of await catalogFiles()) {
    const catalog = await readCatalog(file);
    const name = relative(file);
    if (catalog.sourceLanguage !== config.sourceLocale) errors.push(`${name}: sourceLanguage must be ${config.sourceLocale}`);

    const isPhraseCatalog = PHRASE_CATALOG.test(name);
    for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
      strings += 1;
      const where = `${name} :: ${key}`;
      if (!SYSTEM_KEY.test(key)) {
        if (!isPhraseCatalog && !KEY_SHAPE.test(key)) errors.push(`${where}: key must look like screen.element.role`);
        if (!entry.comment?.trim()) errors.push(`${where}: missing comment (the translator's only context)`);
      }

      const sourceLeaves = leafUnits(entry.localizations?.[config.sourceLocale]);
      if (sourceLeaves.length === 0) {
        errors.push(`${where}: missing ${config.sourceLocale} source`);
        continue;
      }

      for (const locale of config.locales) {
        const targetLeaves = leafUnits(entry.localizations?.[locale]);
        if (targetLeaves.length === 0) {
          errors.push(`${where}: missing ${locale}`);
          continue;
        }
        coverage[locale] += targetLeaves.length;
        for (const leaf of targetLeaves) {
          if (leaf.stringUnit.state !== "translated") errors.push(`${where} [${locale}]: state is ${leaf.stringUnit.state ?? "missing"}`);
        }
        if (locale === config.sourceLocale) continue;

        // A language may need more or fewer plural forms than English, so only leaves that exist
        // on both sides are compared; a singular string is always compared.
        for (const sourceLeaf of sourceLeaves) {
          const targetLeaf = targetLeaves.find(candidate => JSON.stringify(candidate.path) === JSON.stringify(sourceLeaf.path));
          if (!targetLeaf) continue;
          const source = sourceLeaf.stringUnit.value;
          const target = targetLeaf.stringUnit.value;
          for (const issue of validatePair(source, target, config.protectedTerms)) errors.push(`${where} [${locale}]: ${issue}`);
          if (isPhraseCatalog && source.includes(APP_NAME_TOKEN) && !target.includes(APP_NAME_TOKEN)) {
            errors.push(`${where} [${locale}]: Siri phrase lost ${APP_NAME_TOKEN}`);
          }
          const isProtected = config.protectedTerms.some(term => source.includes(term));
          if (source === target && /[A-Za-z]{4}/.test(source) && !isProtected) warnings.push(`${where} [${locale}]: unchanged from source`);
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
  for (const locale of config.locales) console.log(`  ${locale}: ${coverage[locale]} units`);
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

async function exportUnits() {
  const config = await readConfig();
  const glossary = await readGlossary();
  const locale = option("locale") ?? fail("export needs --locale <code>");
  if (locale === config.sourceLocale) fail(`${locale} is the source language`);
  const everything = flag("all");

  const units = [];
  for (const file of await catalogFiles()) {
    const catalog = await readCatalog(file);
    for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
      const existing = leafUnits(entry.localizations?.[locale]);
      for (const leaf of leafUnits(entry.localizations?.[config.sourceLocale])) {
        const current = existing.find(candidate => JSON.stringify(candidate.path) === JSON.stringify(leaf.path));
        if (current && !everything) continue;
        units.push({
          catalog: relative(file),
          key,
          path: leaf.path,
          comment: entry.comment ?? "",
          source: leaf.stringUnit.value,
          translation: current?.stringUnit.value ?? "",
        });
      }
    }
  }

  const document = {
    locale,
    language: config.localeNames[locale] ?? locale,
    instructions: [
      `Translate each "source" from English into ${config.localeNames[locale] ?? locale} and write it into "translation".`,
      "Change nothing else: catalog, key, path, comment and source identify the string.",
      "Read the comment first; it says where the text appears and how much room it has.",
      "Keep every placeholder (%@, %lld, %1$@ …) exactly; you may reorder numbered ones.",
      "Keep line breaks. Do not add quotes or trailing punctuation the source does not have.",
      `Never translate these terms: ${config.protectedTerms.join(", ")}.`,
      "Use the glossary for recurring words so the same thing has one name on every screen.",
      "Write the way a native speaker's phone talks to them: short, plain, informal-polite.",
    ],
    glossary: Object.fromEntries(Object.entries(glossary.terms).map(([term, entry]) => [term, { note: entry.note, translation: entry[locale] ?? "" }])),
    units,
  };

  const text = `${JSON.stringify(document, null, 2)}\n`;
  const out = option("out");
  if (out) {
    await fs.writeFile(out, text, "utf8");
    console.error(`${units.length} units written to ${out}`);
  } else {
    process.stdout.write(text);
  }
}

async function importUnits() {
  const config = await readConfig();
  const file = positional[0] ?? fail("import needs a file produced by export");
  const document = JSON.parse(await fs.readFile(file, "utf8"));
  const locale = document.locale ?? fail("the file has no locale");
  if (!config.locales.includes(locale)) fail(`${locale} is not a project locale yet; run: l10n.mjs add-locale ${locale} <Language name>`);

  const catalogs = new Map();
  const errors = [];
  let written = 0;
  for (const unit of document.units ?? []) {
    const where = `${unit.catalog} :: ${unit.key}`;
    const absolute = path.join(repositoryRoot, unit.catalog);
    if (!catalogs.has(absolute)) {
      try { catalogs.set(absolute, await readCatalog(absolute)); }
      catch { errors.push(`${where}: no such catalog`); continue; }
    }
    const catalog = catalogs.get(absolute);
    const entry = catalog.strings?.[unit.key];
    if (!entry) { errors.push(`${where}: no such key`); continue; }

    // The English may have changed since the export. A translation of the old sentence must not
    // be filed under the new one.
    const sourceLeaf = leafUnits(entry.localizations?.[config.sourceLocale]).find(leaf => JSON.stringify(leaf.path) === JSON.stringify(unit.path ?? []));
    if (!sourceLeaf) { errors.push(`${where}: no such variation`); continue; }
    if (sourceLeaf.stringUnit.value !== unit.source) { errors.push(`${where}: source changed since export`); continue; }

    const issues = validatePair(unit.source, unit.translation, config.protectedTerms);
    if (issues.length) { errors.push(`${where}: ${issues.join(", ")}`); continue; }
    setTranslation(catalog, unit.key, unit.path ?? [], locale, unit.translation);
    written += 1;
  }

  // All or nothing: a half-imported language is harder to notice than a rejected file.
  if (errors.length) {
    console.error(`Nothing was written. Fix these ${errors.length} and import again:`);
    for (const error of errors.slice(0, 100)) console.error(`  - ${error}`);
    process.exit(1);
  }
  for (const [absolute, catalog] of catalogs) await atomicWrite(absolute, appleJSON(catalog));
  console.log(`${written} ${locale} translations written to ${catalogs.size} catalogs. Now run: l10n.mjs validate`);
}

async function addLocale() {
  const [locale, ...nameParts] = positional;
  const name = nameParts.join(" ");
  if (!locale || !name) fail("add-locale needs a code and a name, e.g. add-locale de German");
  const config = await readConfig();
  if (config.locales.includes(locale)) fail(`${locale} is already a project locale`);

  config.locales.push(locale);
  config.localeNames[locale] = name;
  await atomicWrite(configPath, `${JSON.stringify(config, null, 2)}\n`);

  const project = await fs.readFile(projectPath, "utf8");
  const updated = project.replace(/(knownRegions\s*=\s*\(\r?\n)([\s\S]*?)(\t+)Base,/, (_, open, regions, indent) => {
    const entry = /^[A-Za-z0-9_]+$/.test(locale) ? locale : `"${locale}"`;
    return `${open}${regions}${indent}${entry},\n${indent}Base,`;
  });
  if (updated === project) fail("could not find knownRegions in the Xcode project");
  await atomicWrite(projectPath, updated);

  console.log(`${name} (${locale}) added. Next:`);
  console.log(`  node tools/localization/l10n.mjs export --locale ${locale} --out ${locale}.json`);
  console.log(`  …translate ${locale}.json…`);
  console.log(`  node tools/localization/l10n.mjs import ${locale}.json`);
}

const commands = { validate, export: exportUnits, import: importUnits, "add-locale": addLocale };
if (!commands[command]) fail("usage: l10n.mjs validate | export --locale <code> [--all] [--out file] | import <file> | add-locale <code> <name>");
await commands[command]();
