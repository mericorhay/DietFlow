import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const directory = path.dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = path.resolve(directory, "../..");
export const configPath = path.join(directory, "localization.config.json");
export const glossaryPath = path.join(directory, "glossary.json");
export const languagesPath = path.join(directory, "languages.json");
export const projectPath = path.join(repositoryRoot, "DietFlow.xcodeproj/project.pbxproj");

export async function readConfig() {
  return JSON.parse(await fs.readFile(configPath, "utf8"));
}

export async function readGlossary() {
  return JSON.parse(await fs.readFile(glossaryPath, "utf8"));
}

/** Reference data for every language the app ships or has queued: names, direction, plurals. */
export async function readLanguages() {
  return JSON.parse(await fs.readFile(languagesPath, "utf8")).languages;
}

// MARK: Languages

/** "German", from the registry, the config, or the code itself. */
export function languageName(locale, languages, config = {}) {
  return languages[locale]?.name ?? config.localeNames?.[locale] ?? locale;
}

/** The CLDR plural categories a language needs, in CLDR order. Unknown languages get English's. */
export function pluralCategories(locale, languages) {
  return languages[locale]?.plural ?? ["one", "other"];
}

const PLURAL_ORDER = ["zero", "one", "two", "few", "many", "other"];

/** Where in a leaf's path its plural category sits, or -1 when the leaf is not a plural form. */
function pluralIndex(unitPath) {
  for (let index = 0; index + 2 < unitPath.length; index += 3) {
    if (unitPath[index] === "variations" && unitPath[index + 1] === "plural") return index + 2;
  }
  return -1;
}

/** The plural category of a leaf ("few"), or undefined for a plain string. */
export function pluralChoice(unitPath) {
  const index = pluralIndex(unitPath);
  return index < 0 ? undefined : unitPath[index];
}

function withPluralChoice(unitPath, choice) {
  const index = pluralIndex(unitPath);
  if (index < 0) return unitPath;
  const copy = [...unitPath];
  copy[index] = choice;
  return copy;
}

const samePath = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/**
 * The leaves a translation into `locale` must have, given the source's leaves. A plural string
 * needs every category the target language uses, whichever ones English has: Arabic needs six
 * forms of "%lld meals", Japanese one.
 */
export function expectedPaths(sourceLeaves, locale, languages) {
  const categories = pluralCategories(locale, languages);
  const paths = [];
  for (const leaf of sourceLeaves) {
    const candidates = pluralChoice(leaf.path) === undefined ? [leaf.path] : categories.map(choice => withPluralChoice(leaf.path, choice));
    for (const candidate of candidates) {
      if (!paths.some(existing => samePath(existing, candidate))) paths.push(candidate);
    }
  }
  return paths.sort((a, b) => PLURAL_ORDER.indexOf(pluralChoice(a)) - PLURAL_ORDER.indexOf(pluralChoice(b)));
}

/**
 * The source leaf a target leaf translates. A plural category English lacks ("few", "many",
 * "two", "zero") is written from English's "other"; "one" from "one" when English has it.
 */
export function sourceLeafFor(sourceLeaves, targetPath) {
  const exact = sourceLeaves.find(leaf => samePath(leaf.path, targetPath));
  if (exact) return exact;
  if (pluralChoice(targetPath) === undefined) return undefined;
  return sourceLeaves.find(leaf => samePath(leaf.path, withPluralChoice(targetPath, "other")))
    ?? sourceLeaves.find(leaf => pluralChoice(leaf.path) !== undefined && samePath(withPluralChoice(leaf.path, "other"), withPluralChoice(targetPath, "other")));
}

async function walk(current) {
  const result = [];
  for (const entry of await fs.readdir(current, { withFileTypes: true })) {
    if ([".git", ".build", "build", "DerivedData", ".wrangler", "node_modules"].includes(entry.name)) continue;
    const candidate = path.join(current, entry.name);
    if (entry.isDirectory()) result.push(...await walk(candidate));
    else if (entry.name.endsWith(".xcstrings")) result.push(candidate);
  }
  return result;
}

export async function catalogFiles() {
  return (await walk(repositoryRoot)).sort((a, b) => a.localeCompare(b));
}

export function relative(file) {
  return path.relative(repositoryRoot, file).replaceAll(path.sep, "/");
}

export async function readCatalog(file) {
  return JSON.parse(await fs.readFile(file, "utf8"));
}

// A localization is either one string or a tree of plural/device variations. Every string in
// that tree is a "leaf"; its path says which variation it belongs to.
export function leafUnits(localization, prefix = []) {
  if (!localization || typeof localization !== "object") return [];
  const units = [];
  if (localization.stringUnit) units.push({ path: prefix, stringUnit: localization.stringUnit });
  for (const [kind, choices] of Object.entries(localization.variations ?? {})) {
    for (const [choice, value] of Object.entries(choices)) {
      units.push(...leafUnits(value, [...prefix, "variations", kind, choice]));
    }
  }
  return units;
}

export function setTranslation(catalog, key, unitPath, locale, value) {
  const entry = catalog.strings[key];
  entry.localizations ??= {};
  entry.localizations[locale] ??= {};
  let cursor = entry.localizations[locale];
  for (let index = 0; index < unitPath.length; index += 3) {
    const [, kind, choice] = unitPath.slice(index, index + 3);
    cursor.variations ??= {};
    cursor.variations[kind] ??= {};
    cursor.variations[kind][choice] ??= {};
    cursor = cursor.variations[kind][choice];
  }
  cursor.stringUnit = { state: "translated", value };
}

export function placeholders(value) {
  // Apple string catalogs use printf placeholders. A literal %% is significant too.
  return value.match(/%(?:\d+\$)?(?:[-+#0 ']*\d*(?:\.\d+)?)?(?:hh|h|ll|l|L|z|j|t)?[@aAcCdDeEfFgGiIosSuUxXpn%]/g) ?? [];
}

// Sorted, so a translation may reorder arguments (%1$@ … %2$@) but never drop or add one.
export function placeholderSignature(value) {
  return placeholders(value).sort().join("|");
}

export function validatePair(source, target, protectedTerms) {
  const errors = [];
  if (typeof target !== "string" || target.trim().length === 0) return ["empty translation"];
  if (placeholderSignature(source) !== placeholderSignature(target)) errors.push("placeholder mismatch");
  if ((source.match(/\n/g) ?? []).length !== (target.match(/\n/g) ?? []).length) errors.push("newline mismatch");
  for (const term of protectedTerms.filter(term => source.includes(term))) {
    if (!target.includes(term)) errors.push(`protected term changed: ${term}`);
  }
  return errors;
}

function sortedKeys(value) {
  if (Array.isArray(value)) return value.map(sortedKeys);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(Object.keys(value).sort().map(key => [key, sortedKeys(value[key])]));
}

// Xcode writes catalogs with sorted keys and a space before each colon. Matching it keeps a
// tool-written file byte-identical to one Xcode saved, so diffs show only real changes.
export function appleJSON(value) {
  return `${JSON.stringify(sortedKeys(value), null, 2).replace(/^(\s*)"((?:\\.|[^"\\])*)":/gm, '$1"$2" :')}\n`;
}

export async function atomicWrite(file, contents) {
  const temporary = `${file}.localization-${process.pid}.tmp`;
  await fs.writeFile(temporary, contents, "utf8");
  await fs.rename(temporary, file);
}
