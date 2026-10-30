# Architecture

The pet is split into small layers so the Omarchy- and Hyprland-specific parts
stay in a few files. v0.1 ships one implementation of each seam.

```
Pet.qml               Omarchy plugin entry point (manifest "service")
 ├─ OmarchyHost.qml   host/theme adapter: Commons.Color, Style font, theme name,
 │                    colors.toml, live theme-change detection
 └─ PetCore.qml       the pet: stats, behavior, windows, overlay, IPC "desktoppet"
     ├─ PetStore.qml  state.json: per-species saves, atomic writes, .bak, corrupt recovery
     ├─ PetMenu.qml   right-click context menu (writes the same config.json)
     ├─ PetBall.qml   fetch ball (its own tiny input surface + physics)
     ├─ PetBuddy.qml  build buddy: reads the shell hook's event file
     ├─ PetSkills.qml skills engine: runs validated recipes (approved actions only),
     │   │            triggers, cooldowns, hard caps, revertAll()
     │   ├─ PetFx.qml       effects overlay (1x1 when idle): trails, glyph physics, shake, tint
     │   ├─ PetClone.qml    a mini copy of the pet (mitosis), click-through
     │   ├─ PetSticker.qml  ransom note / doodle sticker, click-through
     │   └─ PetHoard.qml    the dragon's coin pile, click-through
     └─ Sprites.js    pixel maps, accessories, palette from theme colors, doodles

scripts/helper.py     one-shot helper the QML runs (JSON on stdout)
 ├─ skills.py         recipe discovery + schema validation (docs/skill.schema.json),
 │                    pitch queue (Claude), journaled wallpaper swap, sounds
 ├─ adapters/         compositor adapters: windows, monitors, focus
 │   ├─ hyprland.py   hyprctl
 │   └─ template.py   documented stub for sway / niri / KDE
 ├─ terminals/        terminal adapters: find a terminal, grid geometry, cells
 │   └─ kitty.py      kitty remote control
 └─ util.py

skills/<pet>/*.json   the built-in skill recipes
shell/                optional build-buddy hooks for bash and zsh
tools/                render-sprites.js (sprite sheets), make-media.sh (demo media)
bin/desktop-pet       CLI: edits ~/.config/desktop-pet/config.json (watched by the
                      pet), talks to the running pet over IPC, setup/uninstall
```

## Rules

- `PetCore.qml`, `Sprites.js` and the overlay never import `qs.Commons` or call
  `omarchy` commands. They read `host.accent / background / foreground`,
  `host.colorsRaw` (a colors.toml-style palette), `host.themeName` and
  `host.uiFont`. With `host: null` they fall back to a built-in palette.
- Core helper code never runs `hyprctl` or `kitty`; it calls
  `adapters.detect()` and `terminals.adapter_for(window)`.
- In the CLI, everything that depends on the Omarchy shell (enable/disable and
  the IPC transport) is in the "host integration" block: `host_is_enabled()`,
  `host_set_enabled()`, `ipc()`.

## Data flow

- Settings: CLI writes `~/.config/desktop-pet/config.json` -> PetCore's FileView
  picks it up live.
- Life: PetStore writes `~/.local/state/desktop-pet/state.json` (one record per
  species: hatch date, stage, variant, meals, diet, stats) on every meaningful
  change and every minute, plus `status.json`, a snapshot the CLI can read.
- Brain: PetCore (or the CLI for `say`/`chat`) runs `helper.py talk`, which logs
  the event in `memory.json` and returns a line (Claude CLI or canned).
- Skills: PetSkills runs `helper.py skills-list` (validated recipes only) and executes
  them with its own action implementations; recipes never reach a shell. Desktop changes go
  through journals the helper writes BEFORE changing anything (`dock-journal.json`,
  `wall-journal.json`); `helper.py restore-all` runs on load, heal, off and unload.
  Rate-limit logs and the hoard live in `state.json` under `skills`.
- Eating: PetCore runs `helper.py scan` -> target window geometry, cell grid and
  letter runs -> the pet walks there and adds patches; `helper.py geom` is polled
  every 2 s while patches are visible.

## Adding a compositor adapter

1. Copy `scripts/adapters/template.py` to `scripts/adapters/<name>.py`.
2. Implement `available()`, `monitors()`, `focused_monitor()`, `list_windows()`
   and `active_window()` with the shapes documented in `adapters/__init__.py`
   (logical pixels, global layout coordinates).
3. Add a detection rule to `adapters.detect()` (e.g. `SWAYSOCK`, `NIRI_SOCKET`).
4. Check: `python3 -I scripts/helper.py monitor` and `... scan`.

The pet's windows are wlr-layer-shell surfaces, so a compositor also needs
layer-shell support (sway, niri, KDE and Hyprland have it; GNOME does not).

## Adding a terminal adapter

1. Create `scripts/terminals/<name>.py` with `NAME`, `matches(window)`,
   `priority(window)`, `grid_info(window, scale)` and `read_cells(window, info)`
   (see `terminals/__init__.py`).
2. Append it to `terminals.ADAPTERS` and remove its class from
   `KNOWN_UNSUPPORTED`.
3. The hard part is reading screen contents without the terminal's help:
   it needs a remote-control or scripting API (kitty `@ get-text`, wezterm
   `cli get-text`, ...). Cell geometry must match the terminal's own layout.

## Testing without touching your real pet

`PetCore` runs fine without Omarchy (`host: null`), so a second Quickshell
instance with a throwaway `HOME` is a full sandbox:

```sh
mkdir -p /tmp/pet-test/qs && cd /tmp/pet-test/qs
for f in PetCore PetMenu PetStore PetBall PetBuddy PetSkills PetFx PetClone PetSticker PetHoard; do
  ln -s ~/src/desktop-pet/$f.qml .; done
ln -s ~/src/desktop-pet/Sprites.js .
cat > shell.qml <<'QML'
import QtQuick
import Quickshell
ShellRoot { PetCore { host: null; pluginDir: "/home/you/src/desktop-pet" } }
QML
HOME=/tmp/pet-test/home quickshell -p /tmp/pet-test/qs &
DESKTOP_PET_QS_CONFIG=/tmp/pet-test/qs HOME=/tmp/pet-test/home ~/src/desktop-pet/bin/desktop-pet
```

Skills in the sandbox: `desktop-pet skills run <id>` (or `quickshell ipc -p ... call desktoppet
runSkill <id>`) runs one now, and `... call desktoppet skillsStatus` shows the active effects.
Don't run `desktop-pet off` from the sandbox: it disables the real plugin. Note that the
wallpaper skill goes through `omarchy theme bg set`, which also talks to the running Omarchy
shell, so in the sandbox it briefly changes the real wallpaper too (and restores it).
