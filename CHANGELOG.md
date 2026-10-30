# Changelog

## 0.2.0 (unreleased)

### Pet skills
- A skills system: tricks are small declarative JSON recipes (`docs/skill.schema.json`,
  `docs/SKILLS.md`) built only from a fixed list of approved actions (move/hop/path, frame sets,
  speech bubbles, particles, trails, tint, a drawn screen-shake, falling-glyph physics, doodles,
  optional sounds, a journaled dock or wallpaper change, mini clones, a coin hoard). Recipes are
  validated against the schema; unknown actions or fields, command/path/URL-like text,
  over-long durations, unsafe doodle paths and oversized files are rejected.
- Hard caps everywhere: a run stops after 120 s, every effect has its own expiry and reverts by
  itself; `heal`, `off`, `uninstall`, `skills off` and switching pets revert everything at once.
  The dock icon and the wallpaper are journaled before they change and restored on load, crash,
  reload and when the plugin is disabled.
- Eight built-in skills, each toggleable, rate-limited, theme-colored and size-aware:
  slime **trail** and **mitosis**, cat **cursor-sit** (never blocks clicks) and **knock-off**
  (a letter falls off btop and shatters; the hole heals), dragon **hoard** (a tiny persistent
  coin pile, optional `hoardLabel`) and **roar**, goblin **wallpaper-heist** and **ransom**.
- Pets pitch skills: with the brain on, at most once a day, the pet asks Claude in character
  for a new recipe and a one-line pitch. It is validated, tamed and queued; never auto-enabled.
- User skills and shareable skill packs in `~/.config/desktop-pet/skills/` (off until enabled).
- CLI: `desktop-pet skills` (list), `skills review` (preview once / approve / reject),
  `skills enable|disable|on|off|pitch|run|show|remove|sound|hoard-label`, and `desktop-pet pet`.
  Bash completion for all of it.
- Right-click menu: a Skills section with a pending-pitch badge, try / approve / reject, a toggle
  for each of the current pet's skills, and skill sounds.

### Changed
- `heal`, `off` and `uninstall` also stop skills and restore the wallpaper.
- The build buddy counts successful commands for the dragon's hoard even while the pet sleeps
  (reactions still wait until it is awake).

## 0.1.0

First public release.

### Pets
- Four original pixel-art pets: slime, cat, baby dragon and goblin, drawn from character maps
  at 50 / 100 / 200% size in crisp whole-pixel steps.
- Eggs: a new pet hatches from a wobbling egg and asks for a name. `desktop-pet new` starts over.
- Care: hunger, happiness and energy decay over time; left-click petting, sleeping 23:00-07:00,
  sad/grumpy moods, no death.
- Evolution over real days of care: baby → teen → adult (classic, cyber or chonk depending on
  diet) → rare elder, with a flash-and-sparkles animation.
- Each species keeps its own save. State is written atomically with a rolling backup and
  recovers from a corrupt file.

### Things it does
- Eats 2-5 letters at a time from btop or any visible kitty window, using overlay patches that
  follow the window, hide when it is covered, and heal after a few minutes.
- The dragon breathes fire and turns text red.
- The goblin moves or hides a pinned nwg-dock-hyprland icon for a while and puts it back. A
  journal written before the dock is touched restores it after `off`, `heal`, a reload or a crash.
- Fetch: throw a ball, or grab and flick it with the mouse; the pet brings it back.
- Build buddy (optional shell hook): reacts to failed commands, passing tests, `git push` and
  long-running commands. Records only command names, exit codes and durations.
- Optional brain through the local Claude Code CLI (haiku, all tools disabled, rate-limited),
  with per-pet personas, a short memory and canned lines offline.

### Look
- Colors follow the live Omarchy theme; an accessory per theme with a fallback for custom themes;
  complementary-color mode (contrast-checked) and custom colors.

### Control
- Right-click menu with stats, age and every setting (also SUPER+SHIFT+left-click).
- `desktop-pet` CLI: status bars, previews, setup/uninstall, bash completion.
- SUPER+CTRL+P toggles the pet (added by `desktop-pet setup`).
- Multiple monitors (the pet lives on the focused one) and fractional scaling.
