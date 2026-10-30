import QtQuick
import Quickshell
import Quickshell.Wayland

// Fetch ball: a tiny layer-shell window that only takes input on the ball.
// Grab it and flick it; it flies with simple gravity at 20 fps (only while
// moving), bounces off the monitor edges and rests on the bottom. The pet
// (PetCore) chases it when it lands. Despawns after 60 s without play.
PanelWindow {
  id: ball

  required property var pet
  property bool active: false      // on screen (not carried, not despawned)
  property bool held: false
  property bool toasted: false
  property real bx: 0               // ball centre, monitor-local logical px
  property real by: 0
  property real vx: 0
  property real vy: 0
  property real throwFromX: 0
  property real throwFromY: 0
  readonly property int d: Math.max(10, Math.round(14 * pet.k))
  readonly property int pad: 6
  readonly property real g: 1.6 * Math.max(0.75, pet.k)
  signal landed(real x, real y, real distance)
  signal grabbed()

  function spawn(x, y) {
    bx = x; by = y; vx = (Math.random() - 0.5) * 16; vy = -8
    toasted = false
    active = true
    throwFromX = x; throwFromY = y
    physics.start()
    idle.restart()
  }
  function hide() { active = false; physics.stop() }
  // put the ball down without throwing it (no chase)
  function place(x, y) {
    bx = Math.max(d / 2, Math.min(pet.screenW - d / 2, x)); by = Math.max(d / 2, Math.min(pet.screenH - d / 2, y))
    vx = 0; vy = 0; active = true; physics.stop(); idle.restart()
  }

  visible: active
  screen: pet.petScreen
  anchors { top: true; left: true }
  margins { left: Math.round(bx - d / 2 - pad); top: Math.round(by - d / 2 - pad) }
  implicitWidth: d + 2 * pad
  implicitHeight: d + 2 * pad
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-pet-ball"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region { item: body }

  Rectangle {
    id: body
    x: ball.pad; y: ball.pad
    width: ball.d; height: ball.d
    radius: ball.d / 2
    color: ball.toasted ? "#2b2118" : ball.pet.tc.red
    border.width: Math.max(1, Math.round(ball.d / 8))
    border.color: Qt.darker(color, 1.8)
    Rectangle {   // stripe + shine, so it reads as a ball at every size
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width; height: Math.max(1, Math.round(ball.d / 6))
      color: ball.toasted ? "#4a3a2a" : "#ffffff"; opacity: 0.85
    }
    Rectangle { x: ball.d * 0.22; y: ball.d * 0.18; width: ball.d / 5; height: width; radius: width / 2; color: "#ffffff"; opacity: 0.8 }
  }

  MouseArea {
    anchors.fill: body
    cursorShape: ball.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    property real lx: 0
    property real ly: 0
    property real lt: 0
    property var samples: []
    onPressed: function (m) {
      ball.held = true; physics.stop(); idle.restart()
      lx = m.x; ly = m.y; lt = Date.now(); samples = []
      ball.throwFromX = ball.bx; ball.throwFromY = ball.by
      ball.grabbed()
    }
    onPositionChanged: function (m) {
      if (!ball.held) return
      var t = Date.now(), dx = m.x - lx, dy = m.y - ly
      // the window follows the ball, so local deltas are screen deltas
      ball.bx = Math.max(ball.d / 2, Math.min(ball.pet.screenW - ball.d / 2, ball.bx + dx))
      ball.by = Math.max(ball.d / 2, Math.min(ball.pet.screenH - ball.d / 2, ball.by + dy))
      var s = samples.slice(-5); s.push({ dx: dx, dy: dy, dt: Math.max(1, t - lt) }); samples = s
      lt = t
    }
    onReleased: {
      ball.held = false
      var sx = 0, sy = 0, st = 0
      for (var i = 0; i < samples.length; i++) { sx += samples[i].dx; sy += samples[i].dy; st += samples[i].dt }
      var cap = 45 * Math.max(0.75, ball.pet.k)
      ball.vx = st > 0 ? Math.max(-cap, Math.min(cap, sx / st * 50)) : 0   // px per 50 ms tick
      ball.vy = st > 0 ? Math.max(-cap, Math.min(cap, sy / st * 50)) : 0
      physics.start()
    }
  }

  Timer {
    id: physics
    interval: 50
    repeat: true
    onTriggered: {
      var W = ball.pet.screenW, H = ball.pet.screenH, r = ball.d / 2
      ball.vy += ball.g
      ball.bx += ball.vx; ball.by += ball.vy
      if (ball.bx < r) { ball.bx = r; ball.vx = -ball.vx * 0.7 }
      if (ball.bx > W - r) { ball.bx = W - r; ball.vx = -ball.vx * 0.7 }
      if (ball.by < r) { ball.by = r; ball.vy = -ball.vy * 0.6 }
      if (ball.by > H - r) {
        ball.by = H - r; ball.vy = -ball.vy * 0.55; ball.vx *= 0.85
        if (Math.abs(ball.vy) < 2.5 && Math.abs(ball.vx) < 0.8) {
          ball.vx = 0; ball.vy = 0; stop()
          var dx = ball.bx - ball.throwFromX, dy = ball.by - ball.throwFromY
          ball.landed(ball.bx, ball.by, Math.sqrt(dx * dx + dy * dy))
        }
      }
    }
  }
  Timer { id: idle; interval: 60000; onTriggered: ball.hide() }
  function touch() { idle.restart() }
}
