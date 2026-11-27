const assert = require("node:assert/strict")
const test = require("node:test")
const AppIconModel = require("../AppIconModel.js")

test("icons given as files are recognised so they can be checked first", () => {
  assert.equal(AppIconModel.localIconPath("/opt/app/icon.png"), "/opt/app/icon.png")
  assert.equal(AppIconModel.localIconPath("file:///opt/my%20app/icon.png"), "/opt/my app/icon.png")
  assert.equal(AppIconModel.localIconPath("firefox"), "")
  assert.equal(AppIconModel.localIconPath("image://icon/firefox"), "")
  assert.equal(AppIconModel.localIconPath(""), "")
  assert.equal(AppIconModel.localIconPath("file:///bad%zz"), "")
})
