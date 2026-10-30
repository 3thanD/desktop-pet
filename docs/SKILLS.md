# Pet skills

Skills are little tricks your pet does on its own: a slime trail, a cat that swats a letter
off btop, a dragon's coin hoard, a goblin that "borrows" your wallpaper. Each one is a small
JSON **recipe**: a trigger plus a few steps built **only** from a fixed list of approved actions
that the pet already knows how to perform. A recipe can't run commands, open files or reach the
network, because no such action exists.

The house rule: **nothing may harm your desktop unless it is cute, entertaining and impermanent.**
Every action has a hard-capped duration, every effect reverts on its own, and
`desktop-pet heal`, `off` and `uninstall` undo everything immediately.

## Where skills live

| | location | default |
|---|---|---|
| built-in | `<plugin>/skills/<pet>/<id>.json` | on |
| yours / skill packs | `~/.config/desktop-pet/skills/<id>.json` (+ optional `NAME.png` doodles) | off until you enable it |
| pitched by your pet | `~/.local/state/desktop-pet/skills/pending/` | never runs until you approve it (a one-off preview excepted) |

```sh
desktop-pet skills                 # everything, with on/off, plus rejected files and why
desktop-pet skills enable my-trick # or disable
desktop-pet skills run my-trick    # run it once now (preview)
desktop-pet skills show my-trick   # what it does, step by step
desktop-pet skills off             # no skill activity at all
```

## A complete example

`~/.config/desktop-pet/skills/happy-twirl.json`:

```json
{
 "format": "desktop-pet-skill/1",
 "id": "happy-twirl",
 "name": "Happy twirl",
 "pet": "slime",
 "description": "When petted it sometimes twirls in a heart shape and sparkles.",
 "author": "you",
 "trigger": { "on": "petted", "chance": 0.3 },
 "cooldown": 30,
 "maxPerDay": 4,
 "steps": [
  { "action": "bubble", "text": "Wheee! {name} loves you!" },
  { "action": "path", "shape": "heart", "size": "small" },
  { "action": "particles", "kind": "sparkles", "count": 10, "color": "accent" },
  { "action": "trail", "kind": "hearts", "duration": 6, "fade": 4, "color": "magenta" }
 ]
}
```

Then `desktop-pet skills enable happy-twirl`. The pet re-reads the folder when you use the
`skills` commands (and every 10 minutes).

## Recipe fields

| field | | |
|---|---|---|
| `format` | required | always `"desktop-pet-skill/1"` |
| `id` | required | `a-z`, `0-9`, `-`; 2-32 characters; unique |
| `name` | required | up to 40 characters |
| `pet` | required | `slime`, `cat`, `dragon`, `goblin` or `any` |
| `trigger` | required | `{ "on": ..., "chance": 0-1, "min": number }`, see below |
| `cooldown` | required | minutes between runs (1-1440) |
| `maxPerDay` | optional | 1-100 |
| `description`, `author` | optional | plain text |
| `steps` | required | 1-24 steps, run in order |

Unknown fields anywhere are rejected. The machine-readable schema is
[`docs/skill.schema.json`](skill.schema.json).

### Triggers

| `on` | fires | `chance` is | `min` |
|---|---|---|---|
| `idle` | now and then while it is idle | per minute | |
| `walk` | when it starts a stroll (only skills without movement steps) | per stroll | |
| `happy` | while happiness ≥ `min` | per minute | happiness (default 95) |
| `neglected` | when nobody has petted it for `min` minutes | per minute | minutes (default 60) |
| `petted` | when you pet it | per pet | |
| `command-ok` | a terminal command succeeded (build buddy hook) | per command | |
| `milestone` | every `min` coins in the hoard | per milestone | coins (default 10) |
| `manual` | never on its own; only `skills run` / the menu | | |

Skills never start while the pet is an egg, asleep or has its menu open, and the pet starts
at most one automatic skill every 90 seconds.

### Actions

Durations are in seconds and capped as shown; a whole run is stopped at 120 s. Colors are a
theme role (`accent`, `body`, `foreground`, `red`, `yellow`, `orange`, `green`, `cyan`, `blue`,
`magenta`), so they follow your Omarchy theme and complement mode, or `#rrggbb`. Sizes follow
the pet size (50/100/200).

