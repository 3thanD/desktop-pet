import QtQuick
import Quickshell
import Quickshell.Wayland

// The dragon's hoard: a tiny gold-coin pile in the bottom-left corner that
// grows with successful commands. Click-through, drawn once per change, at
// most 36 coins on screen (the count itself is kept in state.json).
// Optional label from config "hoardLabel".
PanelWindow {
  id: h

  required property var pet
  property int coins: 0
  property bool shown: false
  readonly property real k: Math.max(0.5, pet.k)
  readonly property int cw: Math.max(5, Math.round(8 * k))        // coin width
  readonly property int ch: Math.max(3, Math.round(cw * 0.55))
  readonly property int drawn: Math.min(36, coins)
  readonly property int baseN: drawn <= 3 ? drawn : Math.min(8, Math.ceil((Math.sqrt(8 * drawn + 1) - 1) / 2))
  readonly property string label: String(pet.cfg.hoardLabel || "").replace(/[\u0000-\u001f\u007f]/g, "").substring(0, 24)
  readonly property int pileW: Math.max(cw, baseN * (cw - 1) + 2)
  readonly property int pileH: Math.max(ch, baseN * (ch - 1) + ch + 2)

  visible: shown && coins > 0 && pet.petScreen !== null
  screen: pet.petScreen
  anchors { bottom: true; left: true }
  margins { left: Math.round(14 * k) + pet.shakeX; bottom: Math.round(10 * k) - pet.shakeY }
  implicitWidth: Math.max(pileW, labelText.visible ? labelText.implicitWidth : 0) + 4
  implicitHeight: pileH + (labelText.visible ? labelText.implicitHeight + 2 : 0) + 6
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-pet-hoard"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}

  onCoinsChanged: pile.requestPaint()
  onKChanged: pile.requestPaint()

  Text {
    id: labelText
    visible: h.label !== ""
    x: 2
    text: h.label
    textFormat: Text.PlainText
    color: h.pet.tc.yellow
    font.family: h.pet.uiFont; font.pixelSize: Math.max(9, Math.round(10 * h.k)); font.bold: true
    style: Text.Outline; styleColor: h.pet.cBg
  }
  Canvas {
    id: pile
    x: 2
    y: labelText.visible ? labelText.implicitHeight + 2 : 0
    width: h.pileW + 2; height: h.pileH + 4
    renderStrategy: Canvas.Immediate
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var gold = String(h.pet.tc.yellow), dark = Qt.darker(gold, 1.7), shine = Qt.lighter(gold, 1.35)
      var left = h.drawn, row = 0, n = h.baseN
      while (left > 0 && n > 0) {
        var inRow = Math.min(n, left)
        var x0 = (h.pileW - inRow * (h.cw - 1)) / 2
        var y0 = height - 2 - (row + 1) * (h.ch - 1) - 1
        for (var i = 0; i < inRow; i++) {
          var x = Math.round(x0 + i * (h.cw - 1))
          ctx.fillStyle = dark; ctx.fillRect(x, y0, h.cw, h.ch)
          ctx.fillStyle = gold; ctx.fillRect(x + 1, y0, h.cw - 2, h.ch - 1)
          ctx.fillStyle = shine; ctx.fillRect(x + 1, y0, Math.max(1, Math.round(h.cw / 3)), 1)
        }
        left -= inRow; row++; n--
      }
    }
    Connections { target: h.pet; function onTcChanged() { pile.requestPaint() } }
  }
}
