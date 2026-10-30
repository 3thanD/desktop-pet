# bash completion for desktop-pet
_desktop_pet() {
  local cur prev cmds pets accs
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[1]}"
  cmds="fetch buddy evolve new coffee size color setup uninstall status on off toggle pick list name feed heal wake accessory eat goblin-steal theme-pet poke say chat brain chatty persona forget config reset help slime cat dragon goblin"
  pets="slime cat dragon goblin"
  accs="auto none list shades visor retroshades glow crown leafhat pumpkin beanie mushroom halo flower bow moonstars scarf headband tie gem"
  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") ); return
  fi
  case "$prev" in
    pick) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "$pets" -- "$cur") ) ;;
    accessory) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "$accs" -- "$cur") ) ;;
    eat|goblin-steal) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "on off" -- "$cur") ) ;;
    brain)
      if (( COMP_CWORD == 2 )); then COMPREPLY=( $(compgen -W "on off context" -- "$cur") )
      elif [[ ${COMP_WORDS[2]} == context ]]; then COMPREPLY=( $(compgen -W "on off" -- "$cur") ); fi ;;
    chatty) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "off low normal high" -- "$cur") ) ;;
    persona) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "reset" -- "$cur") ) ;;
    color) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "theme complement custom" -- "$cur") ) ;;
    size) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "50 100 200" -- "$cur") ) ;;
    goblin) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "heist-now" -- "$cur") ) ;;
    poke) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "hungry fire heist" -- "$cur") ) ;;
    reset|new) COMPREPLY=( $(compgen -W "-y" -- "$cur") ) ;;
    setup) COMPREPLY=( $(compgen -W "-y --buddy" -- "$cur") ) ;;
    fetch|buddy) (( COMP_CWORD == 2 )) && COMPREPLY=( $(compgen -W "on off" -- "$cur") ) ;;
    evolve)
      if (( COMP_CWORD == 2 )); then COMPREPLY=( $(compgen -W "--preview --debug-set" -- "$cur") )
      elif (( COMP_CWORD == 3 )); then COMPREPLY=( $(compgen -W "baby teen adult elder" -- "$cur") )
      else COMPREPLY=( $(compgen -W "classic cyber chonk" -- "$cur") ); fi ;;
    uninstall) COMPREPLY=( $(compgen -W "--purge" -- "$cur") ) ;;
    theme-pet)
      if (( COMP_CWORD == 2 )); then
        COMPREPLY=( $(compgen -W "$(ls /usr/share/omarchy/themes ~/.config/omarchy/themes 2>/dev/null | grep -v : | sort -u)" -- "$cur") )
      else COMPREPLY=( $(compgen -W "$pets off" -- "$cur") ); fi ;;
  esac
}
complete -F _desktop_pet desktop-pet
