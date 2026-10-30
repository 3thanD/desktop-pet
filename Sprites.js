.pragma library

// Pixel-art pets drawn from character grids. Every character is a palette
// role, resolved against the live Omarchy theme in palette().
//   .  transparent     o  outline        b  body       B  body shade
//   h  body highlight  e  eye            w  white      p  blush / tongue
//   m  mouth           y  yellow         r  red        R  dark red
//   O  orange          Q  dark orange    g  green      G  dark green
//   c  cloth (brown)   C  light brown    k  near black a  accent
//   v  cyan            V  light cyan     j  jade       W  wing

var GRID_W = 20
var GRID_H = 20
var SCALE = 4

var PETS = {
  slime: {
    label: "slime",
    rows: [
      "......oooo......",
      "....oohhhboo....",
      "...ohhbbbbbbo...",
      "..ohbbbbbbbbbo..",
      "..obbbbbbbbbbo..",
      ".obbbbbbbbbbbbo.",
      ".obbwebbbbwebbo.",
      ".obbeebbbbeebbo.",
      ".obpbbbbbbbbpbo.",
      ".obbbbbmmbbbbbo.",
      ".oBbbbbbbbbbbBo.",
      "..oBBBBBBBBBBo..",
      "...oooooooooo..."
    ],
    alt: null,           // the slime bobs instead of swapping frames
    bob: true,
    eyes: [[4, 6, 2, 2], [10, 6, 2, 2]],
    mouth: [7, 9, 2],
    headTop: 0, cx: 7.5, neckY: 10, forehead: [7, 3]
  },
  cat: {
    label: "cat",
    rows: [
      ".o...........o..",
      ".oo.........oo..",
      ".obo.......obo..",
      ".obpooooooopbo..",
      ".obbbbbbbbbbbo..",
      "obbbbbbbbbbbbbo.",
      "obbwebbbbbwebbo.",
      "obbeebbbbbeebbo.",
      "obpbbbbpbbbbpbo.",
      "obbbbbmbmbbbbbo.",
      ".obbbbbbbbbbbo..",
      "..obbhhhhhbbo...",
      "..obbhhhhhbbo..o",
      "..obbbbbbbbbobo.",
      "..obbo...obbo...",
      "..oooo...oooo..."
    ],
    alt: { 14: "...obbo.obbo....", 15: "...oooo.oooo...." },
    eyes: [[3, 6, 2, 2], [10, 6, 2, 2]],
    mouth: [6, 9, 3],
    headTop: 3, cx: 7, neckY: 10, forehead: [7, 4]
  },
  dragon: {
    label: "baby dragon",
    rows: [
      "...y.......y....",
      "...oy.....yo....",
      "..obbbbbbbbbo...",
      ".obbbbbbbbbbbo..",
      ".obbwebbbwebbo..",
      ".obbeebbbeebbo..",
      ".obpbbbbbbbpbo..",
      ".obbbbmmmbbbbo..",
      "..oobbbbbbboo...",
      "WWoBbyyyyybBoWW.",
      "WWWobyyyyyboWWW.",
      ".W.obyyyyybo.W..",
      "...obbbbbbbobb..",
      "...obo...obo...."
    ],
    alt: { 8: "W.oobbbbbbboo.W.", 10: "..WobyyyyyboW...", 11: "...obyyyyybo...." },
    eyes: [[4, 4, 2, 2], [9, 4, 2, 2]],
    mouth: [6, 7, 3],
    headTop: 2, cx: 7, neckY: 8, forehead: [7, 3]
  },
  goblin: {
    label: "goblin",
    rows: [
      "......oooo......",
      ".....occcco.....",
      "....occcccco....",
      "oo.obbbbbbbbo.oo",
      "obbobbbbbbbbobbo",
      ".obbbyebbyebbbo.",
      "..obbbbBBbbbbo..",
      "..obbbmmmmbbbo..",
      "...obbbbbbbbo...",
      "..occcccccccco..",
      ".obccccccccccbo.",
      "..occcyyyyccco..",
      "...occcccccco...",
      "...obbo..obbo...",
      "...ooo....ooo..."
    ],
    alt: { 13: "....obbo.obbo...", 14: "....ooo..ooo...." },
    eyes: [[5, 5, 2, 1], [9, 5, 2, 1]],
    mouth: [6, 7, 4],
    headTop: 0, cx: 7.5, neckY: 8, forehead: [7, 3]
  }
}

