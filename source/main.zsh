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

  local MATCH
  local -i 10 MBEGIN MEND
  local -a match mbegin mend

  # ———————————————————————————————————————————————————————————————————— #

  local -ri 10 ROOT_FUNC_PID=$$
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

  local -i 10 TABSIZE=4
  local -i 2 mark_alias_r=1
  local -i 2 do_double_dash=1
  local -i 2 do_posix_for_if=1
  local -i 2 resolve_cmd_case=1

  local -i 2 do_colour=1
  local colour_arg='always'

  if [[ ! -t 1 || -z NO_COLOR ]] do_colour=0 colour_arg='never'

  # ———————————————————————————————————————————————— #

  local RESET DIM NODIM GRY DGY LGY LRD RED ORA YEL GRN CYN BLU PUR MAG LMA

  if (( do_colour )) {
    RESET=$'\e[m'   DIM=$'\e[2m'        NODIM=$'\e[22m'
    GRY=$'\e[2;97m' LGY=$'\e[38;5;103m' DGY=$'\e[38;5;240m'

    RED=$'\e[31m'
    LRD=$'\e[91m'
    ORA=$'\e[38;5;216m'
    YEL=$'\e[93m'
    GRN=$'\e[92m'
    CYN=$'\e[96m'
    BLU=$'\e[94m'
    PUR=$'\e[38;5;170m'
    MAG=$'\e[35m'
    LMA=$'\e[95m'
  }

  local -r RESWORD_CLR="$LMA" OPTIONS_CLR="$PUR"
  local -r BUILTIN_CLR="$LRD" COMMAND_CLR="$BLU"

  local -r COMMENT_CLR="$LGY" COMHASH_CLR="$DGY"

  local -r SGL_QU="$DIM$GRN'$RESET"
  local -r DBL_QU="$DIM$GRN\"$RESET"
  local -r DLR_QU="$DIM$GRN\$'$RESET"

  local -r COMMENT="$COMHASH_CLR#$COMMENT_CLR"

  local -r DISABLED_MSG="$RED${DIM}[$NODIM disabled $DIM]$RESET"
  local -r DISB_COMMENT="$COMHASH_CLR# $DISABLED_MSG"

  local -r   LOADED_MSG="$GRN$DIM(${NODIM}""loaded$DIM)$RESET"
  local -r UNLOADED_MSG="$YEL$DIM(${NODIM}unloaded$DIM)$RESET"

  local -r  SYMLINK_ARROW=" $GRY-->$RESET "
  local -r REALPATH_ARROW=" $BLU==>$RESET "

  local -r     LINE="$DIM${(r:COLUMNS  ::─:)}$RESET"
  local -r HALFLINE="$DIM${(r:COLUMNS/2::─:)}$RESET"
  local -r QUARLINE="$DIM${(r:COLUMNS/4::─:)}$RESET"

  # ———————————————————————————————————————————————— #

  local -r SP=' ' SQ=\' DQ=\"
  local -r NL=$'\n' HT=$'\t'
  local -r PRECMD='(-|builtin|command|exec|nocorrect|noglob)'

  local -ra COLOUR_PAGER=(
    bat --style=plain --paging=never --language=zsh --color="$colour_arg"
  )

  local -ra FILE_CMD=(
    file -E --dereference --brief --preserve-date
      --exclude=compress --exclude=tar --exclude=json --exclude=cdf
  )

  # ———————————————————————————————————————————————— #

  local -ra COMMAND_TYPES=(
    'Bourne-Again shell script *'     "$LRD"  '' 'bash script'
    'POSIX shell script *'            "$BLU"  '󱆃' 'bourne shell script'
    "Paul Falstad's zsh script *"     "$ORA"  '' 'zsh script'
    'Python script *'                 "$YEL"  '󰌠' 'python script'
    'Perl script *'                   "$CYN"  '' 'perl script'

    'a (*) script text executable *'  "$MAG"  '' '$match[1] script'

    'Mach-O 64-bit executable *'      "$RED"  '' 'mach-o binary'
    'Mach-O universal binary with *'  "$LRD"  '' 'multi-arch binary'
    '*'                               "$GRN"  '' 'binary executable'
  )

  # ———————————————————————————————————————————————————————————————————— #
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
  local type dir
  for type in "${(@)SEARCH_ORDER}"; {
    if [[ $type == 'commands' ]] {
      # for commands, we can't just check the assoc, because it doesn't work
      #  case-insensitively - e.g. if `$input = LS`, we need to match `/bin/ls`
      # therefore, we have to manually go through every path in `$path`,
      #  and check whether a path to the executable exists
      for dir in "${(@)path}"; { # stop searching after the first match
        if [[ -e $dir/$input ]] { types+="$type"; break 1; }
      }
    } elif [[ ${(Pt)type} == *association* ]] {
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

  if [[ $alias_body ==
    [[:space:]]#(${~PRECMD}[[:space:]]##|)(#b)((=|)[[:IDENT:]]##)[[:space:]]#
    && ${match[1]#=} != $input
  ]] is_simple=1

  # ———————————————————————————————————————————————————————————————————— #

  local line="${RESWORD_CLR}alias "
  local opts_str=

  if [[ $alias_type == [gs] ]] { opts_str+="-$alias_type " } \
  elif (( mark_alias_r ))      { opts_str+="-r "           }

  if [[ $do_double_dash -ne 0 && $input[1] == '-' ]] line+="$OPTIONS_CLR-- "

  if [[ -n $opts_str ]] line+="$OPTIONS_CLR$opts_str"

  line+="$COMMAND_CLR$input$CYN="

  # ———————————————————————————————————————————————— #

  line+="$quote$(
    "${(@z)COLOUR_PAGER}" <<< "$alias_body"
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
  local -a func_lines=( "${(@f)${(P)type}[$input]}" )

  # ———————————————————————————————————————————————— #

  local redirect=

  if [[ $func_lines[+1] == '{' && $func_lines[-1] == '}'* ]] {
    redirect="${func_lines[-1]#\} }"
    shift    func_lines
    shift -p func_lines
  }

  # ———————————————————————————————————————————————— #

  func_lines=(
    "${(@)func_lines/#(#m)$HT#/${(r.( $#MATCH ? $#MATCH : 1 ) * TABSIZE.)}}"
  )

  # ———————————————————————————————————————————————— #

  local body="${(F)func_lines}"

  if (( do_posix_for_if )) {
    body="${body//$NL$SP#(#b)(then|do)$NL/; $match[1]$NL}"
  } else {
    body="${body//$NL$SP#then$NL/ {$NL}"
    body="${body//$NL$SP#do$NL/; {$NL}"

    body="${body//$NL(#b)($SP#)(fi|done)($NL|(#e))/$NL$match[1]\}$NL}"
    body="${body//$NL(#b)($SP#)elif/$NL$match[1]\} elif}"
    body="${body//$NL(#b)($SP#)else/$NL$match[1]\} else {}"
  }

  # ———————————————————————————————————————————————— #

  local func_source="${${(P)${type/%/_source}}[$input]}"

  # if `func_source` is empty, it's likely an autoloaded function
  if [[ -z $func_source ]] {
    local _path # go fish !!
    for _path in "${(@)fpath}"; {
      if [[ -f "$_path/$input" ]] {
        func_source="$_path/$input"
        break  # stop searching at the first match
      }
    }
    # if we _still_ couldn't find anything, just use an appropriate default
    if [[ -z $func_source ]] func_source='autoload shell function'
  }

  # ———————————————————————————————————————————————————————————————————— #

  local line="${RESWORD_CLR}function "
  local opts_str=

  if [[ "$( typeset -f -- "$input" )" ==
    [^$NL]##${NL}[[:space:]]#'# traced'$NL*
  ]] opts_str+='-T '

  if [[ $do_double_dash -ne 0 && $input[1] == '-' ]] opts_str+='-- '

  if [[ -n $opts_str ]] line+="$OPTIONS_CLR$opts_str"

  # ———————————————————————————————————————————————— #

  line+="$COMMAND_CLR$input$RED () {"
  if (( is_disabled )) line+="  $DISB_COMMENT"

  line+="$RESET$NL$( "${(@z)COLOUR_PAGER}" <<< "$body" )$NL"
  line+="$RED}$RESET"

  if [[ -n $redirect ]] line+=" $( "${(@z)COLOUR_PAGER}" <<< "$redirect" )"

  output_lines+="$COMMENT ${func_source/#$HOME/~}$RESET"
  output_lines+="$line"
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
  local dir cmd_path
  local -a match_arr magic_arr path_match

  for dir in "${(@)path}"; {
    if ! [[ -e "$dir/$input" ]] continue

    cmd_path="$dir/$input"

    if (( resolve_cmd_case )) {
      path_match=( (#i)$cmd_path(DN) )
      if ! (( $#path_match == 1 )) whh::error mult-cmd

      cmd_path="$path_match[1]"
    }

    match_arr+="$cmd_path"
    magic_arr+="$( "${(@z)FILE_CMD}" -- "$cmd_path" )"
  }

  # ———————————————————————————————————————————————— #

  local -i 10 i
  local -a links
  local -i 2 is_exe
  local target magic_out line realpath fmt_path

  for cmd_path magic_out in "${(@)match_arr:^magic_arr}"; {

    target="$cmd_path" line= links=()

    while [[ -h $target ]] {
      target="$( readlink "$target" )" || break
      links+="$target"
    }

    # ———————————————————————————————————————————————— #

    fmt_path="$cmd_path" is_exe=$(( $#links == 0 ))
    whh::format_path

    if (( $#links )) {
      for i in {1..$#links}; {
        line+="$SYMLINK_ARROW"

        fmt_path="$links[i]" is_exe=$(( i == $#links ))
        whh::format_path
      }
    }

    # ———————————————————————————————————————————————— #

    realpath="$( realpath -q "$cmd_path" )"

    if [[ -n "$links" && "$realpath" != "$links[-1]" ]] {
      line+="$NL$REALPATH_ARROW"

      fmt_path="$realpath" is_exe=1
      whh::format_path
    }

    # ———————————————————————————————————————————————— #

    whh::parse_magic
    output_lines+="$line"

    if [[ $cmd_path != $match_arr[-1] ]] output_lines+=$HALFLINE

    # ———————————————————————————————————————————————— #
  }
}

# —— whh::parse_magic () ———————————————————————————————————————————————————— #

function whh::parse_magic () { # <- whh::commands <- whh::process_input <- whh
  local pattern prefix colour icon cmd_type

  for pattern colour icon cmd_type in "${(@)COMMAND_TYPES}"; {
    if [[ "$magic_out" != $~pattern ]] continue

    prefix="$colour$icon${colour:+$RESET}"

    eval "output_lines+='$prefix '\"$cmd_type\""
    return
  }
}

# —— whh::format_path () ———————————————————————————————————————————————————— #

function whh::format_path () { # <- whh::commands <- whh::process_input <- whh
  line+="$CYN${${fmt_path/#$HOME/~}%/*}/"

  if (( is_exe )) { line+="$RED" } else { line+="$MAG" }

  line+="${fmt_path##*/}$RESET"
}

# ——————————————————————————————————————————————————————————————————————————— #
# —— whh::error () —————————————————————————————————————————————————————————— #

function whh::error () { # <- ... <- whh
  local err=
  case "$1" {
    ( mult-cmd  ) err="multiple commands found: ${(j:,:)path_match}" ;;
    ( type-err  ) err="unknown type \`${type/%(e|)s}\`" ;;
    ( no-input  ) err='must provide an input'           ;;
    ( not-found ) err="\`$input\` not found"            ;;
    ( *         ) err="$*"                              ;;
  }

  echo -E - "$RED$ROOT_FUNCNAME$RESET: $err"

  return 0  # this function should always return success
} >&2  # everything this function outputs should go to `stderr`

# ——————————————————————————————————————————————————————————————————————————— #
# ——————————————————————————————————————————————————————————————————————————— #

# spell:ignoreRegexp /[gs]aliases\b/g
# spell:ignore nodim disb mult
