// Isolated screenshot host: production widget, workspaces and popup card,
// installed Omarchy theme, synthetic window and workspace data.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

ShellRoot {
  id: host
  property var fixtures: ({})

  Component.onCompleted: Style.cornerRadius = 10

  FileView {
    path: Quickshell.env("CAPTURE_FIXTURES")
    onLoaded: host.fixtures = JSON.parse(text())
  }

  QtObject {
    id: bar
    property string position: "top"
    property real barSize: Style.bar.sizeHorizontal
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property color urgent: Color.bar.active
    property color background: Color.bar.background
    property color barForeground: Color.bar.text
    property color foreground: Color.bar.text
    property string fontFamily: Style.font.family
    property var activePopout: null
    function requestPopout(key) { activePopout = key }
    function releasePopout(key) { if (activePopout === key) activePopout = null }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    function run(command) {}
    property var shell: QtObject { property var appLibrary: library }
  }

  AppLibrary { id: library }

  FloatingWindow {
    implicitWidth: 1000; implicitHeight: 60
    color: "transparent"

    Rectangle {
      id: strip
      width: row.width + Style.space(16)
      height: bar.barSize
      color: Color.bar.background
      radius: 6

      Row {
        id: row
        x: Style.space(8)
        height: parent.height

        Workspaces {
          id: workspaces
          bar: bar
          height: parent.height
        }

        Loader {
          id: widget
          height: parent.height
          source: "file://" + Quickshell.env("CAPTURE_PLUGIN") + "/BarWidget.qml"
          onLoaded: item.bar = bar
        }
      }
    }
  }

  IpcHandler {
    target: "capture"

    function ready(): bool {
      return !!widget.item && !!host.fixtures.titled && Object.keys(library.iconIndex).length > 0
    }

    function show(name: string, popup: bool): string {
      var sample = host.fixtures[name]
      var ws = host.fixtures.workspaces
      var list = []
      for (var i = 0; i < ws.occupied.length; i++)
        list.push({ id: ws.occupied[i], toplevels: { values: [{}] } })
      workspaces.captureWorkspaces = list
      workspaces.captureFocused = { id: ws.focused }
      var w = widget.item
      w.settingsOpen = false
      w.settings = sample.settings
      w.hyprlandToplevel = { title: sample.title, lastIpcObject: { "class": sample["class"], initialClass: sample["class"], pid: 0 } }
      w.settingsOpen = popup
      return JSON.stringify({ entry: w.desktopEntry ? String(w.desktopEntry.name) : "", icon: w.iconSource, pidLookup: w.executableLookupPid,
                             widgetX: row.x + widget.x })
    }

    function grabBar(path: string): string {
      return strip.grabToImage(result => result.saveToFile(path)) ? "ok" : "Capture failed"
    }

    function grabPopup(path: string): string {
      var w = widget.item
      for (var i = 0; i < w.data.length; i++) {
        var card = w.data[i].captureCard
        if (card !== undefined)
          return card.grabToImage(result => result.saveToFile(path)) ? "ok" : "Capture failed"
      }
      return "No popup card"
    }
  }
}