var PET_NAMES = ["slime", "cat", "dragon", "goblin"]

// ------------------------------------------------------------ accessories

var HATS = {
  crown:    { rows: ["y.y.y", "yyyyy", "yrvry"], overlap: 1 },
  leafhat:  { rows: ["..o..", ".gGg.", "gggGg"], overlap: 1 },
  pumpkin:  { rows: ["..g..", ".OQO.", "OQOQO"], overlap: 1 },
  beanie:   { rows: ["..w..", ".ccc.", "ccccc", "CCCCC"], overlap: 1 },
  mushroom: { rows: ["..rrr..", ".rwrrr.", "rrrrwrr"], overlap: 1 },
  halo:     { rows: [".yyy.", "y...y", ".yyy."], overlap: -1 }
}
var SIDE = {
  flower:    { rows: [".p.", "pyp", ".p.", ".g."] },
  bow:       { rows: ["rr.rr", "rrRrr", "rr.rr"] },
  moonstars: { rows: ["w....", "...yy", "..yy.", "..yy.", "...yy", ".w..."] }
}

var ACCESSORIES = ["shades", "visor", "retroshades", "glow", "crown", "leafhat", "pumpkin",
                   "beanie", "mushroom", "halo", "flower", "bow", "moonstars", "scarf",
                   "headband", "tie", "gem"]

// theme slug -> { acc: [accessories], mono: bool, band: role for headband }
var THEMES = {
  "hackerman":        { acc: ["shades", "glow"] },
  "tokyo-night":      { acc: ["visor"] },
  "everforest":       { acc: ["leafhat"] },
  "nord":             { acc: ["scarf", "snow"] },
  "catppuccin":       { acc: ["crown"] },
  "catppuccin-latte": { acc: ["crown"] },
  "rose-pine":        { acc: ["moonstars"] },
  "gruvbox":          { acc: ["pumpkin"] },
  "matte-black":      { acc: ["bow"], mono: true },
  "vantablack":       { acc: ["bow"], mono: true },
  "white":            { acc: ["bow"], mono: true },
  "kanagawa":         { acc: ["headband"], band: "v" },
  "last-horizon":     { acc: ["headband"], band: "O" },
  "lumon":            { acc: ["tie"] },
  "lupine":           { acc: ["flower"] },
  "miasma":           { acc: ["mushroom"] },
  "osaka-jade":       { acc: ["gem"] },
  "retro-82":         { acc: ["retroshades"] },
  "ristretto":        { acc: ["beanie"] },
  "solitude":         { acc: ["moonstars"] },
  "aether":           { acc: ["halo"] },
  "ethereal":         { acc: ["halo"] },
  "flexoki-light":    { acc: ["flower"] }
}

function slug(name) {
  return String(name || "").trim().toLowerCase().replace(/[\s_]+/g, "-")
}

function themeInfo(themeName) {
  return THEMES[slug(themeName)] || { acc: ["bow"], fallback: true }
}

// accessorySetting: "auto" | "none" | accessory name
function accessoriesFor(themeName, accessorySetting) {
  var s = String(accessorySetting || "auto")
  if (s === "none") return []
  if (s !== "auto") return ACCESSORIES.indexOf(s) >= 0 ? [s] : []
  return themeInfo(themeName).acc
}

// ------------------------------------------------------------ frames

function makeGrid() {
  var g = []
  for (var y = 0; y < GRID_H; y++) {
    var row = []
    for (var x = 0; x < GRID_W; x++) row.push(".")
    g.push(row)
  }
  return g
}

function spriteOrigin(pet) {
  var def = PETS[pet] || PETS.slime
  return [2, GRID_H - def.rows.length]
}

function setCell(g, x, y, c) {
  if (y < 0 || y >= GRID_H || x < 0 || x >= GRID_W) return
  g[y][x] = c
}

function getCell(g, x, y) {
  if (y < 0 || y >= GRID_H || x < 0 || x >= GRID_W) return "."
  return g[y][x]
}

function isBody(c) { return c === "b" || c === "B" || c === "h" }

