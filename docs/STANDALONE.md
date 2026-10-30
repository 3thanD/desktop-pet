# TODO: standalone mode (planned for v0.2.0)

Goal: run the pet on plain Hyprland without Omarchy, e.g. `qs -p <repo>/standalone`.
Nothing here is built yet; the code is structured so this needs only new files.

What the standalone entry point needs:

1. `standalone/shell.qml`: a `ShellRoot` that instantiates `PetCore { host: ... }`
   and sets `pluginDir` to the repo root (so `scripts/` and `bin/` resolve).
2. A `GenericHost.qml` with the same properties as `OmarchyHost.qml`:
   - `accent`, `background`, `foreground`, `colorsRaw`: read from a user palette
     file (e.g. `~/.config/desktop-pet/colors.toml`), or leave empty to use the
     fallback palette in `Sprites.themeColors()`.
   - `themeName`: from config (drives accessories), default "".
   - `uiFont`: "monospace" or a config value.
   - `reload()`: re-read the palette; watch the file with `FileView`.
3. CLI: replace the three functions in the "host integration" block of
   `bin/desktop-pet`:
   - `host_set_enabled()`: start/stop `qs -p <repo>/standalone -d` (or a systemd
     user unit) instead of `omarchy plugin enable/disable`.
   - `host_is_enabled()`: check that process / unit.
   - `ipc()`: `qs -p <repo>/standalone ipc call desktoppet <method>`.
4. `desktop-pet setup`: keybinding for plain `hyprland.conf` (the `bindings.conf`
   path already exists) and an autostart line (`exec-once`).
5. Dock goblin: unchanged (nwg-dock-hyprland is optional already).
