# desktop-pet build buddy hook for bash (installed by `desktop-pet setup --buddy`).
# After each command it records ONLY the command's name (plus "push"/"test" for
# git/cargo/npm/go/make/yarn/pnpm), its exit code and duration, overwriting
# $XDG_RUNTIME_DIR/desktop-pet/buddy.json. No arguments, paths or output.
[[ $- == *i* ]] || return 0
[[ -n ${__dp_buddy_loaded:-} ]] && return 0
__dp_buddy_loaded=1
__dp_dir="${XDG_RUNTIME_DIR:-/tmp}/desktop-pet"

__dp_name() {  # $1 = full command line -> safe short name
  local -a w; read -r -a w <<< "$1"
  local c="${w[0]##*/}" s="${w[1]:-}"
  [[ $c == sudo || $c == time || $c == command ]] && { c="${w[1]##*/}"; s="${w[2]:-}"; }
  case "$c:$s" in
    git:push|cargo:test|npm:test|go:test|make:test|yarn:test|pnpm:test|bun:test) printf '%s %s' "$c" "$s" ;;
    *) printf '%s' "${c//[^A-Za-z0-9._+-]/}" ;;
  esac
}

__dp_preexec() {
  [[ -n ${COMP_LINE:-} || -n ${__dp_cmd:-} ]] && return
  [[ $BASH_COMMAND == __dp_* || $BASH_COMMAND == "$PROMPT_COMMAND" ]] && return
  __dp_cmd=$(__dp_name "$BASH_COMMAND")
  __dp_t0=${EPOCHREALTIME:-$SECONDS}
}

__dp_precmd() {
  local ec=$?
  if [[ -n ${__dp_cmd:-} ]]; then
    local t1=${EPOCHREALTIME:-$SECONDS} dur
    dur=$(( ${t1%.*} - ${__dp_t0%.*} ))
    mkdir -p "$__dp_dir" 2>/dev/null
    printf '{"t":%s,"cmd":"%s","code":%d,"dur":%d}\n' "${t1/./}" "$__dp_cmd" "$ec" "$dur" > "$__dp_dir/buddy.json.$$" 2>/dev/null \
      && mv -f "$__dp_dir/buddy.json.$$" "$__dp_dir/buddy.json" 2>/dev/null
  fi
  __dp_cmd=
  return $ec
}

if declare -p preexec_functions &>/dev/null; then   # bash-preexec is loaded
  preexec_functions+=(__dp_preexec_bp); precmd_functions+=(__dp_precmd)
  __dp_preexec_bp() { BASH_COMMAND="$1" __dp_preexec; }
elif [[ -z $(trap -p DEBUG) ]]; then
  trap '__dp_preexec' DEBUG
  PROMPT_COMMAND="__dp_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