// opts: { frame: 0|1, blink, mouthOpen, mood: "sad"|"grumpy"|..., acc: [..], band }
function buildGrid(pet, opts) {
  var def = PETS[pet] || PETS.slime
  opts = opts || {}
  var g = makeGrid()
  var o = spriteOrigin(pet)
  var ox = o[0], oy = o[1]
  for (var r = 0; r < def.rows.length; r++) {
    var line = def.rows[r]
    if (opts.frame === 1 && def.alt && def.alt[r] !== undefined) line = def.alt[r]
    for (var c = 0; c < line.length; c++) {
      if (line[c] !== ".") setCell(g, ox + c, oy + r, line[c])
    }
  }
  var i, e
  if (opts.blink) {
    for (i = 0; i < def.eyes.length; i++) {
      e = def.eyes[i]
      for (var ex = 0; ex < e[2]; ex++) {
        if (e[3] >= 2) {
          setCell(g, ox + e[0] + ex, oy + e[1], "b")
          setCell(g, ox + e[0] + ex, oy + e[1] + 1, "o")
        } else {
          setCell(g, ox + e[0] + ex, oy + e[1], "o")
        }
      }
    }
  }
  var m = def.mouth
  if (opts.mouthOpen) {
    for (var mx = m[0] - 1; mx <= m[0] + m[2]; mx++) setCell(g, ox + mx, oy + m[1], "m")
    for (mx = m[0]; mx < m[0] + m[2]; mx++) setCell(g, ox + mx, oy + m[1] + 1, "p")
  }
  if (opts.mood === "grumpy" && !opts.blink) {
    for (i = 0; i < def.eyes.length; i++) {
      e = def.eyes[i]
      for (var bx = 0; bx < e[2]; bx++) setCell(g, ox + e[0] + bx, oy + e[1] - 1, "o")
    }
  } else if (opts.mood === "sad" && !opts.blink) {
    e = def.eyes[0]
    setCell(g, ox + e[0], oy + e[1] + e[3], "v")
  }
  applyStage(g, pet, opts.stage || 1, opts.variant || "classic")
  applyAccessories(g, pet, opts.acc || [], opts.band || "r")
  if ((opts.stage || 1) >= 3 && opts.variant === "cyber" && (opts.acc || []).indexOf("glow") < 0) glowPass(g)
  return g
}

// ------------------------------------------------------------ evolution
// Stages: 1 baby, 2 teen, 3 adult (variant classic | cyber | chonk), 4 elder.
// Babies are drawn smaller (fewer screen pixels per art pixel, see babyPx());
// later stages add small overlays on top of the same base map.
var STAGES = ["", "baby", "teen", "adult", "elder"]
var VARIANTS = ["classic", "cyber", "chonk"]

function babyPx(px) { return Math.max(2, Math.round(px * 0.75)) }

function rowSpan(g, y) {
  var l = -1, r = -1
  for (var x = 0; x < GRID_W; x++) if (g[y][x] !== ".") { if (l < 0) l = x; r = x }
  return [l, r]
}

function applyStage(g, pet, stage, variant) {
  var def = PETS[pet] || PETS.slime
  var o = spriteOrigin(pet)
  var ox = o[0], oy = o[1]
  var cx = ox + Math.round(def.cx)
  var top = oy + def.headTop
  var x, y, sp
  if (stage >= 2) {
    // teen: a little tuft on the head
    setCell(g, cx, top - 1, "o"); setCell(g, cx + 1, top - 2, "o"); setCell(g, cx, top - 2, "h")
  }
  if (stage >= 3) {
    var y0 = oy + def.eyes[0][1] + 2, y1 = oy + def.rows.length - 2
    if (variant === "chonk") {
      // rounder: push the outline one cell outwards on the body rows
      for (y = y0; y < y1; y++) {
        sp = rowSpan(g, y)
        if (sp[0] <= 0 || sp[1] >= GRID_W - 1) continue
        if (g[y][sp[0]] === "o") { g[y][sp[0] - 1] = "o"; g[y][sp[0]] = "b" }
        if (g[y][sp[1]] === "o") { g[y][sp[1] + 1] = "o"; g[y][sp[1]] = "b" }
      }
    } else if (variant === "cyber") {
      // circuit traces in the accent color
      y = oy + def.neckY + 1
      for (x = 0; x < GRID_W; x++) if (isBody(getCell(g, x, y)) && x % 2 === 0) setCell(g, x, y, "a")
      for (y = oy + def.neckY + 1; y < y1; y++) if (isBody(getCell(g, cx - 3, y))) setCell(g, cx - 3, y, "a")
      if (isBody(getCell(g, cx + 3, y1 - 1))) setCell(g, cx + 3, y1 - 1, "a")
    } else {
      // classic: darker back markings
      for (y = top + 1; y <= top + 2; y++)
        for (x = cx - 2; x <= cx + 2; x += 2) if (isBody(getCell(g, x, y))) setCell(g, x, y, "B")
    }
  }
  if (stage >= 4) {
    // elder: wise white brows and a few sparkles
    for (var i = 0; i < def.eyes.length; i++) {
      var e = def.eyes[i]
      for (x = 0; x < e[2]; x++) setCell(g, ox + e[0] + x, oy + e[1] - 1, "w")
    }
    setCell(g, 0, top + 2, "y"); setCell(g, GRID_W - 1, top + 5, "y"); setCell(g, 1, oy + def.rows.length - 3, "y")
  }
}

