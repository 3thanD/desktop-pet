import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

// Omarchy host adapter: the only file that knows about the Omarchy shell.
// It exposes plain properties that PetCore consumes:
//   accent, background, foreground  live theme colors (Commons.Color)
//   colorsRaw                       the theme's colors.toml (full palette)
//   themeName                       e.g. "tokyo-night"
//   uiFont                          the shell's UI font family
//   popupBg/popupFg/popupBorder, selBg/selFg, radius   popup styling
//   reload()                        re-read theme files
Item {
  id: host

  readonly property string name: "omarchy"
  readonly property string themeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current"

  readonly property color accent: Commons.Color.accent
  readonly property color background: Commons.Color.background
  readonly property color foreground: Commons.Color.foreground
  readonly property string uiFont: Style.font.family
  // popup look (context menu), matching Omarchy's own popups
  readonly property color popupBg: Commons.Color.popups.background
  readonly property color popupFg: Commons.Color.popups.text
  readonly property color popupBorder: Commons.Color.popups.border
  readonly property color selBg: Commons.Color.menu.selectedBackground
  readonly property color selFg: Commons.Color.menu.selectedText
  readonly property int radius: Style.cornerRadius
  property string colorsRaw: ""
  property string themeName: ""

  function reload() { themeNameFile.reload(); colorsFile.reload() }

  FileView {
    id: colorsFile
    path: host.themeDir + "/theme/colors.toml"
    printErrors: false
    onLoaded: host.colorsRaw = text()
  }
  FileView {
    id: themeNameFile
    path: host.themeDir + "/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: host.reload()
    onLoaded: host.themeName = String(text() || "").trim()
  }

  // `omarchy theme set` swaps Commons.Color live; re-read the files with it.
  Connections {
    target: Commons.Color
    function onAccentChanged() { reloadTimer.restart() }
    function onBackgroundChanged() { reloadTimer.restart() }
    function onForegroundChanged() { reloadTimer.restart() }
  }
  Timer { id: reloadTimer; interval: 300; onTriggered: host.reload() }
}
