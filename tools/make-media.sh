#!/usr/bin/env bash
# Record the README / announcement media on a real, unlocked Omarchy desktop.
#
#   tools/make-media.sh [out-dir]        (default: docs/)
#
# Produces hero.png, eat.gif/.mp4, dragon.gif/.mp4, goblin.gif/.mp4,
# evolve.gif, themes.gif and pets.png. Needs grim + ffmpeg (gpu-screen-recorder
# is used when it works, otherwise a grim frame sequence). It opens one btop
# window (closed at the end), switches pets/themes while recording, and puts
# your pet, size, color and theme back afterwards. Close anything personal first.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO/docs}"
PET="$REPO/bin/desktop-pet"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }
need grim; need ffmpeg; need hyprctl; need python3
[[ $(omarchy-shell lock isLocked 2>/dev/null) == true ]] && { echo "unlock the session first" >&2; exit 1; }

ipc() { omarchy-shell desktoppet "$@" >/dev/null 2>&1; }
cfg_get() { python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.config/desktop-pet/config.json'))).get('$1',''))"; }
mon() { hyprctl -j monitors | python3 -c "import json,sys;m=[m for m in json.load(sys.stdin) if m['focused']][0];print(m['name'])"; }

ORIG_PET=$(cfg_get pet); ORIG_SIZE=$(cfg_get size); ORIG_COLOR=$(cfg_get color)
ORIG_THEME=$(cat ~/.local/state/omarchy/current/theme.name 2>/dev/null)
restore() {
  "$PET" pick "${ORIG_PET:-slime}" >/dev/null; "$PET" size "${ORIG_SIZE:-100}" >/dev/null
  "$PET" color "${ORIG_COLOR:-theme}" >/dev/null
  [[ -n $ORIG_THEME && $(cat ~/.local/state/omarchy/current/theme.name) != "$ORIG_THEME" ]] && omarchy theme set "$ORIG_THEME" >/dev/null 2>&1
  [[ -n ${BTOP_ADDR:-} ]] && hyprctl dispatch closewindow "address:$BTOP_ADDR" >/dev/null 2>&1
}
trap 'restore; rm -rf "$WORK"' EXIT

# record <name> <seconds> <command...>: capture the focused monitor while running a command
record() {
  local name=$1 secs=$2; shift 2
  local mp4="$WORK/$name.mp4"
  if command -v gpu-screen-recorder >/dev/null && \
     timeout $((secs + 5)) gpu-screen-recorder -w "$(mon)" -encoder cpu -f 30 -cursor no -o "$mp4" >/dev/null 2>&1 &
  then
    local gsr=$!; sleep 1; "$@" & sleep "$secs"; kill -INT $gsr 2>/dev/null; wait $gsr 2>/dev/null
  fi
  if [[ ! -s $mp4 ]]; then                     # fallback: grim frames at ~12 fps, half size
    mkdir -p "$WORK/$name"; "$@" &
    local n=0 end=$((SECONDS + secs))
    while (( SECONDS < end )); do grim -s 0.5 "$WORK/$name/$(printf %05d $n).png" 2>/dev/null; n=$((n + 1)); sleep 0.05; done
    ffmpeg -loglevel error -y -framerate $((n / secs)) -i "$WORK/$name/%05d.png" -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" "$mp4"
  fi
  cp "$mp4" "$OUT/$name.mp4"
  ffmpeg -loglevel error -y -i "$mp4" -vf "fps=12,scale=720:-1:flags=neighbor,palettegen=stats_mode=diff" "$WORK/p.png"
  ffmpeg -loglevel error -y -i "$mp4" -i "$WORK/p.png" -lavfi "fps=12,scale=720:-1:flags=neighbor[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4" "$OUT/$name.gif"
  echo "wrote $OUT/$name.gif ($(du -h "$OUT/$name.gif" | cut -f1))"
}

omarchy theme set hackerman >/dev/null 2>&1; sleep 3
omarchy launch tui btop >/dev/null 2>&1 & sleep 3
BTOP_ADDR=$(hyprctl -j clients | python3 -c "import json,sys;print(next((c['address'] for c in json.load(sys.stdin) if c['class']=='org.omarchy.btop'),''))")
"$PET" heal >/dev/null; "$PET" size 200 >/dev/null; "$PET" color theme >/dev/null

"$PET" pick slime >/dev/null; ipc wake; sleep 2
ipc moveTo 300 650; sleep 5; grim "$OUT/hero.png"; echo "wrote $OUT/hero.png"
record eat 14 "$PET" poke hungry
"$PET" pick dragon >/dev/null; ipc wake; sleep 2
record dragon 12 "$PET" poke fire
"$PET" pick goblin >/dev/null; ipc wake; sleep 2
pkill -36 -f nwg-dock-hyprland
record goblin 16 "$PET" goblin heist-now
"$PET" goblin heist-now >/dev/null; sleep 8
"$PET" pick slime >/dev/null; sleep 2
read -r ST VAR < <(omarchy-shell desktoppet status | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('stage',1),d.get('variant','classic'))")
record evolve 10 bash -c "for s in 1 2 3 4; do '$PET' evolve --debug-set \$s cyber >/dev/null; sleep 2.4; done"
"$PET" evolve --debug-set "${ST:-1}" "${VAR:-classic}" >/dev/null   # put the real stage back
record themes 16 bash -c "for t in tokyo-night nord catppuccin-latte gruvbox; do omarchy theme set \$t >/dev/null 2>&1; sleep 3; done; '$PET' color complement >/dev/null; sleep 3"
node "$REPO/tools/render-sprites.js" "$WORK" >/dev/null 2>&1 && magick "$WORK/pets.ppm" "$OUT/pets.png" && echo "wrote $OUT/pets.png"
echo "done"
