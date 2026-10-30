# desktop-pet build buddy hook for zsh (installed by `desktop-pet setup --buddy`).
# Records ONLY the command's name (plus "push"/"test" for git/cargo/npm/go/make/
# yarn/pnpm), its exit code and duration in $XDG_RUNTIME_DIR/desktop-pet/buddy.json.
[[ -o interactive ]] || return 0
(( ${+__dp_buddy_loaded} )) && return 0
typeset -g __dp_buddy_loaded=1 __dp_cmd="" __dp_t0=0
typeset -g __dp_dir="${XDG_RUNTIME_DIR:-/tmp}/desktop-pet"
zmodload zsh/datetime 2>/dev/null
autoload -Uz add-zsh-hook

__dp_preexec() {
  local -a w; w=(${(z)1})
  local c=${w[1]:t} s=${w[2]}
  [[ $c == (sudo|time|command) ]] && { c=${w[2]:t}; s=${w[3]}; }
  case "$c:$s" in
    git:push|cargo:test|npm:test|go:test|make:test|yarn:test|pnpm:test|bun:test) __dp_cmd="$c $s" ;;
    *) __dp_cmd=${c//[^A-Za-z0-9._+-]/} ;;
  esac
  __dp_t0=${EPOCHREALTIME:-$SECONDS}
}

__dp_precmd() {
  local ec=$?
  if [[ -n $__dp_cmd ]]; then
    local t1=${EPOCHREALTIME:-$SECONDS}
    local dur=$(( ${t1%.*} - ${__dp_t0%.*} ))
    mkdir -p "$__dp_dir" 2>/dev/null
    print -r -- "{\"t\":${t1/./},\"cmd\":\"$__dp_cmd\",\"code\":$ec,\"dur\":$dur}" >| "$__dp_dir/buddy.json.$$" 2>/dev/null \
      && mv -f "$__dp_dir/buddy.json.$$" "$__dp_dir/buddy.json" 2>/dev/null
  fi
  __dp_cmd=""
  return $ec
}
add-zsh-hook preexec __dp_preexec
add-zsh-hook precmd __dp_precmd
