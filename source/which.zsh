#!/usr/bin/env zsh


##region 0 - wh()  —————————————————————————————————————————————————————————— #

wh() {
  ##region 0.1 - Flag/Input-Handling  ——————————————————————————————————— #

  local -i 2 {internal_mode,display_indices}=0 {draw_lines,do_all}=1

  while getopts 'xilA' opt; do
    case "$opt" {
      x)   internal_mode=1 ;;
      i) display_indices=1 ;;
      l)      draw_lines=0 ;;
      A)          do_all=0 ;;
    }
  done
  shift $(( OPTIND - 1 ))

  if (( internal_mode )) local {display_indices,draw_lines,do_all}=0

  if (( $# == 0 )) { echo "$0: must enter a command" >&2; return 1; }

  local -r command="$1"

  ##endregion 0.1 - Flag/Input-Handling  ———————————————————————————————— #


  ##region 0.2 - Constant-Definitions  —————————————————————————————————— #

  local -r _alias_prefix="$command: aliased to "
  local -r _builtin_line="$command: shell built-in command"
  local -r _file_prefix='/'

  local -r _function_start="$command () {"
  local -r _function_end='}'

  local -r  _posix_exe_prefix='POSIX shell script text executable'
  local -r _mach_o_bin_prefix='Mach-O universal binary'
  local -r     _zsh_exe_infix='zsh script'
  local -r   _bash_exe_prefix='Bourne-Again shell script'
  local -r        _ascii_text='ASCII text'

  # ————————————————————————————————————————————————————————————————— #

  local -rA _types=(
        [alias]='1 0 alias'
      [builtin]='1 0 shell builtin'
     [function]='1 0 function'

  [general_exe]='0 1 general executable'
   [mach_o_bin]='0 1 Mach-O binary'
    [posix_exe]='0 1 POSIX executable'
    [other_exe]='0 1 binary executable'
     [bash_exe]='0 1 GNU Bash executable'
      [zsh_exe]='0 1 Z shell executable'

      [unknown]='0 0 unknown type'
  )

  local -i 10 max_type_len=-1; local t
  for t ("${(@k)_types}") if (( $#t > max_type_len )) max_type_len=${#t}

  # ————————————————————————————————————————————————————————————————— #

  # these are in order of preference, i.e. 'bat' first, 'cat' second, etc.
  local -ra _visualisers=(
    'bat --language=zsh --paging=never --style=plain --color=always'
    'cat -u'
  )

  local visualiser
  # loop through all of the possible visualisers
  for visualiser in "${(@)_visualisers}" ''; {
    # if one of the commands succeeds, then break,
    #  and $visualiser will be set to that value
    command -v "${visualiser/% **}" &>/dev/null && break
    # if they all fail, then $visualiser will be unset (set to '')
  }

  ##endregion 0.2 - Constant-Definitions  ——————————————————————————————— #


  ##region 0.3 - Parsing-which-Output  —————————————————————————————————— #

  local which_output dash_a=
  if (( do_all )) dash_a='-a'
  which_output="$( which $dash_a -- "$command" 2>&1 )" || {
    echo "$0: '$command' not found" >&2
    return 1
  }

  local -a all_definitions=()
  local -a def_type=()

  local -i 2 is_reading_func=0

  local line file_type func_path
  for line in "${(f)which_output}"; {

    # Function body & end
    if (( is_reading_func )) {
      # stop reading the function
      if [[ "${line[1]}" == "$_function_end" ]] is_reading_func=0

      # make sure that escape chars aren't accidentally expanded
      line="${line//\\/\\\\}"

      # put `then`/`do` on the same line as `if`/`for`/`while`
      if [[ "$line" =~ '^\s*(then|do) *$' ]] {
        all_definitions[-1]+="; ${line/#[[:space:]]#}"
        continue
      }
      all_definitions[-1]+=$'\n'"$line"
      continue
    }

    case "$line" {

      # function
      "$_function_start")
        func_path="$( wh::get_path "$command" )"
        all_definitions+=( "$func_path\nfunction $line" )

        def_type+=( 'function' )
        is_reading_func=1
        ;;

      # alias
      "$_alias_prefix"*)
        all_definitions+=( "${line/$_alias_prefix}" )
        def_type+=( 'alias' )
        ;;

      # builtin
      "$_builtin_line")
        all_definitions+=( "$line" )
        def_type+=( 'builtin' )
        ;;

      # posix_exe, mach_o_bin, bash_exe, zsh_exe, general_exe, other_exe
      "$_file_prefix"*)
        all_definitions+=( "$line" )

        file_type="$( file -b "$line" )"
        # only get the first line of the output
        case "${file_type/$'\n'*}" {
          "$_posix_exe_prefix"*              ) def_type+=( 'posix_exe'   ) ;;
          "$_mach_o_bin_prefix"*             ) def_type+=( 'mach_o_bin'  ) ;;
          "$_bash_exe_prefix"*"$_ascii_text" ) def_type+=( 'bash_exe'    ) ;;
         *"$_zsh_exe_infix"*"$_ascii_text"   ) def_type+=( 'zsh_exe'     ) ;;
          "$_ascii_text"                     ) def_type+=( 'general_exe' ) ;;
          *                                  ) def_type+=( 'other_exe'   ) ;;
        }
        ;;

      # unknown
      *)
        all_definitions+=( "$line" )
        def_type+=( 'unknown' )
        ;;
    }
  }

  ##endregion 0.3 - Parsing-which-Output  ——————————————————————————————— #

  # ——————————————————————————————————————————————————————————————————————— #

  ##region 0.4 - Displaying-Output  ————————————————————————————————————— #

  if (( draw_lines )) wh::draw_separator_line outside

  local -ri 10 definition_count=${#all_definitions}
  local -ri 10    def_count_len=${#definition_count}

  local -ri 10 subtitle_len=$(( def_count_len + max_type_len ))

  local type display_type body
  local -i 10 i run_func is_path

  for i in {1.."$definition_count"}; {
    type="${def_type[i]}"
    body="${all_definitions[i]}"

    if (( draw_lines && i != 1 )) wh::draw_separator_line inside

    # Print out the subtitle, which is:
    #  - the index, right-aligned,
    #    - so if there are >= 10 results, they the indices line up
    #  - a literal '.␣', to separate the index from the output type
    if (( display_indices )) echo -n "${(l:$def_count_len:)i}. "

    # I'm storing some extra data in the first few chars of the type names
        run_func="${_types[$type][1]}"
         is_path="${_types[$type][3]}"
    display_type="${_types[$type][5,-1]}"

    if ! [[ "$type" =~ '^(function|alias|builtin)$' ]] \
      || (( internal_mode )) echo "$display_type"

    # if there's a dedicated function for this type, run it
    if (( run_func )) {
      wh::"$type"    \
        "$body"       \
        "$visualiser"  \
        "$command"      \
        "$internal_mode" \
        "$func_path"
      continue
    }

    # if the type is a path, pretty print it
    if (( is_path )) { wh::echo_coloured_path "$body"; echo; continue; }
    # otherwise just print the body
    echo "$body"
  }

  if (( draw_lines )) wh::draw_separator_line outside

  return 0

  ##endregion 0.4 - Displaying-Output  —————————————————————————————————— #
}

##endregion 0 - wh()  ——————————————————————————————————————————————————————— #


# ——————————————————————————————————————————————————————————————————————————— #


##region 1 - Visualisation-Functions  ——————————————————————————————————————— #


##region 1.1 - wh::function()  —————————————————————————————————————————— #

wh::function() {
  local -r body="$1" vis="$2" from="$5"
  # greedily capture everything ( ** ),
  #  from the first space until the end of the string ( % )
  local -r vis_command="${vis/% **}"
  local -ra vis_args=( "${(z)vis/$vis_command}" )

  echo "$body" | command "$vis_command" "${(@)vis_args}"
}

##endregion 1.1 - wh::function()  ——————————————————————————————————————— #


##region 1.2 - wh::alias()  ————————————————————————————————————————————— #

wh::alias() {
  local -r sq="'" dq='"'

  local -r _equals_colour=$'\e[38;2;148;226;213m'
  local -r  _alias_colour=$'\e[38;2;203;166;247m'
  local -r  _quote_colour=$'\e[38;2;166;227;161m'
  local -r    _cmd_colour=$'\e[38;2;137;180;250m'
  local -r         _reset=$'\e[0m'

  local           body="$1"
  local -r  visualiser="$2"
  local -r     command="$3"
  local -ri 2 internal="$4"

  # if the alias is just aliasing another command,
  #  then show that command's `wh` entry instead
  # also check that we're not in internal mode, so we don't end up recursing
  setopt rematch_pcre
  local -i 2 in_secondary_mode=0
  if ! (( internal )) && [[ "$body" =~ '^ *(command +)?((\w|[-+.:])+) *$' ]] {
    local -r secondary_cmd="${match[2]}"
    local -r secondary_indent=$'\n\t\e[38;2;64;68;84m│\e[0m '
    in_secondary_mode=1
  }

  # —— Correctly Quote & Escape the Cmd Text ———————————————————————— #

  local quoted_body="${${(qqqq)body}[3,-2]}"
  local -i 2 contains_{{s,d}q,sp}=0  # single quote, double quote, space

  if (( ${#quoted_body//\\$sq} != $#quoted_body )) contains_sq=1
  if (( ${#quoted_body//$dq}   != $#quoted_body )) contains_dq=1
  if (( ${#quoted_body// }     != $#quoted_body )) contains_sp=1

  local quote="$sq"
  if (( contains_sq && ! contains_dq )) {
    quoted_body="${quoted_body//\\$sq/$sq}"
    quote="$dq"
  } elif ! (( contains_sq || contains_dq || contains_sp )) quote=

  # ————————————————————————————————————————————————————————————————— #

  local -r alias_text="${_alias_colour}alias$_reset "
  local -r   cmd_text="$_cmd_colour$command$_reset"
  local -r     equals="$_equals_colour=$_reset"
  local         quote="$_quote_colour$quote$_reset"

  # ————————————————————————————————————————————————————————————————— #

  # greedily capture everything ( ** ),
  #  from the first space until the end of the string ( % )
  local -r vis_command="${visualiser/% **}"
  local -ra vis_args=( "${(z)visualiser/$vis_command}" )

  echo -n "$alias_text$cmd_text$equals$quote"

  echo -n "$quoted_body" \
    | command "$vis_command" "${(@)vis_args}" \
    | sed "s/\\\'/$_cmd_colour\\\'$_quote_colour/g"

  echo -n "$quote"

  # ————————————————————————————————————————————————————————————————— #

  if ! (( in_secondary_mode )) { echo; return 0; }
  body="${secondary_cmd:-$body}"

  # the `//\\/\\\\` section is to make sure none of the
  #  escape sequences (e.g. `\n`) get flattened
  local -ra sub_cmd_lines=( "${(@f)"$( wh -x "$body" )"//\\/\\\\}" )
  local -ra sub_cmd_body=( "${(@)sub_cmd_lines[2,-1]}" )
  local     sub_cmd_type="${sub_cmd_lines[1]}:"

  local article='a'
  if [[ "$sub_cmd_type[1]" =~ '[aeiou]' ]] article+='n'

  echo -n ", where $_cmd_colour$body$_reset is $article $sub_cmd_type"
  echo "$secondary_indent${(pj:$secondary_indent:)sub_cmd_body}"

}

##endregion 1.2 - wh::alias()  —————————————————————————————————————————— #


##region 1.3 - wh::builtin()  ——————————————————————————————————————————— #

wh::builtin() {
  local -r _cmd_colour=$'\e[38;2;137;180;250m'
  local -r _shl_colour=$'\e[38;2;184;076;080m'
  local -r _reset=$'\e[0m'

  # get the last part of the path of whichever shell they're using
  local -r shl_name="${${SHELL:-$BASH}/\/**\/}"
  local -r cmd_name="${1/%:*}"

  local -r shl_coloured="$_shl_colour$shl_name$_reset"
  local -r cmd_coloured="$_cmd_colour$cmd_name$_reset"

  echo -n "$cmd_coloured is a $shl_coloured ("
  wh::echo_coloured_path "$SHELL"; echo ') builtin'
}

##endregion 1.3 - wh::builtin()  ———————————————————————————————————————— #


##endregion 1 - Visualisation-Functions  ———————————————————————————————————— #


# ——————————————————————————————————————————————————————————————————————————— #


##region 2 - Helper-Functions  —————————————————————————————————————————————— #


##region 2.1 - wh::draw_separator_line()  ——————————————————————————————— #

wh::draw_separator_line() {
  local -r _outside_colour=$'\e[38;2;128;135;162m'
  local -r  _inside_colour=$'\e[38;2;064;068;084m'
  local -r _reset=$'\e[0m' _line_char='─'

  local -r colour="_${1}_colour"
  echo "${(P)colour}${(pr:$(( COLUMNS * .8 ))::$_line_char:)}$_reset"
}

##endregion 2.1 - wh::draw_separator_line()


##region 2.2 - wh::echo_coloured_path()

wh::echo_coloured_path() {
  local -r   _leading_colour=$'\e[38;2;053;063;090m'
  local -r      _body_colour=$'\e[38;2;109;142;197m'
  local -r  _basename_colour=$'\e[38;2;184;076;080m'
  local -r _underline_colour=$'\e[58;2;098;139;205;4m'

  local -r _underline_off=$'\e[24m'
  local -r _reset_all=$'\e[0m'

  local -r path_="${1/$HOME/~}"

  local -r body="${(S)${(S)path_/#*\/}/%\/*}"
  local -r leading="${path_/%\/**}"
  local -r basename="${path_/#**\/}"

  echo -n "$_underline_colour"
  echo -n "$_leading_colour$leading/"
  echo -n "$_body_colour$body"
  echo -n "$_underline_off/$_underline_colour"
  echo -n "$_basename_colour$basename$_reset_all"
}

##endregion 2.2 - wh::echo_coloured_path()  ————————————————————————————— #


##region 2.3 - wh::get_path

wh::get_path() {
  local -r whence_out="$( whence -va "$1" )"

  local abs_path="${${whence_out#*is a *function from }%$'\n'*}"
  local rel_path="$( grealpath --no-symlinks --relative-to=. "$abs_path" )"

  abs_path="${abs_path/#$HOME/~}"
  if [[ "${rel_path[1,3]}" != '../' ]] rel_path="./$rel_path"

  echo "# $abs_path"
  if (( $#rel_path <= COLUMNS / 2 )) && [[ "$PWD" != "$HOME" ]] \
    echo "# $rel_path"
}

##endregion 2.3 - wh::get_path


##endregion 2 - Helper-Functions  ——————————————————————————————————————————— #


# ——————————————————————————————————————————————————————————————————————————— #

wh::__test__() {
  local -r col=$'\e[38;2;128;125;237m'
  local -r rst=$'\e[0m'

  local -ra _inputs_to_test=( 'config' 'echo' 'nv' )

  local input func title
  for input in "${(@)_inputs_to_test}"; {
    title="${(r:$(( COLUMNS - $#input + 15 ))::─:)input/%/$col }"
    echo "$col───$rst $title $rst"

    echo "${$( whence -va "$input" )/$HOME/~}"; echo
    wh "$input"
  }
}

# ——————————————————————————————————————————————————————————————————————————— #

#  -v     Produce a more verbose report.
#
#  -c     Print  the  results  in  a  csh-like  format.  This takes
#         precedence over -v.
#
#  -w     For each name, print `name: word' where word  is  one  of
#         alias,  builtin,  command,  function, hashed, reserved or
#         none, according  as  name  corresponds  to  an  alias,  a
#         built-in  command, an external command, a shell function,
#         a command defined with the hash builtin, a reserved word,
#         or  is not recognised.  This takes precedence over -v and
#         -c.
#
#  -f     Causes the contents of a shell function to be  displayed,
#         which  would otherwise not happen unless the -c flag were
#         used.
#
#  -p     Do a path search for name even if it  is  an  alias,  re-
#         served word, shell function or builtin.
#
#  -a     Do  a  search  for all occurrences of name throughout the
#         command path.  Normally  only  the  first  occurrence  is
#         printed.
#
#  -m     The  arguments  are taken as patterns (pattern characters
#         should be quoted), and the information is  displayed  for
#         each command matching one of these patterns.
#
#  -s     If  a  pathname contains symlinks, print the symlink-free
#         pathname as well.
#
#  -S     As -s, but if the pathname had to be resolved by  follow-
#         ing   multiple   symlinks,  the  intermediate  steps  are
#         printed, too.  The symlink resolved at each step might be
#         anywhere in the path.
#
#  -x num Expand  tabs when outputting shell functions using the -c
#         option.  This has the same effect as the -x option to the
#         functions builtin.

# spell:ignore grealpath
