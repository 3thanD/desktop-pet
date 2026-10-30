#!/usr/bin/env bash
# Manual install from a clone (the usual way is:
#   omarchy plugin add https://github.com/3thanD/desktop-pet.git --enable
# followed by: ~/.config/omarchy/plugins/3thand.desktop-pet/bin/desktop-pet setup)
#
#   ./install.sh [-y]   link this clone in as the plugin, run setup, turn the pet on
set -euo pipefail
ID="3thand.desktop-pet"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
DEST="$PLUGINS/$ID"

mkdir -p "$PLUGINS"
if [[ "$(realpath -m "$DEST")" != "$REPO" ]]; then
  if [[ -e $DEST && ! -L $DEST ]]; then
    echo "!! $DEST already exists and is not a link to this clone; leaving it alone." >&2
    echo "   Remove it (omarchy plugin remove $ID) or run setup from that copy instead." >&2
    exit 1
  fi
  ln -sfn "$REPO" "$DEST"
  echo ":: plugin: $DEST -> $REPO"
fi
chmod +x "$REPO/bin/desktop-pet" "$REPO/scripts/helper.py"
"$REPO/bin/desktop-pet" setup "$@"
"$REPO/bin/desktop-pet" on