// The egg shown before a pet hatches (frame 0 still, 1 wobble, 2 cracked).
var EGG = [
  "......oooo......",
  ".....ohhbbo.....",
  "....ohbbbbbo....",
  "...ohbbpbbbbo...",
  "...obbbbbbpbo...",
  "..obpbbbbbbbbo..",
  "..obbbbbpbbbbo..",
  "..obbbbbbbbpbo..",
  "..oBbpbbbbbbBo..",
  "...oBBbbbbBBo...",
  "....oooooooo...."
]

function eggGrid(frame) {
  var g = makeGrid()
  var oy = GRID_H - EGG.length, ox = frame === 1 ? 3 : 2
  for (var r = 0; r < EGG.length; r++) for (var c = 0; c < EGG[r].length; c++)
    if (EGG[r][c] !== ".") setCell(g, ox + c, oy + r, EGG[r][c])
  if (frame === 2) {
    var crack = [[7, 3], [8, 4], [7, 5], [8, 6], [9, 5], [10, 4]]
    for (var i = 0; i < crack.length; i++) setCell(g, ox + crack[i][0], oy + crack[i][1], "o")
  }
  return g
}

function applyAccessories(g, pet, acc, band) {
  var def = PETS[pet] || PETS.slime
  var o = spriteOrigin(pet)
  var ox = o[0], oy = o[1]
  var i, x, y, e, map, r, c
  for (var a = 0; a < acc.length; a++) {
    var name = acc[a]
    if (HATS[name]) {
      map = HATS[name]
      var h = map.rows.length, w = map.rows[0].length
      var hx = ox + Math.round(def.cx + 0.5 - w / 2)
      var hy = oy + def.headTop - h + map.overlap
      for (r = 0; r < h; r++) for (c = 0; c < w; c++)
        if (map.rows[r][c] !== ".") setCell(g, hx + c, hy + r, map.rows[r][c])
    } else if (SIDE[name]) {
      map = SIDE[name]
      var sx = GRID_W - map.rows[0].length
      var sy = oy + def.headTop - 3
      if (sy < 0) sy = 0
      for (r = 0; r < map.rows.length; r++) for (c = 0; c < map.rows[r].length; c++)
        if (map.rows[r][c] !== ".") setCell(g, sx + c, sy + r, map.rows[r][c])
    } else if (name === "shades" || name === "retroshades") {
      var L = def.eyes[0], Rr = def.eyes[1]
      for (i = 0; i < def.eyes.length; i++) {
        e = def.eyes[i]
        var lens = name === "retroshades" ? (i === 0 ? "r" : "v") : "k"
        for (y = 0; y < e[3]; y++) for (x = 0; x < e[2]; x++) setCell(g, ox + e[0] + x, oy + e[1] + y, lens)
        if (name === "shades") setCell(g, ox + e[0], oy + e[1], "a")
      }
      for (x = L[0] + L[2]; x < Rr[0]; x++) setCell(g, ox + x, oy + L[1], "k")
      setCell(g, ox + L[0] - 1, oy + L[1], "k")
      setCell(g, ox + Rr[0] + Rr[2], oy + Rr[1], "k")
    } else if (name === "visor") {
      var V0 = def.eyes[0], V1 = def.eyes[1]
      for (y = 0; y < V0[3]; y++)
        for (x = V0[0] - 1; x <= V1[0] + V1[2]; x++)
          setCell(g, ox + x, oy + V0[1] + y, y === 0 ? "V" : "v")
      setCell(g, ox + V1[0] + 1, oy + V0[1], "w")
    } else if (name === "headband") {
      y = oy + def.headTop + 1
      for (x = 0; x < GRID_W; x++) if (isBody(getCell(g, x, y))) setCell(g, x, y, band)
    } else if (name === "scarf") {
      y = oy + def.neckY
      var right = -1
      for (x = 0; x < GRID_W; x++) if (isBody(getCell(g, x, y))) { setCell(g, x, y, "r"); right = x }
      if (right > 0) { setCell(g, right - 1, y + 1, "R"); setCell(g, right - 1, y + 2, "r") }
    } else if (name === "snow") {
      setCell(g, 1, 3, "w"); setCell(g, 18, 6, "w"); setCell(g, 2, 11, "w"); setCell(g, 17, 1, "w")
    } else if (name === "tie") {
      x = ox + Math.round(def.cx)
      y = oy + def.neckY
      setCell(g, x, y, "k"); setCell(g, x, y + 1, "v"); setCell(g, x, y + 2, "v")
    } else if (name === "gem") {
      setCell(g, ox + def.forehead[0], oy + def.forehead[1], "j")
      setCell(g, ox + def.forehead[0] + 1, oy + def.forehead[1], "w")
    }
  }
  if (acc.indexOf("glow") >= 0) glowPass(g)
}

