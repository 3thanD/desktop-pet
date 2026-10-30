// Render the real sprite art (Sprites.js) to PPM images, for docs.
//   node tools/render-sprites.js <out-dir>
// Writes pets.ppm (every pet x every stage, Hackerman colors) and
// themes.ppm (the slime across several Omarchy themes + complement mode).
// Convert with ImageMagick: magick pets.ppm docs/pets.png
const fs = require("fs"), path = require("path"), vm = require("vm")
const root = path.join(__dirname, "..")
const S = {}
vm.runInNewContext(fs.readFileSync(path.join(root, "Sprites.js"), "utf8").replace(".pragma library", "") +
  "\nObject.assign(out, {PET_NAMES, buildGrid, palette, themeColors, themeInfo, accessoriesFor, babyPx, GRID_W, GRID_H})", { out: S })
const outDir = process.argv[2] || "."
const themesDir = "/usr/share/omarchy/themes"

function themeTc(name) {
  let raw = ""
  try { raw = fs.readFileSync(path.join(themesDir, name, "colors.toml"), "utf8") } catch (e) {}
  return S.themeColors(raw, {})
}
function hex(c) { c = c.replace("#", ""); return [parseInt(c.slice(0, 2), 16), parseInt(c.slice(2, 4), 16), parseInt(c.slice(4, 6), 16)] }

function canvas(w, h, bg) { const px = new Uint8Array(w * h * 3); for (let i = 0; i < w * h; i++) px.set(hex(bg), i * 3); return { w, h, px } }
function blend(cv, x, y, rgb, a) {
  if (x < 0 || y < 0 || x >= cv.w || y >= cv.h) return
  const i = (y * cv.w + x) * 3
  for (let k = 0; k < 3; k++) cv.px[i + k] = Math.round(cv.px[i + k] * (1 - a) + rgb[k] * a)
}
function draw(cv, grid, pal, ox, oy, cell) {
  for (let y = 0; y < grid.length; y++) for (let x = 0; x < grid[y].length; x++) {
    const c = grid[y][x]; if (c === ".") continue
    const rgb = hex(pal[c] || "#ff00ff"), a = c === "*" ? 0.35 : 1
    for (let dy = 0; dy < cell; dy++) for (let dx = 0; dx < cell; dx++) blend(cv, ox + x * cell + dx, oy + y * cell + dy, rgb, a)
  }
}
function save(cv, file) {
  fs.writeFileSync(file, Buffer.concat([Buffer.from(`P6 ${cv.w} ${cv.h} 255\n`), Buffer.from(cv.px)]))
}

const CELL = 6, BOX = S.GRID_W * CELL, GAP = 18
// pets x stages
const stages = [[1, "classic"], [2, "classic"], [3, "classic"], [3, "cyber"], [3, "chonk"], [4, "classic"]]
const hk = themeTc("hackerman")
let cv = canvas(stages.length * (BOX + GAP) + GAP, S.PET_NAMES.length * (BOX + GAP) + GAP, hk.background)
S.PET_NAMES.forEach((pet, r) => {
  const pal = S.palette(pet, hk, false, "theme")
  stages.forEach(([st, v], c) => {
    const cell = st === 1 ? S.babyPx(CELL) : CELL, size = S.GRID_W * cell
    const g = S.buildGrid(pet, { stage: st, variant: v, acc: [] })
    draw(cv, g, pal, GAP + c * (BOX + GAP) + (BOX - size) / 2, GAP + r * (BOX + GAP) + (BOX - size), cell)
  })
})
save(cv, path.join(outDir, "pets.ppm"))

// slime across themes (+ complement on the first)
const themes = ["hackerman", "tokyo-night", "nord", "catppuccin-latte", "gruvbox", "rose-pine", "everforest", "retro-82"]
const cols = themes.length + 1
cv = canvas(cols * (BOX + GAP) + GAP, BOX + 2 * GAP, "#000000")
themes.concat(["hackerman"]).forEach((t, i) => {
  const tc = themeTc(t), info = S.themeInfo(t), mode = i === themes.length ? "complement" : "theme"
  const x0 = GAP / 2 + i * (BOX + GAP)
  for (let y = 0; y < BOX + 2 * GAP; y++) for (let x = 0; x < BOX + GAP; x++) blend(cv, x0 + x, y, hex(tc.background), 1)
  draw(cv, S.buildGrid("slime", { stage: 2, acc: S.accessoriesFor(t, "auto"), band: info.band || "r" }),
       S.palette("slime", tc, !!info.mono, mode), x0 + GAP / 2, GAP, CELL)
})
save(cv, path.join(outDir, "themes.ppm"))
console.log("wrote pets.ppm and themes.ppm to " + outDir)
