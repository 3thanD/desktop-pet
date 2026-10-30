#!/usr/bin/env bash
# Undo install.sh / `desktop-pet setup`: turns the pet off, restores the dock,
# removes the CLI/completion links, the keybinding and kitty lines (with backups),
# and the plugin link.   ./uninstall.sh [--purge]   (--purge also deletes settings/state)
set -uo pipefail
ID="3thand.desktop-pet"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$ID"
"$REPO/bin/desktop-pet" uninstall "$@"
if [[ -L $DEST ]]; then
  rm -f "$DEST"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  echo ":: removed plugin link $DEST"
fi