// soft halo (drawn at low alpha) around the outline
function glowPass(g) {
  var glow = [], x, y
  for (y = 0; y < GRID_H; y++) for (x = 0; x < GRID_W; x++) {
    if (g[y][x] !== ".") continue
    if (getCell(g, x - 1, y) === "o" || getCell(g, x + 1, y) === "o" ||
        getCell(g, x, y - 1) === "o" || getCell(g, x, y + 1) === "o") glow.push([x, y])
  }
  for (var i = 0; i < glow.length; i++) g[glow[i][1]][glow[i][0]] = "*"
}

// mouth position in canvas cells (center of the mouth's right edge)
function mouthCell(pet) {
  var def = PETS[pet] || PETS.slime
  var o = spriteOrigin(pet)
  return [o[0] + def.mouth[0] + def.mouth[2], o[1] + def.mouth[1]]
}

function topCell(pet, acc, stage) {
  var def = PETS[pet] || PETS.slime
  return Math.max(0, spriteOrigin(pet)[1] + def.headTop - ((acc && acc.length) ? 3 : ((stage || 1) >= 2 ? 2 : 0)))
}

// ------------------------------------------------------------ palette

function parseToml(raw) {
  var res = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_\-]+)\s*=\s*"([^"]*)"/)
    if (m) res[m[1]] = m[2]
  }
  return res
}

function hexToRgb(h) {
  h = String(h || "").replace("#", "")
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  if (h.length < 6) return null
  var n = parseInt(h.substring(0, 6), 16)
  if (isNaN(n)) return null
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

function rgbToHex(c) {
  function p(v) { v = Math.max(0, Math.min(255, Math.round(v))); return (v < 16 ? "0" : "") + v.toString(16) }
  return "#" + p(c[0]) + p(c[1]) + p(c[2])
}

function mix(a, b, t) {
  var x = hexToRgb(a), y = hexToRgb(b)
  if (!x || !y) return a
  return rgbToHex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t])
}

function darker(c, t) { return mix(c, "#000000", t) }
function lighter(c, t) { return mix(c, "#ffffff", t) }

function luminance(c) {
  var x = hexToRgb(c)
  if (!x) return 0.5
  return (0.2126 * x[0] + 0.7152 * x[1] + 0.0722 * x[2]) / 255
}

function gray(c) {
  var l = Math.round(luminance(c) * 255)
  return rgbToHex([l, l, l])
}

// colors: parsed colors.toml merged over the Commons.Color basics
function themeColors(raw, basics) {
  var t = parseToml(raw)
  var b = basics || {}
  function pick(k, fb) { return t[k] || fb }
  var accent = pick("accent", b.accent || "#7aa2f7")
  var fg = pick("foreground", b.foreground || "#c0caf5")
  var bg = pick("background", b.background || "#1a1b26")
  return {
    mode: t.mode || (luminance(bg) > 0.5 ? "light" : "dark"),
    accent: accent, foreground: fg, background: bg,
    red: pick("red", "#e05561"), yellow: pick("yellow", "#e5c07b"),
    orange: pick("orange", pick("bright_red", "#e8945a")), green: pick("green", "#8cc570"),
    cyan: pick("cyan", "#56b6c2"), blue: pick("blue", "#61afef"),
    magenta: pick("magenta", "#c678dd"), brown: pick("brown", ""),
    bright_green: pick("bright_green", ""), bright_cyan: pick("bright_cyan", "")
  }
}

