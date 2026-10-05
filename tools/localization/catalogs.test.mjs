import assert from "node:assert/strict";
import test from "node:test";
import { appleJSON, expectedPaths, leafUnits, placeholderSignature, pluralChoice, setTranslation, sourceLeafFor, validatePair } from "./catalogs.mjs";

test("a translation may reorder numbered placeholders", () => {
  const source = "%1$lld of %2$lld meals · %@";
  const reordered = "%@ · %2$lld meals, %1$lld done";
  assert.equal(placeholderSignature(source), placeholderSignature(reordered));
  assert.deepEqual(validatePair(source, reordered, []), []);
});

test("a translation may not drop a placeholder", () => {
  assert.deepEqual(validatePair("Delete %lld meals?", "Delete meals?", []), ["placeholder mismatch"]);
});

test("protected terms and line breaks survive translation", () => {
  assert.deepEqual(validatePair("DietFlow\nPlus", "Other\nPlus", ["DietFlow"]), ["protected term changed: DietFlow"]);
  assert.deepEqual(validatePair("First\nSecond", "First Second", []), ["newline mismatch"]);
});

test("an empty translation is rejected on its own", () => {
  assert.deepEqual(validatePair("Today", "  ", []), ["empty translation"]);
});

test("plural variations are read and written leaf by leaf", () => {
  const catalog = {
    strings: {
      "plan.meals.count": {
        localizations: {
          en: {
            variations: {
              plural: {
                one: { stringUnit: { state: "translated", value: "%lld meal" } },
                other: { stringUnit: { state: "translated", value: "%lld meals" } },
              },
            },
          },
        },
      },
    },
  };
  const leaves = leafUnits(catalog.strings["plan.meals.count"].localizations.en);
  assert.deepEqual(leaves.map(leaf => leaf.path), [["variations", "plural", "one"], ["variations", "plural", "other"]]);

  setTranslation(catalog, "plan.meals.count", ["variations", "plural", "other"], "tr", "%lld öğün");
  assert.equal(catalog.strings["plan.meals.count"].localizations.tr.variations.plural.other.stringUnit.value, "%lld öğün");
});

test("catalogs are written the way Xcode writes them", () => {
  assert.equal(appleJSON({ a: { b: 1 } }), '{\n  "a" : {\n    "b" : 1\n  }\n}\n');
  // Sorted keys at every level, so a written file matches one Xcode saved.
  assert.equal(appleJSON({ tr: 1, es: { value: 2, state: 3 } }), '{\n  "es" : {\n    "state" : 3,\n    "value" : 2\n  },\n  "tr" : 1\n}\n');
});

const languages = {
  ar: { plural: ["zero", "one", "two", "few", "many", "other"] },
  ja: { plural: ["other"] },
  tr: { plural: ["one", "other"] },
};
const counted = leafUnits({
  variations: {
    plural: {
      one: { stringUnit: { state: "translated", value: "%lld meal" } },
      other: { stringUnit: { state: "translated", value: "%lld meals" } },
    },
  },
});

test("a plural string needs every form the target language uses", () => {
  assert.deepEqual(expectedPaths(counted, "ar", languages).map(pluralChoice), ["zero", "one", "two", "few", "many", "other"]);
  assert.deepEqual(expectedPaths(counted, "ja", languages).map(pluralChoice), ["other"]);
  assert.deepEqual(expectedPaths(counted, "tr", languages).map(pluralChoice), ["one", "other"]);
  // A language the registry does not know is treated like English.
  assert.deepEqual(expectedPaths(counted, "xx", languages).map(pluralChoice), ["one", "other"]);
});

test("forms English lacks are translated from English's other form", () => {
  const source = (choice) => sourceLeafFor(counted, ["variations", "plural", choice]).stringUnit.value;
  assert.equal(source("one"), "%lld meal");
  assert.equal(source("few"), "%lld meals");
  assert.equal(source("zero"), "%lld meals");
});

test("a plain string needs exactly one translation", () => {
  const plain = leafUnits({ stringUnit: { state: "translated", value: "Today" } });
  assert.deepEqual(expectedPaths(plain, "ar", languages), [[]]);
  assert.equal(sourceLeafFor(plain, []).stringUnit.value, "Today");
});
