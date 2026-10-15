// Isolated screenshot host: production widget, workspaces and popup card,
// installed Omarchy theme, synthetic window and workspace data.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons

ShellRoot {
  id: host
  property var fixtures: ({})
  property real widgetX: 0
  property real widgetWidth: 0

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

  FloatingWindow {
    id: preview
    implicitWidth: 1280; implicitHeight: 800
    visible: false
    color: "#090503"

    Item {
      id: composition
      width: 1280; height: 800

      Image {
        anchors.fill: parent
        source: Quickshell.env("CAPTURE_WALLPAPER")
        fillMode: Image.PreserveAspectCrop
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: 0.7 }
      }
      Rectangle { anchors.fill: parent; color: "#a6000000" }

      // Captures are 4x device pixels; shown at 2x (bars) and 1.5x (panel).
      Shot {
        id: titledBar
        file: "bar-titled.png"
        zoom: 2
        x: popupShot.x + popupShot.width / 2 - (host.widgetX + host.widgetWidth / 2) * zoom
        y: 120
      }
      Shot {
        id: popupShot
        file: "settings.png"
        zoom: 1.5
        x: 520
        y: titledBar.y + titledBar.height + 32
      }
      Shot {
        file: "bar-iconOnly.png"
        zoom: 2
        x: 130
        y: 420
      }
    }
  }

  component Shot: Image {
    property string file
    property real zoom: 1
    source: preview.visible ? "file://" + Quickshell.env("CAPTURE_OUTPUT") + "/" + file : ""
    width: sourceSize.width / 4 * zoom
    height: sourceSize.height / 4 * zoom
    smooth: true
    mipmap: true
    layer.enabled: true
    layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.6; shadowVerticalOffset: 14 }
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
      host.widgetX = row.x + widget.x
      host.widgetWidth = w.implicitWidth
      return JSON.stringify({ entry: w.desktopEntry ? String(w.desktopEntry.name) : "", icon: w.iconSource, pidLookup: w.executableLookupPid })
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

    function preparePreview(): void { preview.visible = true }

    function grabPreview(path: string): string {
      return composition.grabToImage(result => result.saveToFile(path), Qt.size(640, 400)) ? "ok" : "Capture failed"
    }
  }
}