function petBody(pet, tc) {
  if (pet === "cat") return tc.foreground
  if (pet === "dragon") return tc.green
  if (pet === "goblin") return tc.bright_green || lighter(tc.green, 0.15)
  return tc.accent
}

// ---- color modes: "theme" (default), "complement", or a custom "#rrggbb"

function rgbToHsl(c) {
  var x = hexToRgb(c)
  if (!x) return [0, 0, 0.5]
  var r = x[0] / 255, g = x[1] / 255, b = x[2] / 255
  var mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, h = 0, s = 0
  if (mx !== mn) {
    var d = mx - mn
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
    if (mx === r) h = (g - b) / d + (g < b ? 6 : 0)
    else if (mx === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h /= 6
  }
  return [h, s, l]
}

function hslToHex(h, s, l) {
  function f(p, q, t) {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  var r, g, b
  if (s === 0) { r = g = b = l } else {
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
    r = f(p, q, h + 1 / 3); g = f(p, q, h); b = f(p, q, h - 1 / 3)
  }
  return rgbToHex([r * 255, g * 255, b * 255])
}

// WCAG relative luminance / contrast ratio
function relLum(c) {
  var x = hexToRgb(c) || [128, 128, 128]
  var v = x.map(function (u) { u /= 255; return u <= 0.03928 ? u / 12.92 : Math.pow((u + 0.055) / 1.055, 2.4) })
  return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
}
function contrast(a, b) {
  var la = relLum(a), lb = relLum(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// Nudge lightness until `c` has at least `ratio` contrast with `bg`.
function ensureContrast(c, bg, ratio) {
  var hsl = rgbToHsl(c)
  var up = relLum(bg) < 0.4
  for (var i = 0; i < 20 && contrast(hslToHex(hsl[0], hsl[1], hsl[2]), bg) < ratio; i++)
    hsl[2] = Math.max(0, Math.min(1, hsl[2] + (up ? 0.04 : -0.04)))
  return hslToHex(hsl[0], hsl[1], hsl[2])
}

// Opposite hue; greys have no opposite, so they borrow the accent's.
function complementOf(c, accent) {
  var hsl = rgbToHsl(c)
  if (hsl[1] < 0.15) {
    var a = rgbToHsl(accent)
    if (a[1] < 0.15) return c
    hsl = [a[0], a[1], hsl[2]]
  }
  return hslToHex((hsl[0] + 0.5) % 1, Math.max(0.5, hsl[1]), Math.max(0.3, Math.min(0.75, hsl[2])))
}

function isHex(s) { return /^#[0-9a-fA-F]{6}$/.test(String(s || "")) }

function palette(pet, tc, mono, colorMode) {
  var body = petBody(pet, tc)
  var dark = tc.mode !== "light"
  var wing = tc.cyan
  var mode = String(colorMode || "theme")
  if (isHex(mode)) {
    body = mode
    mono = false
  } else if (mode === "complement") {
    body = ensureContrast(complementOf(mono ? tc.accent : body, tc.accent), tc.background, 3)
    wing = ensureContrast(complementOf(wing, tc.accent), tc.background, 2)
    mono = false
  } else if (mono) {
    body = gray(dark ? tc.foreground : mix(tc.foreground, tc.background, 0.35))
  }
  var lum = luminance(body)
  var brown = tc.brown || darker(mix(tc.orange, tc.yellow, 0.3), 0.45)
  var p = {
    o: darker(body, lum > 0.3 ? 0.62 : 0.75),
    b: body,
    B: darker(body, 0.24),
    h: lighter(body, 0.28),
    e: lum < 0.25 ? lighter(tc.accent, 0.2) : "#101018",
    w: "#ffffff",
    p: mix(tc.magenta, "#ffffff", 0.25),
    m: darker(body, 0.7),
    y: tc.yellow, r: tc.red, R: darker(tc.red, 0.3),
    O: tc.orange, Q: darker(tc.orange, 0.3),
    g: tc.green, G: darker(tc.green, 0.35),
    c: brown, C: lighter(brown, 0.25),
    k: "#111118", a: tc.accent,
    v: tc.cyan, V: lighter(tc.cyan, 0.35), j: mix(tc.cyan, tc.green, 0.5),
    W: pet === "dragon" ? wing : body,
    "*": tc.accent
  }
  if (pet === "dragon") p.y = tc.yellow
  if (mono) {
    for (var k in p) if (k !== "w" && k !== "k") p[k] = gray(p[k])
  }
  return p
}