| action | fields | what it does |
|---|---|---|
| `move` | `to`: random, cursor, center, home, bottom, top, left, right; `follow` 0-10; `speed`: slow/normal/fast | walk somewhere. `to: cursor` + `follow` sits beside the pointer and follows it, with **no input mask** (never blocks a click) |
| `hop` | `count` 1-8, `height` 2-30 | hop in place |
| `path` | `shape`: circle, zigzag, figure8, square, heart; `size`: small/medium/large; `laps` 1-3 | walk a little shape |
| `animate` | `frames`: bounce, spin, wiggle, squash, blink, chomp, sleepy, swat; `duration` 0.2-10 | play a frame set |
| `bubble` | `text` (≤100 chars; `{name}` = the pet's name) | speech bubble |
| `wait` | `duration` 0.1-30 | pause |
| `particles` | `kind`: hearts, sparkles, coins, pixels, bubbles, stars, notes, smoke; `count` 1-24; `color` | a burst around the pet |
| `trail` | `kind`: drips, sparkles, footprints, hearts; `duration` 1-120; `fade` 2-20; `color` | leave marks behind while walking |
| `tint` | `color`; `opacity` 0.02-0.25; `duration` 0.5-10; `area`: pet/screen | a soft color wash (never takes input) |
| `shake` | `intensity`: gentle/medium; `duration` 0.2-3 | a screen-shake **drawn on an overlay**; no real window ever moves |
| `glyph` | `source`: terminal/text; `text` (1-3 chars, for `text`); `shatter` | a letter falls with physics and shatters into pixels. `terminal` swats one letter off btop/kitty (needs `eat on`); the hole is an overlay patch that heals like eaten letters |
| `doodle` | `image`; `where`: pet/corner/center; `duration` 1-60 | a small pixel doodle on the desktop |
| `sound` | `name`: blip, chime, coin, roar, pop, purr | a tiny synthesized sound; **off by default** (`desktop-pet skills sound on`) |
| `dock` | `mode`: hide/move; `duration` 5-120; `ransom`: `{ "task": "pet", "count": 1-10, "text" }` | hides or moves one pinned dock icon (needs `goblin-steal on`). Journaled; it comes back after `duration`, when the ransom is paid, or on heal/off/crash |
| `wallpaper` | `doodle`; `duration` 5-120 | swaps your Omarchy wallpaper for a pixel doodle and puts the original back (saved first, journaled, restored on heal/off/crash/reload) |
| `clones` | `count` 1-3; `duration` 3-120 | splits into mini copies that wander, then merge back |
| `hoard` | `add` 1-5 | adds coins to the tiny, click-through, size-capped coin pile (shown with the dragon; label: `desktop-pet skills hoard-label "text"`) |

Doodles (`image` / `doodle`): a built-in name (`goblin-was-here`, `slime-was-here`, `heart`,
`crown`, `paw`, `skull-and-coins`) or `NAME.png` sitting **directly** in
`~/.config/desktop-pet/skills/`: a real PNG (no symlinks, no paths), at most 256 KB and
1024×1024.

## What gets rejected

`desktop-pet skills` lists every rejected file with the reason. A recipe is refused when:

- it isn't valid JSON, or the file is larger than 16 KB
- it uses an action or a field that isn't in the schema
- a number is out of range (e.g. a `duration` of 999), or the timed steps add up to more than 120 s
- any text looks like a command, path or URL: `$`, backticks, `;`, `|`, `<`, `>`, `{}`, `\`,
  `&&`, `../`, `~/`, `/usr`..., `://`, words like `sudo`, `rm -`, `curl`, `bash`...
- a doodle path tries to leave the skills folder, is a symlink, isn't a PNG or is too big
- its `id` is already taken

Nothing in a recipe is ever executed: the pet only maps the approved action names to its own
built-in animations. The QML engine re-checks the action names and clamps every number again.

## Skills your pet invents

With the brain on (`desktop-pet brain on`) your pet occasionally (at most once a day) asks
Claude, in character, to invent a new skill. Claude gets the schema and must answer with only
a recipe and a one-line pitch, using your local Claude Code CLI with all tools disabled. The
recipe is validated (and tamed: forced to that pet, cooldown ≥ 30 min, at most 4 a day) and
queued. **It is never enabled automatically.**

```sh
desktop-pet skills pitch     # ask for one now (up to 6 a day)
desktop-pet skills review    # each pitch: what it does, its recipe; preview once / approve / reject
```

The right-click menu shows a badge with the number of waiting pitches and has try / approve /
reject buttons, plus a toggle for each of the current pet's skills.

## Skill packs

A skill pack is just a few recipe files (and maybe a PNG or two). To share one, zip up your
`~/.config/desktop-pet/skills/*.json` (and the PNGs they use). To install one, drop the files
into `~/.config/desktop-pet/skills/`, run `desktop-pet skills` to see what was accepted, and
`desktop-pet skills enable <id>` for the ones you want. Read a recipe first with
`desktop-pet skills show <id>`: it explains every step in plain words.
