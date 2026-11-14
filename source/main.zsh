#!/usr/bin/env zsh

# ——————————————————————————————————————————————————————————————————————————— #

zmodload zsh/parameter

# -w For each name, print `name: word` where word is one of
#    alias, builtin, command, function, hashed, reserved or
#    none, according as name corresponds to an alias, a
#    built-in command, an external command, a shell function,
#    a ```command defined with the hash builtin```, a reserved word,
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
    commands  # todo: add a contingency for unix's case-insensitive behaviour
  )

  # ———————————————————————————————————————————————— #

  local -ra inputs=( "$@" )
  if ! (( $#inputs )) whh::error no-input && return 1

  # ———————————————————————————————————————————————— #

  local -i 2 do_colour=1
  if [[ ! -t 1 || -v NO_COLOR ]] do_colour=0

  # ———————————————————————————————————————————————— #

  local input= output=
  for input in "${(@)inputs}"; whh::process_input

  # ———————————————————————————————————————————————— #

  if [[ -n "$output" ]] echo -E - "$output"
}

# ——————————————————————————————————————————————————————————————————————————— #
# —— whh::process_input () —————————————————————————————————————————————————— #

function whh::process_input () { # <- whh
  local -a types=() output_lines=()
  whh::find_types

  if ! (( $#types )) whh::error not-found && return  # move on to next input

  # ———————————————————————————————————————————————— #

  local type type_func
  for type in "${(@)types}"; {

    # remove the `dis_` from the start of `$type`
    type_func="${type#dis_}"
    # all alias types will share the same function
    if [[ $type_func == [gs]aliases ]] type_func="${type_func#?}"

    # prepend the namespace prefix to the type_func
    type_func="whh::$type_func"

    # if `whh::$type_func` isn't a function, then something's gone wrong
    #  this should basically never run, but it's here as a backup
    if ! [[ $functions[(Ie)$type_func] ]] whh::error type-err && continue

    "$type_func"  # run the function associated with this type
  }

  # ———————————————————————————————————————————————— #

  output+="${(F)output_lines}"
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
# —— whh::aliases ——————————————————————————————————————————————————————————— #

function whh::aliases () { # <- whh::process_input <- whh
}

# —— whh::reswords —————————————————————————————————————————————————————————— #

function whh::reswords () { # <- whh::process_input <- whh
}

# —— whh::functions ————————————————————————————————————————————————————————— #

function whh::functions () { # <- whh::process_input <- whh
}

# —— whh::builtins —————————————————————————————————————————————————————————— #

function whh::builtins () { # <- whh::process_input <- whh
}

# —— whh::commands —————————————————————————————————————————————————————————— #

function whh::commands () { # <- whh::process_input <- whh
}

# ——————————————————————————————————————————————————————————————————————————— #
# —— whh::error () —————————————————————————————————————————————————————————— #

function whh::error () { # <- ... <- whh
  local err=
  case "$1" {
    ( no-input  ) err='must provide an input'           ;;
    ( not-found ) err="\`$input\` not found"            ;;
    ( type-err  ) err="unknown type \`${type/%(e|)s}\`" ;;
    ( *         ) err='unknown error'                   ;;
  }

  echo -E - $'\e[31m'"$ROOT_FUNCNAME"$'\e[m'": $err"

  return 0  # this function should always return success
} >&2  # everything this function outputs should go to `stderr`

# ——————————————————————————————————————————————————————————————————————————— #
# ——————————————————————————————————————————————————————————————————————————— #

# spell:ignoreRegexp /[gs]aliases\b/g
