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

  setopt local_options warn_create_global typeset_silent
  setopt extended_glob

  local -a match mbegin mend

  # ———————————————————————————————————————————————————————————————————— #

  local -r ROOT_FUNCNAME="${(%):-%N}"

  local -ra SEARCH_ORDER=(
    aliases     dis_aliases
    galiases    dis_galiases
    saliases    dis_saliases

    reswords    dis_reswords    # arrays
    functions   dis_functions   # functions_source  dis_functions_source
    builtins    dis_builtins
    commands  # todo: add a contingency for unix's case-insensitive behaviour
  )

  # ———————————————————————————————————————————————————————————————————— #

  local -i 2 mark_alias_r=1

  local -i 2 do_colour=1
  local colour_arg='always'

  if [[ ! -t 1 || -z NO_COLOR ]] do_colour=0 colour_arg='never'

  # ———————————————————————————————————————————————— #

  local RESET DIM NODIM RED ORA YEL GRN CYN
  local {BUILTIN,OPTIONS,COMMAND,RESWORD}_CLR

  if (( do_colour )) {
    RESET=$'\e[m' DIM=$'\e[2m' NODIM=$'\e[22m'
    RED=$'\e[31m'
    ORA=$'\e[38;5;216m'
    YEL=$'\e[93m'
    GRN=$'\e[92m'
    CYN=$'\e[96m'

    RESWORD_CLR=$'\e[95m'
    OPTIONS_CLR=$'\e[38;5;170m'
    BUILTIN_CLR=$'\e[91m'
    COMMAND_CLR=$'\e[94m'
  }

  local -r SP=' ' SQ=\' DQ=\"
  local -r PRECMD_PAT='(-|builtin|command|exec|nocorrect|noglob)'

  local -r SGL_QU="$DIM$GRN'$RESET"
  local -r DBL_QU="$DIM$GRN\"$RESET"
  local -r DLR_QU="$DIM$GRN\$'$RESET"

  local -r DISABLED_MSG="$RED${DIM}[$NODIM disabled $DIM]$RESET"

  local -r   LOADED_MSG="$GRN$DIM(${NODIM}""loaded$DIM)$RESET"
  local -r UNLOADED_MSG="$YEL$DIM(${NODIM}unloaded$DIM)$RESET"

  local -r     LINE="$DIM${(r:COLUMNS  ::─:)}$RESET"
  local -r HALFLINE="$DIM${(r:COLUMNS/2::─:)}$RESET"

  # ———————————————————————————————————————————————————————————————————— #

  local -ra inputs=( "$@" )
  if ! (( $#inputs )) whh::error no-input && return 1

  # ———————————————————————————————————————————————— #

  local input= output=
  for input in "${(@)inputs}"; whh::process_input

  # ———————————————————————————————————————————————————————————————————— #

  if [[ -n "$output" ]] echo -E - "$output"
}

# ——————————————————————————————————————————————————————————————————————————— #
# —— whh::process_input () —————————————————————————————————————————————————— #

function whh::process_input () { # <- whh
  local -a types=() output_lines=()
  whh::find_types

  if ! (( $#types )) whh::error not-found && return  # move on to next input

  # ———————————————————————————————————————————————— #

  output_lines+="$HALFLINE"  # add an initial dividing line

  # ———————————————————————————————————————————————— #

  local -i 2 is_disabled=0
  local type type_func disabled_msg

  for type in "${(@)types}"; {
    is_disabled=0 disabled_msg=
    type_func="$type"

    if [[ $type == dis_* ]] {
      is_disabled=1 disabled_msg="$DISABLED_MSG"  # mark the input as disabled
      # remove the `dis_` from the start of `$type`
      type_func="${type_func#dis_}"
    }

    # all alias types will share the same function
    if [[ $type_func == [gs]aliases ]] type_func="${type_func#?}"

    # prepend the namespace prefix to the type_func
    type_func="whh::$type_func"

    # if `whh::$type_func` isn't a function, then something's gone wrong
    #  this should basically never run, but it's here as a backup
    if ! [[ $functions[(Ie)$type_func] ]] whh::error type-err && continue

    # ——————————————————————————————————— #

    "$type_func"  # run the function associated with this type
    output_lines+="$HALFLINE"  # add a dividing line
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
  local -r alias_type="${${type#dis_}[1]}"
  local -r alias_body="${${(P)type}[$input]}"

  # ———————————————————————————————————————————————— #

  # TODO: improve - it isn't great, but it'll do for now
  local quote
  if   [[ $alias_body == *$SQ* ]] { quote="$DBL_QU" } \
  elif [[ $alias_body == *$DQ* ]] { quote="$SGL_QU" } \
  elif [[ $alias_body == *$SP* ]] { quote="$SGL_QU" } \
  else                            { quote=          }

  # ———————————————————————————————————————————————— #

  # TODO: implement
  local -i 2 is_simple=0

  if [[ "$alias_body" ==
    [[:space:]]#(${~PRECMD_PAT}[[:space:]]##|)(#b)([[:IDENT:]]##)[[:space:]]#
  ]] is_simple=1

  # ———————————————————————————————————————————————————————————————————— #

  local line="${RESWORD_CLR}alias "

  if [[ $alias_type == [gs] ]] { line+="$OPTIONS_CLR-$alias_type " } \
  elif (( mark_alias_r ))      { line+="$OPTIONS_CLR-r "           }

  line+="$COMMAND_CLR$input$CYN="

  # ———————————————————————————————————————————————— #

  line+="$quote$(
    bat --style=plain --paging=never --language=zsh --color=$colour_arg \
      <<< "$alias_body"
  )$quote"

  # ———————————————————————————————————————————————————————————————————— #

  output_lines+="$line $disabled_msg"
}

# —— whh::reswords —————————————————————————————————————————————————————————— #

function whh::reswords () { # <- whh::process_input <- whh
  output_lines+="$RESWORD_CLR$input$RESET : shell reserved word $disabled_msg"
}

# —— whh::functions ————————————————————————————————————————————————————————— #

function whh::functions () { # <- whh::process_input <- whh
}

# —— whh::builtins —————————————————————————————————————————————————————————— #

function whh::builtins () { # <- whh::process_input <- whh
  local -r line="$BUILTIN_CLR$input$RESET : shell builtin"

  local load_msg="$LOADED_MSG"
  if [[ "${${(P)type}[$input]}" == 'undefined' ]] load_msg="$UNLOADED_MSG"

  output_lines+="$line $load_msg $disabled_msg"
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

  echo -E - "$RED$ROOT_FUNCNAME$RESET: $err"

  return 0  # this function should always return success
} >&2  # everything this function outputs should go to `stderr`

# ——————————————————————————————————————————————————————————————————————————— #
# ——————————————————————————————————————————————————————————————————————————— #

# spell:ignoreRegexp /[gs]aliases\b/g
# spell:ignore nodim
