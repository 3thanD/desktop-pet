import QtQuick
import Quickshell
import Quickshell.Wayland

// Skill effects overlay: trail marks, a falling glyph that shatters into
// pixels, a drawn screen-shake and a screen tint. Like the eaten-letter overlay
// it stays mapped at 1x1 while idle (so it maps before, and stacks below, the
// pet window) and only covers the pet's monitor while an effect is on screen.
// It never takes input (empty mask) and every timer stops when idle:
// marks fade in ~3 fps steps, physics runs at 15 fps for a second or two.
PanelWindow {
  id: fx

  required property var pet
  signal glyphDone(int g)

  property var marks: []               // {kind, x, y, color, born, fade, s}
  property real clock: Date.now()
  readonly property bool active: marks.length > 0 || glyphOn || shardsOn || shaking || tinting
  readonly property real k: Math.max(0.5, pet.k)

  visible: pet.petScreen !== null
  screen: pet.petScreen
  anchors { top: true; left: true }
  implicitWidth: active ? pet.screenW : 1
  implicitHeight: active ? pet.screenH : 1
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-pet-fx"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}

  function clear() {
    marks = []
    glyphOn = false; shardsOn = false; physTimer.stop()
    shaking = false; jx = 0; jy = 0; pet.shakeX = 0; pet.shakeY = 0
    tinting = false
    if (glyphG >= 0) { var g = glyphG; glyphG = -1; glyphDone(g) }
  }

  // ------------------------------------------------------------ trail marks
  function addMark(kind, x, y, color, fade) {
    var list = marks.slice(-79)
    list.push({ kind: kind, x: x, y: y, color: String(color), born: Date.now(), fade: fade * 1000,
                s: Math.round((7 + Math.random() * 4) * k) })
    clock = Date.now()
    marks = list
  }
  Timer {
    interval: 330; repeat: true
    running: fx.marks.length > 0
    onTriggered: {
      var t = Date.now()
      fx.clock = t
      var keep = fx.marks.filter(function (m) { return t - m.born < m.fade })
      if (keep.length !== fx.marks.length) fx.marks = keep
    }
  }
  Repeater {
    model: fx.active ? fx.marks : []
    delegate: Item {
      required property var modelData
      readonly property real age: Math.max(0, (fx.clock - modelData.born) / modelData.fade)
      readonly property int s: modelData.s
      readonly property color mc: modelData.color
      x: modelData.x - s / 2
      y: modelData.y - s / 2
      width: s; height: s
      opacity: age < 0.5 ? 0.9 : Math.max(0, 0.9 * (1 - (age - 0.5) / 0.5))
      // drips: a glossy blob with a slowly lengthening drip and a highlight
      Rectangle {
        visible: modelData.kind === "drips"
        width: parent.s; height: parent.s * 0.8; radius: height / 2
        color: modelData.color
        border.width: Math.max(1, Math.round(fx.k)); border.color: Qt.darker(modelData.color, 1.5)
        Rectangle {
          x: parent.width * 0.42; y: parent.height * 0.6
          width: Math.max(2, parent.width * 0.26); height: parent.height * (0.5 + Math.min(1, age * 2) * 0.9)
          radius: width / 2; color: modelData.color
        }
        Rectangle { x: parent.width * 0.2; y: parent.height * 0.18; width: Math.max(2, parent.width * 0.24); height: width
                    radius: width / 2; color: "#ffffff"; opacity: 0.75 }
      }
      Item {
        visible: modelData.kind === "sparkles"
        anchors.fill: parent
        Rectangle { x: parent.width / 2 - width / 2; width: Math.max(2, parent.s / 4); height: parent.s; color: modelData.color }
        Rectangle { y: parent.height / 2 - height / 2; height: Math.max(2, parent.s / 4); width: parent.s; color: modelData.color }
      }
      Rectangle { visible: modelData.kind === "footprints"; width: parent.s / 3; height: parent.s / 2; radius: width / 2; color: parent.mc }
      Rectangle { visible: modelData.kind === "footprints"; x: parent.s * 0.6; y: parent.s * 0.3; width: parent.s / 3; height: parent.s / 2; radius: width / 2; color: parent.mc }
      Text {
        visible: modelData.kind === "hearts"
        anchors.centerIn: parent
        text: "♥"; color: modelData.color
        font.pixelSize: parent.s * 1.4
      }
    }
  }

  // ------------------------------------------------------------ falling glyph + shatter
  property bool glyphOn: false
  property int glyphG: -1
  property string gText: ""
  property string gFont: "monospace"
  property real gPx: 14
  property color gColor: "white"
  property real gx: 0
  property real gy: 0
  property real gvx: 0
  property real gvy: 0
  property real grot: 0
  property real gvr: 0
  property bool gShatter: true
  property real gFadeT: 0
  property bool shardsOn: false
  property real shardT: 0
  property var shards: []
  readonly property real grav: 0.9 * Math.max(0.75, k)

  function dropGlyph(text, x, y, font, px, color, shatter, dir, g) {
    if (glyphG >= 0) { var old = glyphG; glyphG = -1; glyphDone(old) }
    gText = text; gFont = font || "monospace"; gPx = px || 14; gColor = color
    gx = x; gy = y; gvx = (dir < 0 ? -1 : 1) * (2 + Math.random() * 3) * k; gvy = -(3 + Math.random() * 3) * k
    grot = 0; gvr = (Math.random() < 0.5 ? -1 : 1) * (8 + Math.random() * 10)
    gShatter = shatter; gFadeT = 0
    glyphG = g; glyphOn = true; shardsOn = false
    physTimer.restart()
  }
  function shatter() {
    glyphOn = false
    var list = [], n = 16, cols = [String(gColor), String(pet.tc.accent), String(pet.tc.yellow)]
    for (var i = 0; i < n; i++)
      list.push({ x: gx + Math.random() * gPx * 0.6, y: gy + Math.random() * gPx * 0.8,
                  vx: (Math.random() - 0.5) * 9 * k, vy: -(2 + Math.random() * 7) * k,
                  s: Math.max(2, Math.round((2 + Math.random() * 2) * k)), c: cols[i % 3] })
    shards = list; shardT = 0; shardsOn = true
  }
  Timer {
    id: physTimer
    interval: 66; repeat: true
    onTriggered: fx.physStep()
  }
  function physStep() {
    var H = pet.screenH, W = pet.screenW
    if (glyphOn) {
      if (gFadeT > 0) {
        gFadeT += 0.15
        if (gFadeT >= 1) { glyphOn = false; finishGlyph() }
      } else {
        gvy += grav; gx += gvx; gy += gvy; grot += gvr
        if (gx < 0) { gx = 0; gvx = -gvx * 0.6 }
        if (gx > W - gPx) { gx = W - gPx; gvx = -gvx * 0.6 }
        if (gy >= H - gPx * 1.3) {
          gy = H - gPx * 1.3
          if (gShatter) shatter(); else gFadeT = 0.01
        }
      }
    }
    if (shardsOn) {
      shardT += 1
      if (shardT > 16) { shardsOn = false; shards = []; finishGlyph() }
    }
    if (shaking) {
      if (Date.now() > shakeUntil) { shaking = false; jx = 0; jy = 0 }
      else { var a = shakeAmp * k; jx = Math.round((Math.random() - 0.5) * 2 * a); jy = Math.round((Math.random() - 0.5) * 2 * a) }
      pet.shakeX = jx; pet.shakeY = jy
      shakeT = 1 - Math.max(0, shakeUntil - Date.now()) / shakeDur
    }
    if (!glyphOn && !shardsOn && !shaking) physTimer.stop()
  }
  function finishGlyph() {
    if (glyphG >= 0) { var g = glyphG; glyphG = -1; glyphDone(g) }
  }
  Text {
    visible: fx.glyphOn
    x: fx.gx; y: fx.gy
    rotation: fx.grot
    text: fx.gText
    color: fx.gColor
    opacity: 1 - fx.gFadeT
    font.family: fx.gFont; font.pixelSize: fx.gPx; font.bold: true
    style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5)
  }
  Repeater {
    model: fx.shardsOn ? fx.shards : []
    delegate: Rectangle {
      required property var modelData
      x: modelData.x + modelData.vx * fx.shardT
      y: Math.min(fx.pet.screenH - height, modelData.y + modelData.vy * fx.shardT + 0.5 * fx.grav * fx.shardT * fx.shardT)
      width: modelData.s; height: modelData.s
      color: modelData.c
      opacity: Math.max(0, 1 - fx.shardT / 16)
    }
  }

  // ------------------------------------------------------------ shake (drawn; no real window moves)
  property bool shaking: false
  property real shakeUntil: 0
  property real shakeDur: 1000
  property real shakeAmp: 3
  property real shakeT: 0
  property int jx: 0
  property int jy: 0
  function shake(level, sec) {
    shakeDur = sec * 1000; shakeUntil = Date.now() + shakeDur; shakeAmp = level >= 2 ? 6 : 3; shakeT = 0
    shaking = true
    physTimer.restart()
  }
  Item {
    visible: fx.shaking
    anchors.fill: parent
    readonly property color c: Qt.rgba(fx.pet.cFg.r, fx.pet.cFg.g, fx.pet.cFg.b, 0.22)
    readonly property int t: Math.max(3, Math.round(5 * fx.k))
    Rectangle { x: fx.jx; y: fx.jy; width: parent.width; height: parent.t; color: parent.c }
    Rectangle { x: fx.jx; y: parent.height - parent.t + fx.jy; width: parent.width; height: parent.t; color: parent.c }
    Rectangle { x: fx.jx; y: fx.jy; width: parent.t; height: parent.height; color: parent.c }
    Rectangle { x: parent.width - parent.t + fx.jx; y: fx.jy; width: parent.t; height: parent.height; color: parent.c }
    // comic impact lines in the corners
    Repeater {
      model: 8
      Rectangle {
        required property int index
        readonly property bool onRight: index % 4 >= 2
        readonly property bool onBottom: index >= 4
        width: (18 + (index % 2) * 10) * fx.k; height: Math.max(2, Math.round(3 * fx.k))
        color: fx.pet.cAccent
        opacity: 0.7 * (1 - fx.shakeT)
        rotation: (onRight ? -1 : 1) * (onBottom ? -1 : 1) * (35 + (index % 2) * 15)
        x: (onRight ? parent.width - width - 14 * fx.k : 14 * fx.k) + fx.jx
        y: (onBottom ? parent.height - 30 * fx.k - (index % 2) * 14 * fx.k : 22 * fx.k + (index % 2) * 14 * fx.k) + fx.jy
      }
    }
    // dust shaken loose from the top edge
    Repeater {
      model: 10
      Rectangle {
        required property int index
        width: Math.max(2, Math.round(3 * fx.k)); height: width
        color: fx.pet.cFg
        opacity: 0.5 * (1 - fx.shakeT)
        x: (index + 0.5) / 10 * parent.width + fx.jx
        y: fx.shakeT * fx.shakeT * (60 + (index * 37) % 90) * fx.k
      }
    }
  }

  // ------------------------------------------------------------ screen tint (a soft wash, never blocks input)
  property bool tinting: false
  property color tintColor: "transparent"
  property real tintOp: 0.1
  property real tintStart: 0
  property real tintDur: 2000
  property real tintNow: 0
  function tint(color, op, sec) {
    tintColor = color; tintOp = op; tintDur = sec * 1000; tintStart = Date.now(); tintNow = tintStart
    tinting = true
    tintTimer.restart()
  }
  Timer {
    id: tintTimer
    interval: 125; repeat: true
    onTriggered: {
      fx.tintNow = Date.now()
      if (fx.tintNow - fx.tintStart > fx.tintDur) { fx.tinting = false; stop() }
    }
  }
  Rectangle {
    visible: fx.tinting
    anchors.fill: parent
    color: fx.tintColor
    readonly property real e: (fx.tintNow - fx.tintStart) / fx.tintDur
    opacity: fx.tintOp * Math.min(1, e * 5, (1 - e) * 3)
  }
}
