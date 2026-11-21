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
# ── ─── Main Entry Point ─── ───────────────────────────────────────────────── #

function whh () {

  # —— init & set shell options ———————————————————————————————————————— #

  setopt local_options warn_create_global typeset_silent
  setopt extended_glob

  local MATCH
  local -i 10 MBEGIN MEND
  local -a match mbegin mend

  local -r ROOT_FUNCNAME="${(%):-%N}"

  # —— user options ———————————————————————————————————————————————————— #

  # TODO: implement a `getopts` loop to set these values
  local -i 10 TABSIZE=4
  local -i 2 mark_alias_r=1
  local -i 2 do_double_dash=1
  local -i 2 do_posix_for_if=1
  local -i 2 resolve_cmd_case=1

  local -i 2 do_colour=1
  local colour_arg='always'

  if [[ ! -t 1 || -z NO_COLOR ]] do_colour=0 colour_arg='never'

  # —— base colour definitions ————————————————————— #

  local RESET DIM NODIM UDL NOUDL
  local GRY DGY LGY LRD RED ORA YEL GRN LCY CYN BLU LBL PUR MAG LMA

  if (( do_colour )) {
    RESET=$'\e[m'
    DIM=$'\e[2m' NODIM=$'\e[22m'
    UDL=$'\e[4m' NOUDL=$'\e[24m'

    GRY=$'\e[2;97m' LGY=$'\e[38;5;103m' DGY=$'\e[38;5;240m'

    RED=$'\e[31m'
    LRD=$'\e[91m'
    ORA=$'\e[38;5;216m'
    YEL=$'\e[93m'
    GRN=$'\e[92m'
    CYN=$'\e[36m'
    LCY=$'\e[96m'
    BLU=$'\e[34m'
    LBL=$'\e[94m'
    PUR=$'\e[38;5;170m'
    MAG=$'\e[35m'
    LMA=$'\e[95m'
  }

  # —— colour & graphical definitions —————————————— #

  local -r RESWORD_CLR="$LMA" OPTIONS_CLR="$PUR"
  local -r BUILTIN_CLR="$LRD" COMMAND_CLR="$LBL"
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
  local -r REALPATH_ARROW=" $MAG==>$RESET "

  local -r     LINE="$DIM${(r:COLUMNS  ::─:)}$RESET"
  local -r HALFLINE="$DIM${(r:COLUMNS/2::─:)}$RESET"
  local -r QUARLINE="$DIM${(r:COLUMNS/4::─:)}$RESET"

  # —— convenience constants ——————————————————————— #

  local -r SP=' ' SQ=\' DQ=\"
  local -r NL=$'\n' HT=$'\t'

  # —— parsing & pattern definitions ——————————————— #

  local -ra SEARCH_ORDER=(
    aliases     dis_aliases
    galiases    dis_galiases
    saliases    dis_saliases

    reswords    dis_reswords  # note: these are the only two arrays
    functions   dis_functions # sources: functions_source, dis_functions_source
    builtins    dis_builtins
    commands
  )

  local -r PRECMD='(-|builtin|command|exec|nocorrect|noglob)'

  local -ra COMMAND_TYPES=(
    'Bourne-Again shell script *'     "$RED"  '' 'bash script'
    'POSIX shell script *'            "$BLU"  '󱆃' 'bourne shell script'
    "Paul Falstad's zsh script *"     "$ORA"  '' 'zsh script'
    'Python script *'                 "$YEL"  '󰌠' 'python script'
    'Perl script *'                   "$LCY"  '' 'perl script'

    'a (*) script text executable *'  "$MAG"  '' '$match[1] script'

    'Mach-O 64-bit executable *'      "$LRD"  '' 'mach-o binary'
    'Mach-O universal binary with *'  "$PUR"  '' 'multi-arch binary'
    '*'                               "$GRN"  '' 'binary executable'
  )

  # —— external command definitions ———————————————— #

  local -ra COLOUR_PAGER=(
    bat --style=plain --paging=never --language=zsh --color="$colour_arg"
  )

  local -ra FILE_CMD=(
    file -E --dereference --brief --preserve-date
      --exclude=compress --exclude=tar --exclude=json --exclude=cdf
  )

  # —— ————————————————————————————————————————————————————————————————— #
  # —— parse & process inputs —————————————————————————————————————————— #

  local -ra inputs=( "$@" )
  if ! (( $#inputs )) wh::error no-input && return 1

  local input= output=
  for input in "${(@)inputs}"; wh::process_input

  # —— output & return ————————————————————————————————————————————————— #

  if [[ -n "$output" ]] echo -E - "$output"

  return 0

  # ———————————————————————————————————————————————————————————————————— #
}

# ——————————————————————————————————————————————————————————————————————————— #
# ── ── process_input () ── ───────────────────────────────────────────────── #

function wh::process_input () { # <- wh

  # —— find applicable types ——————————————————————— #

  local -a types=() output_lines=()
  wh::process_input::find_types

  if ! (( $#types )) wh::error not-found && return  # move on to next input

  # ———————————————————————————————————————————————— #

  output_lines+="$HALFLINE"  # add an initial dividing line

  # —— determine type categories ——————————————————— #

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
    type_func="wh::$type_func"

    # if `wh::$type_func` isn't a function, then something's gone wrong
    #  this should basically never run, but it's here as a backup
    if ! [[ $functions[(Ie)$type_func] ]] wh::error type-err && continue

    # —— send input for processing —————— #

    "$type_func"  # run the function associated with this type
    output_lines+="$HALFLINE"  # add a dividing line
  }

  # —— output & return ————————————————————————————— #

  output+="${(F)output_lines}"
}

# —— process_input::find_types () ——————————————————————————————————————————— #

function wh::process_input::find_types () { # <- wh::process_input <- wh
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
# ── ── aliases () ── ─────────────────────────────────────────────────────── #

function wh::aliases () { # <- wh::process_input <- wh

  # —— format input ———————————————————————————————— #

  local -r alias_type="${${type#dis_}[1]}"
  local -r alias_body="${${(P)type}[$input]}"

  # —— determine quoting rules ————————————————————— #

  # TODO: improve - it isn't great, but it'll do for now
  local quote
  case "$alias_body" {
    ( *"$SQ"* ) quote="$DBL_QU" ;;
    ( *"$DQ"* ) quote="$SGL_QU" ;;
    ( *"$SP"* ) quote="$SGL_QU" ;;
    ( *       ) quote=          ;;
  }

  # —— find exact aliases —————————————————————————— #

  # TODO: implement
  local -i 2 is_simple=0

  if [[ $alias_body ==
    [[:space:]]#(${~PRECMD}[[:space:]]##|)(#b)((=|)[[:IDENT:]]##)[[:space:]]#
      && ${match[1]#=} != $input
  ]] is_simple=1

  # —— set --options ——————————————————————————————————————————————————— #

  local line="${RESWORD_CLR}alias "
  local opts_str=

  # if the alias is global or suffixed, then add the options unconditionally
  if [[ $alias_type == [gs] ]] { opts_str+="-$alias_type " } \
  elif (( mark_alias_r ))      { opts_str+="-r "           }
  # if it's a normal alias, then (based on the user's choice), add the `-r` opt

  # if the alias' name starts with a hyphen
  #  then it'd have to be defined as `alias -- -name`
  if [[ $do_double_dash -ne 0 && $input[1] == '-' ]] line+="$OPTIONS_CLR-- "

  # only add the options colour if the options string is actually defined
  line+="${opts_str:+$OPTIONS_CLR$opts_str}"

  # `name` and `=` in `alias -- name=def`
  line+="$COMMAND_CLR$input$LCY="

  # —— syntax highlighting ————————————————————————— #

  # pass the entire alias body straight to `bat` - it'll highlight everything
  line+="$quote$(
    "${(@z)COLOUR_PAGER}" <<< "$alias_body"
  )$quote"

  if (( is_simple )) line+=' !'

  # —— output & return ————————————————————————————————————————————————— #

  # if the alias is disabled, add a warning after the alias' body
  output_lines+="$line $disabled_msg"

  # ———————————————————————————————————————————————————————————————————— #
}

# ——————————————————————————————————————————————————————————————————————————— #
# ── ── reswords () ── ────────────────────────────────────────────────────── #

function wh::reswords () { # <- wh::process_input <- wh
  output_lines+="$RESWORD_CLR$input$RESET : shell reserved word $disabled_msg"
}

# ——————————————————————————————————————————————————————————————————————————— #
# ── ── functions () ── ───────────────────────────────────────────────────── #

function wh::functions () { # <- wh::process_input <- wh

  # —— format input ———————————————————————————————— #

  # get the function body from the assoc array (`functions` / `dis_functions`)
  #  and split it by line
  local -a func_lines=( "${(@f)${(P)type}[$input]}" )

  # —— parse function redirect ————————————————————— #

  local redirect=

  # if the function is entirely defined in a group with a redirect
  #  i.e. `function name () { ... } >&2`
  if [[ $func_lines[+1] == '{' && $func_lines[-1] == '}'* ]] {
    # then capture the redirect (so we can add it back later)
    redirect="${func_lines[-1]#\} }"
    # and remove the outer `{` group `}` (remove the first and last lines)
    shift    func_lines
    shift -p func_lines
  }

  # —— replace tabs w spaces ——————————————————————— #

  # match any (or 0) tabs at the beginning of each line
  #  however many tabs we captured, replace them with `$TABSIZE` spaces
  # at a minimum, if we don't capture anything (`$#MATCH == 0`), add `1` tab
  func_lines=(
    "${(@)func_lines/#(#m)$HT#/${(r.( $#MATCH ? $#MATCH : 1 ) * TABSIZE.)}}"
  )

  # —— prettify for / if statements ———————————————— #

  # re-join the lines into one big string
  local body="${(F)func_lines}"

  # if using POSIX-style if/for/while/etc statements...
  if (( do_posix_for_if )) {
    # simply replace `then`/`do` at the beginning of a line with `; then/do`
    body="${body//$NL$SP#(#b)(then|do)$NL/; $match[1]$NL}"

  } else {
    # if, however, we're using zsh's short loops, then:
    # replace `then` with `{` and `for` with `; {`
    body="${body//$NL$SP#then$NL/ {$NL}"
    body="${body//$NL$SP#do$NL/; {$NL}"

    # add brackets to all the `if` / `elif` / `else` statements
    body="${body//$NL(#b)($SP#)(fi|done)($NL|(#e))/$NL$match[1]\}$NL}"
    body="${body//$NL(#b)($SP#)elif/$NL$match[1]\} elif}"
    body="${body//$NL(#b)($SP#)else/$NL$match[1]\} else {}"

    # note: the reason short loops aren't the default is because
    #  `bat` isn't able to parse them correctly
  }

  # —— find function source ———————————————————————— #

  # add `_source` to the end of the array's name
  #  (i.e. `dis_functions` --> `dis_functions_source`)
  # then get the name of the current function from the assoc array
  local func_source="${${(P)${type/%/_source}}[$input]}"

  # if `func_source` is empty, it's likely an autoloaded function
  if [[ -z $func_source ]] {
    local _path # go fish !!

    # look through all function paths for a file matching this function's name
    for _path in "${(@)fpath}"; {
      if [[ -f "$_path/$input" ]] {
        func_source="$_path/$input"
        break  # stop searching at the first match
      }
    }

    # if we _still_ couldn't find anything, just use an appropriate default
    if [[ -z $func_source ]] func_source='autoload shell function'
  }

  # —— set --options ——————————————————————————————————————————————————— #

  local line="${RESWORD_CLR}function "
  local opts_str=

  # get the function body using `typeset -f`
  #  ignore the body's first line (`[^$NL]##${NL}`)
  # if the second line contains `# traced`, then we know this function has `-T`
  # INFO: afaik, this is the only reliable way to tell if a function is traced
  if [[ "$( typeset -f -- "$input" )" ==
    [^$NL]##${NL}[[:space:]]#'# traced'$NL*
  ]] opts_str+='-T '

  # if the function's name starts with a hyphen
  #  then it'd have to be defined as `function -- -name () { ... }`
  if [[ $do_double_dash -ne 0 && $input[1] == '-' ]] opts_str+='-- '

  # only add the options colour if the options string is actually defined
  line+="${opts_str:+$OPTIONS_CLR$opts_str}"

  # —— colourise & assemble ———————————————————————— #

  # `function -T --` has been added so far
  #  now add `funcname () {`
  line+="$COMMAND_CLR$input$RED () {"
  # if the function is disabled, add a comment after the opening bracket
  if (( is_disabled )) line+="  $DISB_COMMENT"

  # pass the (majority of the) function body to `bat` for highlighting
  line+="$RESET$NL$( "${(@z)COLOUR_PAGER}" <<< "$body" )$NL"
  line+="$RED}$RESET" # add the closing `}`

  # if we captured a redirect earlier, add it to the end of the function body,
  #  using `bat` to highlight any tokens
  if [[ -n $redirect ]] line+=" $( "${(@z)COLOUR_PAGER}" <<< "$redirect" )"

  # —— output & return ————————————————————————————— #

  # add the function's source path as a comment before the body
  output_lines+="$COMMENT ${func_source/#$HOME/~}$RESET"
  # then output the "line" (which isn't actually a single line but ykwim)
  output_lines+="$line"

  # ———————————————————————————————————————————————— #
}

# ——————————————————————————————————————————————————————————————————————————— #
# ── ── builtins () ── ────────────────────────────────────────────────────── #

function wh::builtins () { # <- wh::process_input <- wh
  local -r line="$BUILTIN_CLR$input$RESET : shell builtin"

  # add an extra message to the end of the builtin's name to specify whether
  #  it's a loaded/unloaded builtin (zsh calls these `defined` / `undefined`)
  local load_msg="$LOADED_MSG"
  if [[ "${${(P)type}[$input]}" == 'undefined' ]] load_msg="$UNLOADED_MSG"

  # add the disabled message at the end (if applicable)
  output_lines+="$line $load_msg $disabled_msg"
}

# ——————————————————————————————————————————————————————————————————————————— #
# ── ── commands () ── ────────────────────────────────────────────────────── #

function wh::commands () { # <- wh::process_input <- wh

  # —— parse $PATH for matches ————————————————————— #

  local dir cmd_path
  local -a match_arr magic_arr path_match

  # iterate through `$path` ( ≈ `$PATH`), trying to find each occurrence
  #  of the input name in those directories
  for dir in "${(@)path}"; {
    # if it doesn't exist, move on & keep searching
    if ! [[ -e "$dir/$input" ]] continue

    cmd_path="$dir/$input"

    # since macos uses unix's case-insensitive but case-preserving file naming
    #  conventions, an input of `cLEaR` would pass `test -e`, but wouldn't
    #  make much sense as an output, since `/usr/bin/cLEaR` doesn't exist,
    #   but `/usr/bin/clear` does
    if (( resolve_cmd_case )) {
      # this glob pattern resolves the path to its _actual_ casing
      path_match=( (#i)$~~cmd_path(DN) )
      # this is almost an assertion - it shouldn't be possible to get >1 match
      if ! (( $#path_match == 1 )) wh::error mult-cmd

      # replace the command path with its case-resolved version
      cmd_path="$path_match[1]"
    }

    # save the case-resolved (if applicable) command path
    match_arr+="$cmd_path"
    # while we have the path of the command, pass it through `file`
    #  to get some additional information about the executable
    magic_arr+="$( "${(@z)FILE_CMD}" -- "$cmd_path" )"
  }

  # —— iterate through matches ————————————————————————————————————————— #

  local -i 10 i
  local -a links
  local -i 2 is_exe
  local target magic_out line realpath fmt_path last_path

  # zip the command paths and their `file` outputs together,
  #  so we can iterate through them simultaneously
  for cmd_path magic_out in "${(@)match_arr:^magic_arr}"; {

    # —— resolve symlinks ———————————————————————————— #

    target="$cmd_path" realpath= line= links=()

    # while we haven't found the target file (`$target` is a symlink)
    while [[ -h $target ]] {
      # resolve the symlink, and add it to the `$links` array
      target="$( readlink -- "$target" )" || break
      links+="$target"
    }

    # —— add symlinks to output —————————————————————— #

    # send the initial path off for formatting
    #  if there aren't any links, then this path is the executable itself
    fmt_path="$cmd_path" is_exe=$(( $#links == 0 ))
    wh::commands::path

    if (( $#links )) {
      last_path="$links[-1]"

      # iterate through each link, format it, and add it to the line
      for i in {1..$#links}; {
        line+="$SYMLINK_ARROW"

        # the last "link" in the array is the actual executable
        fmt_path="$links[i]" is_exe=$(( i == $#links ))
        wh::commands::path
      }

    } else {
      last_path="$cmd_path"
    }

    # —— get realpath ———————————————————————————————— #

    realpath="$( realpath -q -- "$cmd_path" )"

    # if the final link isn't the same as the executable's `realpath`, then
    #  add an arrow to show its path with _all_ symlinks resolved
    if [[ -n "$realpath" && "$realpath" != "$last_path" ]] {
      line+="$NL$REALPATH_ARROW"

      # the `realpath` will always be an executable
      fmt_path="$realpath" is_exe=1
      wh::commands::path
    }

    # —— output —————————————————————————————————————— #

    # format / resolve the output of the `file` command that we got earlier
    wh::commands::magic

    # then add the formatted line (the path(s)) to the output
    output_lines+="$line"

    # if we're not on the last path, add a dividing line
    if [[ $cmd_path != $match_arr[-1] ]] output_lines+=$HALFLINE

    # ———————————————————————————————————————————————— #
  }
}

# —— commands::magic () ————————————————————————————————————————————————————— #

function wh::commands::magic () { # <- wh::commands <- wh::process_input <- wh
  local pattern colour icon cmd_type

  # iterate through each of the patterns & compare the magic output to each one
  # this for loop is essentially just a deconstructed switch/case statement
  for pattern colour icon cmd_type in "${(@)COMMAND_TYPES}"; {
    if [[ "$magic_out" != $~pattern ]] continue

    # re-assemble the executable's descriptor - note: one of the patterns uses
    #  a capturing group, so we use `eval` here to handle the replacement
    eval "output_lines+='$colour$icon${colour:+$RESET} '\"$cmd_type\""
    # return after the first match
    return
  }
}

# —— commands::path () —————————————————————————————————————————————————————— #

function wh::commands::path () { # <- wh::commands <- wh::process_input <- wh

  local path_col="$CYN" under=
  # this statement is essentially asking whether this is the final path or not
  if [[ $#links -eq 0 || -n $realpath ]] path_col="$LBL" under="$UDL"

  if [[ $fmt_path == */* ]] {
    # find & format the command's `dirname`
    line+="$path_col$under${${fmt_path/#$HOME/~}%/*}${under:+$NOUDL}/"
  }

  # colour the command name based on whether its a link or an executable
  if (( is_exe )) { line+="$RED" } else { line+="$MAG" }

  # colour the command's `basename`
  line+="$under${fmt_path##*/}$RESET"
}

# ——————————————————————————————————————————————————————————————————————————— #
# ── ── error () ── ───────────────────────────────────────────────────────── #

function wh::error () { # <- ... <- wh
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
# spell:ignore nodim disb mult noudl
