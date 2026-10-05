import assert from "node:assert/strict";
import test from "node:test";
import { appleJSON, leafUnits, placeholderSignature, setTranslation, validatePair } from "./catalogs.mjs";

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
});
