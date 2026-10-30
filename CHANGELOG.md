# Changelog

## 0.1.0 (unreleased)

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
