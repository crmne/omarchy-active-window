import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "AppIconModel.js" as AppIconModel

BarWidget {
  id: root
  moduleName: "crmne.active-window"

  readonly property var waylandToplevel: ToplevelManager.activeToplevel
  readonly property var hyprlandToplevel: Hyprland.activeToplevel
  readonly property var ipcObject: hyprlandToplevel && hyprlandToplevel.lastIpcObject
    ? hyprlandToplevel.lastIpcObject : ({})
  readonly property string appClass: String(ipcObject.class || (waylandToplevel ? waylandToplevel.appId : "") || "")
  readonly property string initialClass: String(ipcObject.initialClass || "")
  readonly property int activePid: Number(ipcObject.pid || 0)
  readonly property string title: String(
    (hyprlandToplevel ? hyprlandToplevel.title : "")
      || (waylandToplevel ? waylandToplevel.title : "")
      || appClass
      || ""
  )

  property string executablePath: ""
  property int executableLookupPid: 0
  property bool settingsOpen: false
  readonly property bool opened: settingsOpen

  readonly property string executableName: {
    var path = executablePath
    return path ? path.slice(path.lastIndexOf("/") + 1) : ""
  }
  readonly property var desktopEntries: DesktopEntries.applications ? DesktopEntries.applications.values : []
  readonly property var desktopEntry: AppIconModel.resolve(desktopEntries, [appClass, initialClass, executableName])
  readonly property string iconName: desktopEntry ? String(desktopEntry.icon || "") : ""
  readonly property string iconSource: resolveIconSource(iconName)

  readonly property bool showTitle: setting("showTitle", true) === true
  readonly property int maxLabelWidth: Math.max(80, Number(setting("maxWidth", 280)))
  readonly property int configuredIconSize: Math.max(12, Number(setting("iconSize", 16)))
  readonly property int iconSize: Math.min(configuredIconSize, Math.max(12, barSize - Style.space(6)))
  readonly property real saturationEffect: {
    var percent = Math.max(0, Math.min(200, Number(setting("iconSaturation", 100))))
    return (percent - 100) / 100
  }

  visible: title !== ""
  implicitWidth: visible
    ? (vertical || !showTitle
      ? barSize
      : iconSize + Style.space(6) + Math.min(maxLabelWidth, titleLabel.implicitWidth) + Style.space(16))
    : 0
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  function resolveIconSource(icon) {
    var value = String(icon || "")
    if (bar && bar.shell && bar.shell.appLibrary) return bar.shell.appLibrary.iconSource(value)
    if (!value) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true) || Quickshell.iconPath("application-x-executable", true)
  }

  function refreshExecutable() {
    executablePath = ""
    if (activePid <= 0 || executableLookup.running) return
    executableLookupPid = activePid
    executableLookup.command = ["readlink", "-f", "/proc/" + activePid + "/exe"]
    executableLookup.running = true
  }

  function close() {
    settingsOpen = false
  }

  function open() {
    settingsOpen = true
  }

  function toggle() {
    settingsOpen = !settingsOpen
  }

  function previewSetting(key, value) {
    var next = Object.assign({}, settings || {})
    next[key] = value
    settings = next
  }

  function saveSetting(key, value) {
    previewSetting(key, value)
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, settings)
  }

  onActivePidChanged: Qt.callLater(refreshExecutable)

  Process {
    id: executableLookup

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.executableLookupPid === root.activePid)
          root.executablePath = String(text || "").trim()
      }
    }

    onExited: {
      if (root.executableLookupPid !== root.activePid) Qt.callLater(root.refreshExecutable)
    }
  }

  Component.onCompleted: refreshExecutable()

  Row {
    id: contents
    anchors.centerIn: parent
    spacing: Style.space(6)

    Item {
      id: iconContainer
      width: root.iconSize
      height: root.iconSize
      anchors.verticalCenter: parent.verticalCenter

      Image {
        id: appIcon
        anchors.fill: parent
        source: root.iconSource
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
          saturation: root.saturationEffect
        }
      }

      Text {
        anchors.centerIn: parent
        visible: appIcon.status === Image.Error
        text: "󰖯"
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Item {
      id: titleClip
      width: Math.min(root.maxLabelWidth, titleLabel.implicitWidth)
      height: titleLabel.implicitHeight
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && root.showTitle
      clip: true

      Text {
        id: titleLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        opacity: 0.9
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: root.waylandToplevel ? Qt.PointingHandCursor : Qt.ArrowCursor

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.settingsOpen = !root.settingsOpen
      } else if (mouse.button === Qt.MiddleButton) {
        if (root.waylandToplevel) root.waylandToplevel.close()
      } else {
        root.settingsOpen = false
        if (root.waylandToplevel) root.waylandToplevel.activate()
      }
    }
    onEntered: if (root.bar) {
      var appName = root.desktopEntry ? String(root.desktopEntry.name || "") : root.appClass
      root.bar.showTooltip(root, root.title + (appName ? "\n" + appName : "") + "\nRight-click: appearance")
    }
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: settingsPopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.settingsOpen
    contentWidth: fittedContentWidth(Style.space(330))
    contentHeight: fittedContentHeight(settingsColumn.implicitHeight)

    Column {
      id: settingsColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        text: "ACTIVE WINDOW"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        text: root.desktopEntry
          ? String(root.desktopEntry.name || root.appClass)
          : (root.appClass || "No desktop entry matched")
        color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      PanelSeparator {
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      SettingSlider {
        label: "Icon saturation"
        suffix: "%"
        minimum: 0
        maximum: 200
        step: 5
        currentValue: Number(root.setting("iconSaturation", 100))
        onPreviewed: function(value) { root.previewSetting("iconSaturation", Math.round(value)) }
        onCommitted: function(value) { root.saveSetting("iconSaturation", Math.round(value)) }
      }

      SettingSlider {
        label: "Icon size"
        suffix: "px"
        minimum: 12
        maximum: 22
        step: 1
        currentValue: Number(root.setting("iconSize", 16))
        onPreviewed: function(value) { root.previewSetting("iconSize", Math.round(value)) }
        onCommitted: function(value) { root.saveSetting("iconSize", Math.round(value)) }
      }

      SettingSlider {
        label: "Title width"
        suffix: "px"
        minimum: 80
        maximum: 600
        step: 10
        currentValue: Number(root.setting("maxWidth", 280))
        onPreviewed: function(value) { root.previewSetting("maxWidth", Math.round(value / 10) * 10) }
        onCommitted: function(value) { root.saveSetting("maxWidth", Math.round(value / 10) * 10) }
      }

      Toggle {
        width: parent.width
        label: "Show window title"
        description: "Turn this off for an icon-only widget."
        checked: root.showTitle
        foreground: root.bar ? root.bar.foreground : Color.foreground
        accent: Color.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onClicked: root.saveSetting("showTitle", !root.showTitle)
      }

      Text {
        id: resetText
        width: parent.width
        text: "Reset to defaults"
        color: resetMouse.containsMouse
               ? (root.bar ? root.bar.barForeground : "white")
               : (root.bar ? Qt.darker(root.bar.foreground, 1.8) : Color.foreground)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.underline: true
        horizontalAlignment: Text.AlignLeft
        MouseArea{
          id: resetMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          onClicked:{
            root.saveSetting("iconSaturation", 100)
            root.saveSetting("iconSize", 16)
            root.saveSetting("maxWidth", 280)
          }
        }
      }
    }
  }

  component SettingSlider: Column {
    id: sliderSetting

    required property string label
    property string suffix: ""
    required property real minimum
    required property real maximum
    required property real step
    required property real currentValue

    signal previewed(real value)
    signal committed(real value)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(5)

    Item {
      width: parent.width
      implicitHeight: Math.max(settingLabel.implicitHeight, settingValue.implicitHeight)

      Text {
        id: settingLabel
        anchors.left: parent.left
        text: sliderSetting.label
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        id: settingValue
        anchors.right: parent.right
        text: Math.round(slider.dragging ? slider.liveValue : sliderSetting.currentValue) + sliderSetting.suffix
        color: root.bar ? Qt.darker(root.bar.foreground, 1.35) : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.bar
      minimum: sliderSetting.minimum
      maximum: sliderSetting.maximum
      step: sliderSetting.step
      integer: true
      value: sliderSetting.currentValue
      onMoved: function(value) { sliderSetting.previewed(value) }
      onReleased: function(value) { sliderSetting.committed(value) }
    }
  }
}
