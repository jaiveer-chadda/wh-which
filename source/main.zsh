#!/usr/bin/env zsh

# ——————————————————————————————————————————————————————————————————————————— #

zmodload zsh/parameter

# -w For each name, print `name: word` where word is one of
#    alias, builtin, command, function, hashed, reserved or
#    none, according as name corresponds to an alias, a
#    built-in command, an external command, a shell function,
#    a command defined with the hash builtin, a reserved word,
#    or is not recognised.

# ——————————————————————————————————————————————————————————————————————————— #
# —— Main Entry Point ——————————————————————————————————————————————————————— #

function whh () {

  setopt local_options warn_create_global

  # ———————————————————————————————————————————————— #

  local -r ROOT_FUNCNAME="${(%):-%N}"

  local -ra SEARCH_ORDER=(
    aliases     dis_aliases
    galiases    dis_galiases
    saliases    dis_saliases

    reswords    dis_reswords
    functions   dis_functions   # functions_source  dis_functions_source
    builtins    dis_builtins
    commands
  )

  # ———————————————————————————————————————————————— #

  local -ra inputs=( "$@" )

  local input
  for input in "${(@)inputs}"; whh::process_input
}

# ——————————————————————————————————————————————————————————————————————————— #
# —— whh::process_input () —————————————————————————————————————————————————— #

function whh::process_input () { # <- whh
  local -a types=()
  whh::find_types

  if ! (( $#types )) whh::error not-found && return  # move on to next input

  print -l $types
}

# —— whh::find_types () ————————————————————————————————————————————————————— #

function whh::find_types () { # <- whh::process_input <- whh
  # check if the input is each of the the associative/regular arrays
  #  - for assoc   arrays, we need to check that the match's strlen isn't 0
  #  - for regular arrays, we need to check that the match's index  isn't 0
  local type
  for type in "${(@)SEARCH_ORDER}"; {
    if [[ ${(Pt)type} == *association* ]] {
      if [[ ${${(P)type}[(Ie)$input]} ]] types+="$type"
    } else {
      if (( ${${(P)type}[(Ie)$input]} )) types+="$type"
    }
  }
}

# ——————————————————————————————————————————————————————————————————————————— #
# —— whh::error () —————————————————————————————————————————————————————————— #

function whh::error () { # <- ... <- whh
  local error="$1"
  echo -nE - $'\e[31m'"$ROOT_FUNCNAME"$'\e[m: '

  case "$error" {
    ( no-input  ) echo -E - "\`$input\` not found" ;;
    ( not-found ) echo -E - "\`$input\` not found" ;;
    ( *         ) echo -E - "unknown error"        ;;
  }

} >&2

# ——————————————————————————————————————————————————————————————————————————— #
