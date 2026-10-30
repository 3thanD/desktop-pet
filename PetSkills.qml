import QtQuick
import Quickshell
import Quickshell.Io
import "Sprites.js" as Sprites

// Pet skills engine. Runs declarative recipes (docs/skill.schema.json) that
// helper.py has already validated, using ONLY the approved actions below; any
// other action is skipped. Every run is capped at 120 s and every effect has
// its own expiry, after which it reverts by itself. revertAll() (heal, off,
// pet switch) undoes everything at once; the two desktop changes (dock icon,
// wallpaper) are journaled by the helper and restored on load / crash too.
//
// Surfaces: a fx window (1x1 when idle, the pet's monitor while an effect is on
// screen, never takes input), up to 3 mini clones, a note and a doodle sticker,
// and the dragon's coin pile. Timers run only while something is happening.
Item {
  id: eng

  required property var pet

  readonly property bool on: pet.cfg.skillsOn !== false
  readonly property int maxRunMs: 120000
  readonly property var motion: ["move", "hop", "path", "animate", "glyph", "clones"]
  readonly property var actions: ["move", "hop", "path", "animate", "bubble", "wait", "particles", "trail", "tint",
                                  "shake", "glyph", "doodle", "sound", "dock", "wallpaper", "clones", "hoard"]

  property var all: []               // [{id, origin, enabled, recipe}] from helper skills-list
  property var pending: []           // [{id, pitch, pet, recipe}]
  property int errorCount: 0
  property var run: null             // {id, recipe, idx, seized, gen, startX, startY, preview}
  readonly property bool busy: run !== null
  property int gen: 0
  property var queued: []            // ids triggered while busy (milestones)
  property real lastAutoStart: 0

  // background effects (each with a hard expiry)
  property var trailFx: null         // {until, fade, kind, color}
  property var wallFx: null          // {until}
  property var dockFx: null          // {until, id, icon, ransom: {count, paid, text}}
  property bool hoardHidden: false   // heal tucks the pile away until the next coin
  readonly property bool dockBusy: dockFx !== null || dockProc.running

  // ------------------------------------------------------------ helpers
  function now() { return Date.now() }
  function num(v, lo, hi, def) { var n = Number(v); if (!(n === n)) n = def; return Math.max(lo, Math.min(hi, n)) }
  function rnd(a, b) { return a + Math.random() * (b - a) }
  function alive(g) { return run !== null && run.gen === g }
  function dayKey() { var d = new Date(); return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() }

  function colorOf(role) {
    var r = String(role || "accent"), tc = pet.tc
    if (Sprites.isHex(r)) return r
    if (r === "body") return pet.pal.b
    var c = tc[r] || tc.accent
    if (pet.cfg.color === "complement" && (r === "accent" || r === "foreground"))
      c = Sprites.ensureContrast(Sprites.complementOf(c, tc.accent), tc.background, 3)
    return c
  }
  function fmt(text) {
    var icon = dockFx ? String(dockFx.id || "icon") : "icon"
    return String(text || "").replace(/\{name\}/g, pet.displayName).replace(/\{icon\}/g, icon)
  }

  function enabled(s) {
    var m = pet.cfg.skills || {}
    if (m[s.id] !== undefined) return m[s.id] === true
    return s.origin === "builtin"
  }
  function forPet(p) {
    return all.filter(function (s) { return s.recipe.pet === p || s.recipe.pet === "any" })
  }
  function byId(id, withPending) {
    for (var i = 0; i < all.length; i++) if (all[i].id === id) return all[i]
    if (withPending) for (i = 0; i < pending.length; i++) if (pending[i].id === id)
      return { id: pending[i].id, origin: "pending", recipe: pending[i].recipe }
    return null
  }
  function isOn(id) { var s = byId(id, false); return !!s && on && enabled(s) }

  // persisted bits live in the pet's state.json (doc.skills)
  function sdoc() {
    var d = pet.storeObj.doc
    if (!d) return { log: {}, hoard: 0, lastPitchTry: 0 }
    if (!d.skills || typeof d.skills !== "object") d.skills = { log: {}, hoard: 0, lastPitchTry: now() - 20 * 3600000 }
    if (!d.skills.log) d.skills.log = {}
    if (typeof d.skills.hoard !== "number") d.skills.hoard = 0
    return d.skills
  }
  property int hoardCoins: 0
  function syncFromStore() { hoardCoins = sdoc().hoard }

  // ------------------------------------------------------------ loading
  Process {
    id: listProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: eng.onList(text) }
  }
  function reload() { if (!listProc.running) pet.runHelper(listProc, ["skills-list"]) }
  function onList(raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    if (!r || !r.ok) return
    // defense in depth: drop anything with an action this engine doesn't know
    var ok = function (rec) { return rec && rec.steps && rec.steps.every(function (s) { return eng.actions.indexOf(s.action) >= 0 }) }
    all = (r.skills || []).filter(function (s) { return ok(s.recipe) })
    pending = (r.pending || []).filter(function (p) { return ok(p.recipe) })
    errorCount = (r.errors || []).length
  }
  Timer { interval: 600000; running: true; repeat: true; onTriggered: eng.reload() }
  Component.onCompleted: reload()

  // ------------------------------------------------------------ rate limits + triggers
  function canRun(s, t, sleepOk) {
    if (!on || !enabled(s) || pet.egg || pet.menuOpen || (pet.sleeping && !sleepOk)) return false
    var r = s.recipe, L = sdoc().log[s.id] || {}
    if (L.last && t - L.last < num(r.cooldown, 1, 1440, 30) * 60000) return false
    if (r.maxPerDay && L.day === dayKey() && (L.n || 0) >= r.maxPerDay) return false
    return gatesOk(r)
  }
  function gatesOk(r) {
    for (var i = 0; i < r.steps.length; i++) {
      var a = r.steps[i]
      if (a.action === "glyph" && a.source === "terminal" && !pet.cfg.eat) return false
      if (a.action === "dock" && (!pet.cfg.goblinSteal || pet.heist || dockBusy)) return false
      if (a.action === "wallpaper" && (wallFx || wallProc.running)) return false
    }
    return true
  }
  function logRun(id) {
    var d = sdoc(), L = d.log[id] || {}, day = dayKey()
    if (L.day !== day) { L.day = day; L.n = 0 }
    L.n = (L.n || 0) + 1; L.last = now()
    d.log[id] = L
    pet.saveSoon()
  }
  function seizes(r) { return r.steps.some(function (s) { return eng.motion.indexOf(s.action) >= 0 }) }
  function perTick(chance) { return 1 - Math.pow(1 - num(chance, 0, 1, 0.02), 3 / 60) }   // think() runs every 3 s

  // called from PetCore.think() while the pet is idle
  function tick() {
    if (!on || busy) return
    var t = now()
    tickPitch(t)
    if (t - lastAutoStart < 90000) return
    var list = forPet(pet.pet)
    for (var i = 0; i < list.length; i++) {
      var s = list[i], tr = s.recipe.trigger, ok = false
      if (tr.on === "idle") ok = true
      else if (tr.on === "happy") ok = pet.happiness >= num(tr.min, 0, 100, 95)
      else if (tr.on === "neglected") ok = t - pet.lastPetAt >= num(tr.min, 1, 1440, 60) * 60000
      if (!ok || !canRun(s, t) || Math.random() >= perTick(tr.chance)) continue
      if (start(s, false)) { lastAutoStart = t; return }
    }
  }
  function fireEvent(kind, extra) {
    if (!on) return
    var t = now(), list = forPet(pet.pet)
    for (var i = 0; i < list.length; i++) {
      var s = list[i], tr = s.recipe.trigger
      // a sleeping dragon still counts its coins (recipes that don't move the pet)
      if (tr.on !== kind || !canRun(s, t, kind === "command-ok" && !seizes(s.recipe))) continue
      if (kind === "milestone" && extra % Math.max(1, Math.round(num(tr.min, 1, 1440, 10))) !== 0) continue
      if (Math.random() >= num(tr.chance, 0, 1, 1)) continue
      if (kind === "walk" && seizes(s.recipe)) continue      // the pet is busy walking
      if (busy) { if (kind === "milestone" && queued.indexOf(s.id) < 0) queued = queued.concat([s.id]); continue }
      if (start(s, false)) return
    }
  }
  function onWalk() { fireEvent("walk") }
  function onCommandOk() { if (!pet.egg) fireEvent("command-ok") }
  function onPetted() {
    if (dockFx && dockFx.ransom) {
      var d = dockFx
      d.ransom.paid++
      dockFx = d; dockFxChanged()
      noteWin.progress = d.ransom.paid
      if (d.ransom.paid >= d.ransom.count) { returnDock("paid"); return true }
      pet.bubble(d.ransom.count - d.ransom.paid + " more and you get it back. Heh.")
      return true
    }
    fireEvent("petted")
    return false
  }

  // ------------------------------------------------------------ running
  function start(s, preview) {
    if (busy || !s || !s.recipe) return false
    var r = s.recipe, seize = seizes(r)
    if (seize) {
      if (pet.egg) return false
      if (pet.sleeping) pet.wakeUp(false)
      if (pet.menuOpen) return false
      pet.resetActivity()
    }
    run = { id: s.id, recipe: r, idx: -1, seized: seize, gen: ++gen, startX: pet.posX, startY: pet.posY, preview: !!preview }
    if (seize) pet.mode = "skill"
    if (!preview) logRun(s.id)
    hardCap.restart()
    next()
    return true
  }
  // preview / CLI run: ignores enabled, cooldown and limits (you asked for it)
  function runNow(id) {
    var s = byId(id, true)
    if (!s) return "no skill " + id
    if (pet.egg) return "still an egg"
    if (s.recipe.pet !== "any" && s.recipe.pet !== pet.pet) return "that is a " + s.recipe.pet + " skill; the current pet is the " + pet.pet
    if (busy) abort("replaced")
    if (!gatesOk(s.recipe)) return "blocked right now (eat/goblin-steal off, or a dock/wallpaper effect is already on)"
    return start(s, true) ? "ok" : "busy"
  }

  function next() {
    if (!run) return
    if (run.seized && pet.mode !== "skill") { finish("interrupted"); return }
    run.idx++
    if (run.idx >= run.recipe.steps.length) { finish("done"); return }
    exec(run.recipe.steps[run.idx], run.gen)
  }
  Timer {
    id: stepTimer
    property int g: -1
    onTriggered: if (eng.alive(g)) eng.next()
  }
  function later(ms, g) { stepTimer.g = g; stepTimer.interval = Math.max(1, ms); stepTimer.restart() }
  Timer { id: hardCap; interval: eng.maxRunMs; onTriggered: eng.abort("time limit") }

  function finish(why) {
    if (!run) return
    var wasSeized = run.seized
    run = null
    hardCap.stop(); stepTimer.stop(); animTimer.stop(); hopTimer.stop()
    stopFollow()
    glyphStep = null
    pet.fxX = 0; pet.squash = 1; pet.speedMul = 1
    if (wasSeized) {
      pet.mouthOpen = false; pet.hopY = 0; pet.blink = false
      if (pet.mode === "skill" || (pet.mode === "walk" && pet.task === "skill")) pet.resetActivity()
      pet.requestPaint()
    }
    if (queued.length) {
      var q = queued.slice(), id = q.shift()
      queued = q
      Qt.callLater(function () { var s = eng.byId(id, false); if (s && eng.canRun(s, eng.now())) eng.start(s, false) })
    }
  }
  function abort(why) {
    if (clonesActive) endClones(true)
    finish(why)
  }

  function exec(st, g) {
    var a = st.action
    if (actions.indexOf(a) < 0) { later(1, g); return }   // unknown: skipped
    if (a === "bubble") { pet.bubble(fmt(st.text).substring(0, 100)); later(400, g) }
    else if (a === "wait") later(num(st.duration, 0.1, 30, 1) * 1000, g)
    else if (a === "particles") { pet.fxBurst(String(st.kind), Math.round(num(st.count, 1, 24, 8)), colorOf(st.color || "accent")); later(350, g) }
    else if (a === "sound") { if (pet.cfg.skillSound === true && !soundProc.running) pet.runHelper(soundProc, ["sound", String(st.name)]); later(30, g) }
    else if (a === "trail") { startTrail(st); later(10, g) }
    else if (a === "tint") {
      var dur = num(st.duration, 0.5, 10, 2), op = num(st.opacity, 0.02, 0.25, 0.12)
      if (st.area === "screen") fx.tint(colorOf(st.color), op, dur); else pet.tintPet(colorOf(st.color), op, dur)
      later(10, g)
    }
    else if (a === "shake") { var sd = num(st.duration, 0.2, 3, 1); fx.shake(st.intensity === "medium" ? 2 : 1, sd); later(sd * 1000, g) }
    else if (a === "doodle") { doodleWin.showDoodle(String(st.image), String(st.where || "pet"), num(st.duration, 1, 60, 5)); later(250, g) }
    else if (a === "hoard") { addCoins(Math.round(num(st.add, 1, 5, 1))); later(120, g) }
    else if (a === "hop") hop(Math.round(num(st.count, 1, 8, 2)), num(st.height, 2, 30, 12), g)
    else if (a === "animate") animate(String(st.frames), num(st.duration, 0.2, 10, 1), g)
    else if (a === "move") doMove(st, g)
    else if (a === "path") doPath(st, g)
    else if (a === "glyph") doGlyph(st, g)
    else if (a === "dock") doDock(st, g)
    else if (a === "wallpaper") doWall(st, g)
    else if (a === "clones") doClones(st, g)
    else later(1, g)
  }

  // ------------------------------------------------------------ hop / animate
  property int hopLeft: 0
  property real hopH: 12
  Timer {
    id: hopTimer
    property int g: -1
    interval: 140; repeat: true
    onTriggered: {
      pet.hopY = (eng.hopLeft % 2) ? 0 : -eng.hopH * pet.k
      if (--eng.hopLeft <= 0) { stop(); pet.hopY = 0; if (eng.alive(g)) eng.next() }
    }
  }
  function hop(n, h, g) { hopLeft = n * 2; hopH = h; hopTimer.g = g; hopTimer.restart() }

  property string animKind: ""
  property real animEnd: 0
  property int animN: 0
  Timer {
    id: animTimer
    property int g: -1
    interval: 90; repeat: true
    onTriggered: eng.animStep(g)
  }
  function animate(kind, dur, g) {
    animKind = kind; animEnd = now() + dur * 1000; animN = 0
    animTimer.g = g; animTimer.restart()
  }
  function animStep(g) {
    var n = ++animN, k = pet.k
    if (now() >= animEnd) {
      animTimer.stop()
      pet.fxX = 0; pet.squash = 1; pet.hopY = 0; pet.blink = false; pet.mouthOpen = false
      pet.requestPaint()
      if (alive(g)) next()
      return
    }
    if (animKind === "bounce") pet.hopY = (n % 4 < 2) ? -8 * k : 0
    else if (animKind === "spin") { if (n % 2 === 0) pet.dir = -pet.dir }
    else if (animKind === "wiggle") pet.fxX = (n % 2 ? 3 : -3) * Math.max(1, k)
    else if (animKind === "squash") pet.squash = n % 4 < 2 ? 0.82 : 1.08
    else if (animKind === "blink") { pet.blink = n % 6 < 2; pet.requestPaint() }
    else if (animKind === "chomp") { if (n % 2 === 0) { pet.mouthOpen = !pet.mouthOpen; pet.requestPaint() } }
    else if (animKind === "sleepy") { if (n === 1) { pet.blink = true; pet.requestPaint() } }
    else if (animKind === "swat") {
      pet.fxX = (n % 3 === 1 ? 6 : 0) * Math.max(1, k)
      if (n % 3 === 1) { pet.frame = pet.frame ? 0 : 1; pet.requestPaint() }
    }
  }

  // ------------------------------------------------------------ move / path
  function walkThen(x, y, g, cb) {
    pet.walkTo(x, y, "skill", function () {
      if (!eng.alive(g)) return
      pet.mode = "skill"
      cb()
    })
  }
  function doMove(st, g) {
    pet.speedMul = st.speed === "slow" ? 0.6 : (st.speed === "fast" ? 1.6 : 1)
    var to = String(st.to), W = pet.screenW, H = pet.screenH, x = pet.posX, y = pet.posY
    if (to === "cursor") {
      var f = num(st.follow, 0, 10, 0)
      if (f > 0) { startFollow(f, g); return }
      cursorOnce.g = g
      if (!pet.runHelper(cursorOnce, ["cursor"])) later(1, g)
      return
    }
    if (to === "random") { x += rnd(-350, 350); y += rnd(-180, 180) }
    else if (to === "center") { x = W / 2 - pet.winW / 2; y = H / 2 - pet.winH / 2 }
    else if (to === "home") { x = run.startX; y = run.startY }
    else if (to === "bottom") { x = W / 2 - pet.winW / 2 + rnd(-140, 140); y = pet.maxY }
    else if (to === "top") y = 0
    else if (to === "left") x = 0
    else if (to === "right") x = pet.maxX
    walkThen(x, y, g, function () { eng.next() })
  }
  Process {
    id: cursorOnce
    property int g: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = null
        try { r = JSON.parse(text) } catch (e) {}
        if (!eng.alive(cursorOnce.g)) return
        if (!r || !r.ok) { eng.next(); return }
        eng.walkThen(r.x + 16 - pet.sprLeft, r.y - pet.sprTop - pet.spr / 2, cursorOnce.g, function () { eng.next() })
      }
    }
  }

  // cursor sit: follow the pointer for a few seconds with an EMPTY input mask
  property int followG: -1
  property real followTX: 0
  property real followTY: 0
  property bool following: false
  property real followUntil: 0
  Process {
    id: cursorStream
    stdout: SplitParser { onRead: function (line) { eng.onCursorLine(line) } }
    onExited: if (eng.following) eng.endFollow()
  }
  Timer {
    id: followTimer
    interval: 66; repeat: true
    onTriggered: {
      var dx = eng.followTX - pet.posX, dy = eng.followTY - pet.posY
      if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
        pet.posX += dx * 0.3; pet.posY += dy * 0.3
        if (Math.abs(dx) > 3) pet.dir = dx > 0 ? 1 : -1
      }
      if (eng.now() > eng.followUntil + 1500) eng.endFollow()
    }
  }
  function startFollow(sec, g) {
    following = true; followG = g; followUntil = now() + sec * 1000
    followTX = pet.posX; followTY = pet.posY
    pet.clickThrough = true
    cursorStream.command = ["python3", "-I", pet.helper, "cursor-stream", String(sec)]
    cursorStream.running = true
    followTimer.restart()
  }
  function onCursorLine(line) {
    var r = null
    try { r = JSON.parse(line) } catch (e) { return }
    if (!r || typeof r.x !== "number" || (r.monitor && pet.screenName && r.monitor !== pet.screenName)) return
    // sit just beside the pointer (right, or left near the edge), never under it
    var gap = 18 * Math.max(1, pet.k)
    var right = r.x + gap + pet.spr < pet.screenW
    var sx = right ? r.x + gap : r.x - gap - pet.spr
    followTX = pet.clamp(sx - pet.sprLeft, 0, pet.maxX)
    followTY = pet.clamp(r.y - pet.sprTop - pet.spr * 0.55, 0, pet.maxY)
  }
  function stopFollow() {
    if (!following) return
    following = false
    followTimer.stop()
    if (cursorStream.running) cursorStream.signal(15)
    pet.clickThrough = false
    pet.saveSoon()
  }
  function endFollow() {
    var g = followG
    stopFollow()
    if (alive(g)) next()
  }

  property var pathPts: []
  function doPath(st, g) {
    var size = (st.size === "small" ? 50 : (st.size === "large" ? 170 : 100)) * Math.max(0.7, pet.k)
    var laps = Math.round(num(st.laps, 1, 3, 1)), cx = pet.posX, cy = pet.posY, pts = [], i, t
    var shape = String(st.shape)
    for (var l = 0; l < laps; l++) {
      if (shape === "circle") for (i = 1; i <= 12; i++) { t = i / 12 * Math.PI * 2; pts.push([cx + Math.sin(t) * size, cy - (1 - Math.cos(t)) * size * 0.6]) }
      else if (shape === "zigzag") { for (i = 1; i <= 6; i++) pts.push([cx + i * size / 3, cy + (i % 2 ? -1 : 1) * size * 0.3]); pts.push([cx, cy]) }
      else if (shape === "figure8") for (i = 1; i <= 16; i++) { t = i / 16 * Math.PI * 2; pts.push([cx + Math.sin(t) * size, cy + Math.sin(2 * t) * size * 0.35]) }
      else if (shape === "square") pts = pts.concat([[cx + size, cy], [cx + size, cy - size * 0.7], [cx, cy - size * 0.7], [cx, cy]])
      else for (i = 1; i <= 16; i++) {   // heart
        t = i / 16 * Math.PI * 2
        var hx = 16 * Math.pow(Math.sin(t), 3), hy = 13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t)
        pts.push([cx + hx / 16 * size, cy - (hy - 5) / 17 * size * 0.8])
      }
    }
    pet.speedMul = 1.3
    pathPts = pts
    pathStep(g)
  }
  function pathStep(g) {
    if (!alive(g)) return
    if (pathPts.length === 0) { pet.speedMul = 1; next(); return }
    var p = pathPts[0]
    pathPts = pathPts.slice(1)
    walkThen(p[0], p[1], g, function () { eng.pathStep(g) })
  }

  // ------------------------------------------------------------ trail
  function startTrail(st) {
    trailFx = { until: now() + num(st.duration, 1, 120, 10) * 1000, fade: num(st.fade, 2, 20, 8),
                kind: String(st.kind), color: colorOf(st.color || "body") }
    lastMarkX = -9999; lastMarkY = -9999
  }
  property real lastMarkX: -9999
  property real lastMarkY: -9999
  Timer {
    id: trailTimer
    interval: 260; repeat: true
    running: eng.trailFx !== null
    onTriggered: {
      var t = eng.trailFx
      if (!t || eng.now() > t.until) { eng.trailFx = null; return }
      if (pet.hideSprite || pet.mode === "sleep") return
      var fx0 = pet.posX + pet.sprLeft + pet.spr / 2, fy0 = pet.posY + pet.sprTop + pet.spr - pet.floorPad
      var dx = fx0 - eng.lastMarkX, dy = fy0 - eng.lastMarkY
      if (dx * dx + dy * dy < Math.pow(16 * Math.max(0.6, pet.k), 2)) return
      eng.lastMarkX = fx0; eng.lastMarkY = fy0
      fx.addMark(t.kind, fx0 + eng.rnd(-4, 4) * pet.k, fy0 - eng.rnd(0, 4) * pet.k, t.color, t.fade)
    }
  }

  // ------------------------------------------------------------ glyph (knock-off)
  property var glyphStep: null
  function doGlyph(st, g) {
    var shatter = st.shatter !== false
    if (st.source === "text") {
      var mp = pet.mouthPx()
      fx.dropGlyph(String(st.text || "!").substring(0, 3), pet.posX + pet.sprLeft + mp[0], pet.posY + pet.sprTop + mp[1] - 14 * pet.k,
                   pet.uiFont, Math.round(14 * Math.max(0.8, pet.k)), colorOf("foreground"), shatter, pet.dir, g)
      return
    }
    if (!pet.cfg.eat) { later(1, g); return }
    glyphStep = { g: g, shatter: shatter }
    if (!pet.skillScan()) { glyphStep = null; later(1, g) }
  }
  // PetCore hands us its scan result (purpose "skill")
  function onScan(r) {
    var gs = glyphStep
    glyphStep = null
    if (!gs || !alive(gs.g)) return
    if (!r || !r.ok || !r.runs || !r.runs.length) { pet.bubble("Nothing worth swatting..."); later(300, gs.g); return }
    var tgt = pet.adoptTarget(r)
    var taken = {}
    for (var i = 0; i < pet.patches.length; i++) if (pet.patches[i].addr === tgt.address) taken[pet.patches[i].row + ":" + pet.patches[i].col] = true
    for (i = 0; i < r.runs.length; i++) {
      var run0 = r.runs[i], col = run0.col + Math.floor(Math.random() * run0.text.length)
      if (taken[run0.row + ":" + col]) continue
      var ch = run0.text[col - run0.col]
      var cellX = tgt.x + tgt.ox + col * tgt.cw, cellY = tgt.y + tgt.oy + run0.row * tgt.ch
      // stand just left of the letter so the paw reaches it
      var wx = cellX - pet.sprLeft - pet.artX - Sprites.GRID_W * pet.cellPx * 0.78
      var wy = cellY + tgt.ch / 2 - pet.sprTop - pet.spr * 0.62
      if (wx < 0 || wy < 0 || wx > pet.maxX || wy > pet.maxY) continue
      walkThen(wx, wy, gs.g, function () { eng.swat(gs, col, run0.row, ch, cellX, cellY, tgt) })
      return
    }
    pet.bubble("Hmph. Nothing in reach.")
    later(300, gs.g)
  }
  function swat(gs, col, row, ch, cellX, cellY, tgt) {
    pet.dir = 1
    animate("swat", 0.45, -1)          // visual only; the step continues below
    swatTimer.args = [gs, col, row, ch, cellX, cellY, tgt]
    swatTimer.restart()
  }
  Timer {
    id: swatTimer
    property var args: null
    interval: 320
    onTriggered: {
      var a = args
      if (!a || !eng.alive(a[0].g)) return
      pet.addPatch(a[1], a[2], "eat", a[3])
      fx.dropGlyph(a[3], a[4], a[5], a[6].font, a[6].fontPx, eng.colorOf("foreground"), a[0].shatter, 1, a[0].g)
    }
  }
  function onGlyphDone(g) { if (alive(g)) next() }

  // ------------------------------------------------------------ dock (through the heist journal)
  Process {
    id: dockProc
    property string purpose: ""
    property var st: null
    property int g: -1
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: eng.onDockResult(dockProc.purpose, text) }
  }
  function doDock(st, g) {
    if (!pet.cfg.goblinSteal || pet.heist || dockFx || dockProc.running) { later(1, g); return }
    dockProc.purpose = "steal"; dockProc.st = st; dockProc.g = g
    if (!pet.runHelper(dockProc, ["dock-steal", st.mode === "move" ? "move" : "hide"])) later(1, g)
  }
  function onDockResult(purpose, raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    if (purpose === "restore") { if (pendingDockRestore) { pendingDockRestore = false; restoreDock() } return }
    var st = dockProc.st, g = dockProc.g
    if (r && r.ok) {
      var rs = st.ransom ? { count: Math.round(num(st.ransom.count, 1, 10, 3)), paid: 0,
                             text: String(st.ransom.text || "Pet {name} {count} times to get your icon back!") } : null
      dockFx = { until: now() + num(st.duration, 5, 120, 60) * 1000, id: r.id || "icon", icon: r.icon || "", applied: !!r.applied, ransom: rs }
      if (rs) noteWin.showNote(fmt(rs.text).replace(/\{count\}/g, rs.count), r.icon || "", rs.count, Math.round(num(st.duration, 5, 120, 60)))
      pet.happiness = pet.clamp(pet.happiness + 5, 0, 100)
    }
    if (alive(g)) later(200, g)
  }
  property bool pendingDockRestore: false
  function restoreDock() {
    if (dockProc.running) { pendingDockRestore = true; return }
    dockProc.purpose = "restore"
    pet.runHelper(dockProc, ["dock-restore"])
  }
  function returnDock(why) {
    if (!dockFx) return
    dockFx = null
    noteWin.hideNote()
    restoreDock()
    if (why === "paid") { pet.heartBurst(); pet.bubble("Fine, FINE. A deal's a deal. Icon's back!") }
    else if (why === "time") pet.bubble("Bah, you can have your icon back.")
  }

  // ------------------------------------------------------------ wallpaper (journaled by the helper)
  Process {
    id: wallProc
    property string purpose: ""
    property int g: -1
    property real secs: 20
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: eng.onWall(wallProc.purpose, text) }
  }
  function doWall(st, g) {
    if (wallFx || wallProc.running) { later(1, g); return }
    var tc = pet.tc, dpr = (pet.petScreen && pet.petScreen.devicePixelRatio) ? pet.petScreen.devicePixelRatio : 1
    var colors = { background: String(tc.background), foreground: String(tc.foreground), green: String(tc.bright_green || tc.green),
                   yellow: String(tc.yellow), accent: String(colorOf("accent")), red: String(tc.red), orange: String(tc.orange) }
    var secs = num(st.duration, 5, 120, 20)
    wallProc.purpose = "swap"; wallProc.g = g; wallProc.secs = secs
    if (!pet.runHelper(wallProc, ["wall-swap", String(st.doodle), String(Math.round(pet.screenW * dpr)), String(Math.round(pet.screenH * dpr)),
                                  JSON.stringify(colors), String(secs)])) later(1, g)
  }
  property bool pendingWallRestore: false
  function onWall(purpose, raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    if (purpose === "swap") {
      if (r && r.applied) wallFx = { until: now() + wallProc.secs * 1000 }
      if (alive(wallProc.g)) later(300, wallProc.g)
    }
    if (pendingWallRestore) { pendingWallRestore = false; restoreWall() }
  }
  function restoreWall() {
    wallFx = null
    if (wallProc.running) { pendingWallRestore = true; return }
    wallProc.purpose = "restore"
    pet.runHelper(wallProc, ["wall-restore"])
  }

  // ------------------------------------------------------------ clones (mitosis)
  property bool clonesActive: false
  property bool merging: false
  property real cloneUntil: 0
  property int cloneG: -1
  readonly property var clones: [clone0, clone1, clone2]
  function doClones(st, g) {
    var n = Math.round(num(st.count, 1, 3, 3))
    var cx = pet.posX + pet.sprLeft + pet.spr / 2, cy = pet.posY + pet.sprTop + pet.spr - pet.floorPad
    pet.hideSprite = true
    for (var i = 0; i < 3; i++) {
      var c = clones[i]
      if (i >= n) { c.active = false; continue }
      var ang = (i / n) * Math.PI * 2 + 0.6
      c.cx = cx; c.cy = cy
      c.tx = pet.clamp(cx + Math.cos(ang) * 110 * Math.max(0.7, pet.k), 30, pet.screenW - 30)
      c.ty = pet.clamp(cy + Math.sin(ang) * 50 * Math.max(0.7, pet.k), 60, pet.screenH - 4)
      c.moving = true; c.dir = c.tx >= cx ? 1 : -1; c.nextAt = 0
      c.active = true
    }
    clonesActive = true; merging = false
    cloneUntil = now() + num(st.duration, 3, 120, 30) * 1000
    cloneG = g
    cloneTimer.restart()
  }
  Timer {
    id: cloneTimer
    interval: 66; repeat: true
    onTriggered: eng.cloneTick()
  }
  function cloneTick() {
    var t = now(), cx = pet.posX + pet.sprLeft + pet.spr / 2, cy = pet.posY + pet.sprTop + pet.spr - pet.floorPad
    if (!merging && t >= cloneUntil) {
      merging = true
      for (var j = 0; j < 3; j++) if (clones[j].active) { clones[j].tx = cx; clones[j].ty = cy; clones[j].moving = true }
    }
    var allHome = true
    for (var i = 0; i < 3; i++) {
      var c = clones[i]
      if (!c.active) continue
      if (c.moving) {
        var dx = c.tx - c.cx, dy = c.ty - c.cy, d = Math.sqrt(dx * dx + dy * dy)
        var sp = (merging ? 6 : 4) * Math.max(0.7, pet.k)
        if (d <= sp) {
          c.cx = c.tx; c.cy = c.ty; c.hop = 0; c.moving = false
          c.nextAt = t + rnd(700, 2600)
        } else {
          c.cx += dx / d * sp; c.cy += dy / d * sp
          c.phase += 0.45
          c.hop = -Math.abs(Math.sin(c.phase)) * 7 * Math.max(0.6, pet.k)
          if (Math.abs(dx) > 2) c.dir = dx > 0 ? 1 : -1
          allHome = false
        }
      } else if (!merging && t > c.nextAt) {
        c.tx = pet.clamp(cx + rnd(-260, 260) * Math.max(0.7, pet.k), 30, pet.screenW - 30)
        c.ty = pet.clamp(cy + rnd(-120, 120) * Math.max(0.7, pet.k), 60, pet.screenH - 4)
        c.moving = true
      }
      if (merging && (c.cx !== cx || c.cy !== cy)) allHome = false
    }
    if (merging && allHome) endClones(false)
  }
  function endClones(quiet) {
    cloneTimer.stop()
    for (var i = 0; i < 3; i++) clones[i].active = false
    clonesActive = false; merging = false
    pet.hideSprite = false
    pet.requestPaint()
    if (!quiet) { pet.sparkle(); pet.heartBurst(); if (alive(cloneG)) later(500, cloneG) }
  }

  // ------------------------------------------------------------ hoard
  function addCoins(n) {
    var d = sdoc(), before = d.hoard
    d.hoard = Math.min(9999, before + n)
    hoardCoins = d.hoard
    hoardHidden = false
    pet.saveSoon()
    for (var c = before + 1; c <= d.hoard; c++) {
      // milestones fire after the current run (roar)
      var list = forPet(pet.pet)
      for (var i = 0; i < list.length; i++) {
        var tr = list[i].recipe.trigger
        if (tr.on === "milestone" && c % Math.max(1, Math.round(num(tr.min, 1, 1440, 10))) === 0) { fireEvent("milestone", c); break }
      }
    }
  }

  // ------------------------------------------------------------ pitching (Claude, at most once a day)
  Process {
    id: pitchProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: eng.onPitch(text) }
  }
  function tickPitch(t) {
    if (!pet.cfg.brain || pet.cfg.chatty === "off" || pitchProc.running || pending.length >= 5) return
    var d = sdoc()
    if (t - (d.lastPitchTry || 0) < 24 * 3600000 || Math.random() > 0.005) return
    d.lastPitchTry = t
    pet.saveSoon()
    var ctx = { pet: pet.pet, name: pet.petName, mood: pet.mood(), stage: pet.stageName,
                happiness: Math.round(pet.happiness), energy: Math.round(pet.energy) }
    pet.runHelper(pitchProc, ["skills-pitch", "--auto", JSON.stringify(ctx)])
  }
  function onPitch(raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    if (!r || !r.ok) return
    pet.bubble((r.pitch || "I have an idea for a new trick!") + "  (desktop-pet skills review)")
    reload()
  }

  // menu actions
  Process {
    id: decideProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: eng.reload() }
  }
  function decide(id, approve) {
    if (decideProc.running) return
    decideProc.command = ["python3", "-I", pet.helper, approve ? "skills-approve" : "skills-reject", id]
    decideProc.running = true
    if (approve) pet.bubble("Yay! I'll practice it!")
  }

  // ------------------------------------------------------------ expiry + revert
  Timer {
    interval: 1000; repeat: true
    running: eng.dockFx !== null || eng.wallFx !== null
    onTriggered: {
      var t = eng.now()
      if (eng.dockFx && t > eng.dockFx.until) eng.returnDock("time")
      if (eng.wallFx && t > eng.wallFx.until) eng.restoreWall()
    }
  }
  Process { id: soundProc }
  Process { id: restoreProc }

  // heal / off / pet switch: everything goes back NOW
  function revertAll() {
    queued = []
    abort("revert")
    if (clonesActive) endClones(true)
    pet.hideSprite = false
    trailFx = null
    fx.clear()
    pet.tintPet("#000000", 0, 0)
    doodleWin.hide()
    noteWin.hideNote()
    dockFx = null
    wallFx = null
    hoardHidden = true
    restoreProc.command = ["python3", "-I", pet.helper, "restore-all"]
    if (!restoreProc.running) restoreProc.running = true
  }

  function statusObj() {
    return { on: on, running: run ? run.id : "", trail: trailFx !== null, wallpaper: wallFx !== null,
             dock: dockFx ? { id: dockFx.id, ransom: dockFx.ransom } : null, clones: clonesActive,
             following: following, fx: fx.active, marks: fx.marks.length, hoard: hoardCoins,
             hoardVisible: hoardWin.visible, pending: pending.length, skills: all.length, errors: errorCount }
  }

  // ------------------------------------------------------------ surfaces
  PetFx { id: fx; pet: eng.pet; onGlyphDone: function (g) { eng.onGlyphDone(g) } }
  PetClone { id: clone0; pet: eng.pet }
  PetClone { id: clone1; pet: eng.pet }
  PetClone { id: clone2; pet: eng.pet }
  PetSticker { id: noteWin; pet: eng.pet; kind: "note" }
  PetSticker { id: doodleWin; pet: eng.pet; kind: "doodle" }
  PetHoard {
    id: hoardWin
    pet: eng.pet
    coins: eng.hoardCoins
    shown: eng.on && eng.hoardCoins > 0 && !eng.hoardHidden && pet.pet === "dragon" && !pet.egg && eng.isOn("hoard")
  }
}
