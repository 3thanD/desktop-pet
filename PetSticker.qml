import QtQuick
import Quickshell
import Quickshell.Wayland
import "Sprites.js" as Sprites

// A small click-through sticker on the desktop: the goblin's ransom note
// (kind "note") or a pixel doodle (kind "doodle"). Mapped only while shown;
// it hides itself after its duration.
PanelWindow {
  id: st

  required property var pet
  property string kind: "note"
  property bool shown: false
  property string text: ""
  property string icon: ""
  property int count: 0
  property int progress: 0
  property string image: ""
  property real px: 0
  property real py: 0
  readonly property real k: Math.max(0.75, pet.k)
  readonly property int doodlePx: Math.max(2, Math.round(3 * k))
  readonly property var doodleRows: kind === "doodle" ? Sprites.doodle(image) : null
  readonly property bool userImage: kind === "doodle" && doodleRows === null && /^[A-Za-z0-9_-]{1,40}\.png$/.test(image)

  function showNote(text, icon, count, seconds) {
    st.text = text; st.icon = icon; st.count = count; st.progress = 0
    px = pet.screenW / 2 - noteBox.width / 2
    py = pet.screenH - noteBox.height - 70 * k
    shown = true
    life.interval = Math.min(120, seconds) * 1000 + 2000; life.restart()
  }
  function hideNote() { shown = false; life.stop() }
  function showDoodle(name, where, seconds) {
    image = name
    var w = implicitWidth, h = implicitHeight
    if (where === "corner") { px = pet.screenW - w - 24; py = 60 }
    else if (where === "center") { px = pet.screenW / 2 - w / 2; py = pet.screenH / 2 - h / 2 }
    else { px = pet.posX + pet.sprLeft + pet.spr + 6; py = pet.posY + pet.sprTop - h / 2 }
    px = Math.max(0, Math.min(pet.screenW - w, px)); py = Math.max(0, Math.min(pet.screenH - h, py))
    shown = true
    life.interval = Math.min(60, seconds) * 1000; life.restart()
    art.requestPaint()
  }
  function hide() { shown = false; life.stop() }
  Timer { id: life; onTriggered: st.shown = false }

  visible: shown && pet.petScreen !== null
  screen: pet.petScreen
  anchors { top: true; left: true }
  margins { left: Math.round(px); top: Math.round(py) }
  implicitWidth: kind === "note" ? noteBox.width + 8 : (userImage ? 128 * k : (doodleRows ? doodleRows[0].length * doodlePx : 8))
  implicitHeight: kind === "note" ? noteBox.height + 8 : (userImage ? 128 * k : (doodleRows ? doodleRows.length * doodlePx : 8))
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-pet-sticker"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}

  // ransom note: a slightly crooked paper slip with cut-out style letters
  Rectangle {
    id: noteBox
    visible: st.kind === "note"
    x: 4; y: 4
    width: Math.round(190 * st.k); height: noteCol.implicitHeight + 16
    rotation: -2
    color: "#f4ecd4"
    border.width: 2; border.color: "#3a3226"
    Column {
      id: noteCol
      x: 8; y: 8
      width: parent.width - 16
      spacing: 4
      Row {
        spacing: 6
        Image {
          width: Math.round(22 * st.k); height: width
          sourceSize.width: width; sourceSize.height: height
          source: st.icon ? Quickshell.iconPath(st.icon, "application-x-executable") : ""
          visible: st.icon !== ""
        }
        Text {
          text: "RANSOM"
          font.family: st.pet.uiFont; font.pixelSize: Math.round(15 * st.k); font.bold: true
          color: "#b3261e"
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      Text {
        width: parent.width
        text: st.text
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: st.pet.uiFont; font.pixelSize: Math.round(11 * st.k)
        color: "#2a241b"
      }
      Row {
        spacing: 3
        Repeater {
          model: st.count
          Rectangle {
            required property int index
            width: Math.round(10 * st.k); height: width; radius: width / 2
            color: index < st.progress ? "#d0457a" : "transparent"
            border.width: 1; border.color: "#d0457a"
          }
        }
      }
    }
  }

  Canvas {
    id: art
    visible: st.kind === "doodle" && st.doodleRows !== null
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (!st.doodleRows) return
      var p = st.pet.pal
      Sprites.drawGrid(ctx, st.doodleRows, p, st.doodlePx, false)
    }
  }
  Image {
    visible: st.userImage
    anchors.fill: parent
    fillMode: Image.PreserveAspectFit
    smooth: false
    source: st.userImage && st.shown ? "file://" + st.pet.home + "/.config/desktop-pet/skills/" + st.image : ""
  }
}
