// The real widget with the installed Omarchy UI kit, a synthetic window and a
// bar host that records settings writes instead of saving them.
import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  id: harness

  property var writes: []
  property var widget: loader.item
  property var steps: []
  property var pending: null
  property int failures: 0

  QtObject {
    id: host
    property string position: "top"
    property real barSize: Style.bar.sizeHorizontal
    property bool vertical: false
    property color urgent: "red"
    property color background: "black"
    property color barForeground: "white"
    property color foreground: "white"
    property string fontFamily: Style.font.family
    property var activePopout: null
    function requestPopout(key) { activePopout = key }
    function releasePopout(key) { if (activePopout === key) activePopout = null }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    property var shell: QtObject {
      function updateEntryInline(id, settings) {
        harness.writes.push({ id: id, settings: JSON.parse(JSON.stringify(settings)) })
        return true
      }
    }
  }

  FloatingWindow {
    implicitWidth: 900
    implicitHeight: 60
    color: "transparent"

    Loader {
      id: loader
      height: host.barSize
      source: Qt.resolvedUrl("BarWidget.qml")
      onLoaded: {
        item.bar = host
        Qt.callLater(harness.start)
      }
    }
  }

  Timer {
    id: stepTimer
    onTriggered: harness.runPending()
  }

  function assert(value, message) {
    if (!value) throw new Error(message)
  }

  function show(title) {
    widget.hyprlandToplevel = {
      title: title,
      lastIpcObject: { "class": "org.gnome.Nautilus", initialClass: "org.gnome.Nautilus", pid: 0 }
    }
  }

  // Popup content is created with the widget, so controls are found closed.
  function find(node, predicate, depth) {
    if (!node || (depth || 0) > 40) return null
    if (predicate(node)) return node
    var lists = [node.data, node.children]
    for (var l = 0; l < lists.length; l++) {
      var list = lists[l]
      if (!list) continue
      for (var i = 0; i < list.length; i++) {
        var found = find(list[i], predicate, (depth || 0) + 1)
        if (found) return found
      }
    }
    return null
  }

  function control(property, value) {
    var found = find(widget, function(node) { return node[property] === value && typeof node.clicked === "function" })
    assert(found, "missing control " + value)
    return found
  }

  // Shows a short title, then a long one, and reports the width straight
  // after the change and once any animation has finished.
  function resizeSteps(name, settings, setup, check) {
    var state = {}
    return [
      { delay: 0, run: function() {
        if (setup) setup()
        widget.settings = settings
        show("Notes")
      } },
      { delay: 400, run: function() {
        state.before = widget.implicitWidth
        show("A much longer synthetic window title for the resize check")
        state.immediate = widget.implicitWidth
      } },
      { delay: 500, run: function() {
        state.settled = widget.implicitWidth
        assert(state.settled > state.before + 50, name + ": the long title did not widen the widget")
        check(state)
      } }
    ]
  }

  function iconSteps() {
    var fifo = Quickshell.env("WIDGET_TEST_FIFO_ICON")
    var image = Quickshell.env("WIDGET_TEST_FILE_ICON")
    return [
      { delay: 0, run: function() {
        assert(fifo && image, "icon fixtures missing")
        show("Icons")
        widget.iconName = fifo
      } },
      { delay: 500, run: function() {
        assert(widget.iconSource.indexOf("icon-fifo") === -1, "a FIFO icon path was loaded: " + widget.iconSource)
        widget.iconName = "file://" + image
      } },
      { delay: 500, run: function() {
        assert(widget.iconSource.indexOf("icon.png") !== -1, "a regular icon file was not loaded: " + widget.iconSource)
        widget.iconName = ""
      } }
    ]
  }

  function start() {
    steps = [].concat(
      iconSteps(),
      [{ delay: 0, run: function() {
        assert(widget.animateWidth === true, "the width animation must default to on")
        assert(widget.widthAnimationDuration === 180, "unexpected default duration " + widget.widthAnimationDuration)
      } }],
      resizeSteps("default", {}, null, function(state) {
        assert(state.immediate < state.settled - 50, "default: the width should animate, got "
          + state.immediate + " then " + state.settled)
      }),
      resizeSteps("animateWidth off", { animateWidth: false }, null, function(state) {
        assert(state.immediate === state.settled, "animateWidth off: the width should change at once, got "
          + state.immediate + " then " + state.settled)
      }),
      resizeSteps("Omarchy animations off", {}, function() { Style.reduceMotion = true }, function(state) {
        Style.reduceMotion = false
        assert(state.immediate === state.settled, "Omarchy animations off: the width should change at once, got "
          + state.immediate + " then " + state.settled)
      }),
      [{ delay: 0, run: function() {
        widget.settings = { iconSize: 18 }
        writes = []
        var toggle = control("label", "Animate width changes")
        assert(toggle.checked === true, "the toggle should start on")
        toggle.clicked()
        assert(writes.length === 1, "the toggle should save once, saved " + writes.length + " times")
        assert(writes[0].id === "crmne.active-window", "saved to " + writes[0].id)
        assert(writes[0].settings.animateWidth === false && writes[0].settings.iconSize === 18,
          "unexpected saved settings " + JSON.stringify(writes[0].settings))
        assert(widget.animateWidth === false && toggle.checked === false, "the toggle did not turn the animation off")
        toggle.clicked()
        assert(writes.length === 2 && writes[1].settings.animateWidth === true, "the toggle did not turn it back on")
      } }],
      [{ delay: 0, run: function() {
        widget.settings = { id: "crmne.active-window", iconSaturation: 0, iconSize: 22, maxWidth: 600,
                            showTitle: false, animateWidth: false }
        writes = []
        control("text", "Reset to defaults").clicked()
        var expected = { id: "crmne.active-window", iconSaturation: 100, iconSize: 16, maxWidth: 280,
                         showTitle: true, animateWidth: true }
        assert(writes.length === 1, "reset should save once, saved " + writes.length + " times")
        assert(JSON.stringify(writes[0].settings) === JSON.stringify(expected),
          "unexpected reset settings " + JSON.stringify(writes[0].settings))
        assert(widget.showTitle && widget.animateWidth && widget.maxLabelWidth === 280
          && widget.configuredIconSize === 16 && widget.saturationEffect === 0, "the widget did not return to its defaults")
        assert(control("label", "Show window title").checked === true, "the title toggle did not follow the reset")
      } }]
    )
    next()
  }

  function next() {
    if (steps.length === 0) {
      console.log(failures === 0 ? "WIDGET_TEST_PASS" : "WIDGET_TEST_FAIL")
      Qt.exit(failures === 0 ? 0 : 1)
      return
    }
    pending = steps.shift()
    stepTimer.interval = Math.max(1, pending.delay)
    stepTimer.start()
  }

  function runPending() {
    try {
      pending.run()
    } catch (e) {
      failures++
      console.log("WIDGET_TEST_FAIL " + e.message)
    }
    next()
  }
}
