# Contributing

Thanks for wanting to make the pet better! Bug reports, ideas, new accessories, ports and
pixel art are all welcome.

## Getting set up

```sh
git clone https://github.com/3thanD/desktop-pet.git
cd desktop-pet
./install.sh            # links this clone in as the Omarchy plugin and runs setup
```

The Omarchy shell keeps a cached copy of plugin QML, so after changing a `.qml` file or
`Sprites.js` run `omarchy restart shell`. Python and CLI changes apply immediately.

You can also run the pet in its own Quickshell instance with a throwaway home, which is handy
for testing without touching your real pet: create a `shell.qml` with
`ShellRoot { PetCore { host: null; pluginDir: "/path/to/desktop-pet" } }` next to links to the
QML files, then `HOME=/tmp/pet-home quickshell -p that-dir`. Talk to it with
`quickshell ipc -p that-dir call desktoppet status`.

## Where things live

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). In short: `PetCore.qml` is the pet,
`Sprites.js` the art, `OmarchyHost.qml` the only Omarchy-specific QML, `scripts/adapters/` the
compositor, `scripts/terminals/` the terminals, `bin/desktop-pet` the CLI.

## Guidelines

- Keep it cheap: no full-screen repainting surfaces, no continuous animations while idle.
  The pet should be happy on a CPU-only machine.
- Keep it private: nothing beyond the documented pet events goes to the brain; no network
  access except the optional local `claude` CLI.
- Keep it reversible: anything that edits user files needs a backup and an undo in
  `desktop-pet uninstall`.
- Original characters only, please (no trademarked creatures).
- Pixel art: every sprite is a 16-wide character map in `Sprites.js`; accessories and stage
  overlays are small additive maps placed by anchors.

## Ports

Porting to another distro or compositor is the most wanted contribution. Start with
`scripts/adapters/template.py` (compositor) or `docs/STANDALONE.md` (no Omarchy), and open a
"Feature request or port" issue so others know.

## Pull requests

Small, focused PRs are easiest to review. Please describe how you tested (which pets, sizes,
themes) and include a screenshot for visual changes.
