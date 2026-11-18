const assert = require("node:assert/strict")
const test = require("node:test")
const manifest = require("../manifest.json")
const SettingsModel = require("../SettingsModel.js")

test("defaults match the manifest's defaults and schema", () => {
  const defaults = SettingsModel.defaults()
  assert.deepEqual(defaults, manifest.barWidget.defaults)
  const schema = Object.fromEntries(manifest.barWidget.schema.map(entry => [entry.key, entry.defaultValue]))
  assert.deepEqual(schema, defaults)
})

test("defaults are a new object each time", () => {
  const first = SettingsModel.defaults()
  first.iconSize = 22
  assert.equal(SettingsModel.defaults().iconSize, 16)
})

test("reset returns every declared setting to its default and keeps the rest", () => {
  const current = {
    id: "crmne.active-window",
    iconSaturation: 0,
    iconSize: 22,
    maxWidth: 600,
    showTitle: false,
    animateWidth: false
  }
  const next = SettingsModel.reset(current)
  assert.deepEqual(next, { id: "crmne.active-window", ...manifest.barWidget.defaults })
  assert.notEqual(next, current)
  assert.equal(current.iconSize, 22, "reset must not change the object it was given")
})

test("reset works without stored settings", () => {
  assert.deepEqual(SettingsModel.reset(undefined), manifest.barWidget.defaults)
  assert.deepEqual(SettingsModel.reset(null), manifest.barWidget.defaults)
})
