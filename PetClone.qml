import QtQuick
import Quickshell
import Quickshell.Wayland
import "Sprites.js" as Sprites

// One mini copy of the pet (mitosis). A tiny click-through window that the
// skills engine moves by its margins; it only exists while `active`.
PanelWindow {
  id: clone

  required property var pet
  property bool active: false
  property real cx: 0          // feet centre, monitor-local logical px
  property real cy: 0
  property real tx: 0
  property real ty: 0
  property bool moving: false
  property int dir: 1
  property real hop: 0
  property real phase: 0
  property real nextAt: 0
  property int frame: 0
  readonly property int mpx: Math.max(1, Math.floor(pet.cellPx / 2))
  readonly property int side: Sprites.GRID_W * mpx

  visible: active && pet.petScreen !== null
  screen: pet.petScreen
  anchors { top: true; left: true }
  margins { left: Math.round(Math.max(0, cx - side / 2)); top: Math.round(Math.max(0, cy - side + hop)) }
  implicitWidth: side
  implicitHeight: side
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-pet-clone"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}

  onDirChanged: art.requestPaint()
  onFrameChanged: art.requestPaint()
  onActiveChanged: if (active) art.requestPaint()

  Timer { interval: 550; repeat: true; running: clone.active && !clone.moving; onTriggered: clone.frame = clone.frame ? 0 : 1 }

  Canvas {
    id: art
    width: clone.side; height: clone.side
    y: (clone.pet.pet === "slime" && clone.frame === 1 && !clone.moving) ? clone.mpx : 0
    renderStrategy: Canvas.Immediate
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (!clone.active) return
      var p = clone.pet
      var g = Sprites.buildGrid(p.pet, { frame: clone.frame, blink: false, mouthOpen: false, mood: "happy",
                                         acc: p.acc, band: p.themeInfo.band || "r", stage: p.stage, variant: p.variant })
      Sprites.drawGrid(ctx, g, p.pal, clone.mpx, clone.dir < 0)
    }
    Connections { target: clone.pet; function onPalChanged() { art.requestPaint() } }
  }
}
