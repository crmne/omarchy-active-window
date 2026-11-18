// The widget's settings defaults, kept equal to manifest.json's
// barWidget.defaults by tests/settings.test.js.
function defaults() {
  return {
    iconSaturation: 100,
    iconSize: 16,
    maxWidth: 280,
    showTitle: true,
    animateWidth: true
  }
}

// A new settings object with every declared setting at its default. Keys the
// widget does not own, such as the shell's `id`, are kept.
function reset(settings) {
  var next = Object.assign({}, settings || {})
  var values = defaults()
  for (var key in values) next[key] = values[key]
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    defaults: defaults,
    reset: reset
  }
}
