#!/usr/bin/env zsh

wh() {
  setopt local_options warn_create_global warn_nested_var extended_glob

  local -r error="$0:"

  local -i 2 internal_mode=0 do_lines=1 do_all=1

  local opt OPTIND OPTARG
  while { getopts 'xlA' opt; } { #
    case "$opt" {
      ( x ) internal_mode=1 ;;
      ( l )      do_lines=0 ;;
      ( A )        do_all=0 ;;
      ( * )        return 1 ;;
    }
  }
  shift $(( OPTIND - 1 ))

  if ! (( $# )) {
    echo "$error must enter a command" >&2
    return 1
  }

  if (( internal_mode )) do_lines=0 do_all=0

  # ————————————————————————————————————————————————————————————————— #

  local -r NL=$'\n'
  local -r sq=\' dq=\"

  local -r reset=$'\e[m'
  local -r no_udln=$'\e[24m'

  local -r     d_red=$'\e[38;5;131m'  #B84C50
  local -r     green=$'\e[38;5;114m'  #A6E3A1
  local -r turquoise=$'\e[38;5;116m'  #94E2D5
  local -r    d_blue=$'\e[38;5;60m'   #353F5A
  local -r    m_blue=$'\e[38;5;68m'   #6D8EC5
  local -r    l_blue=$'\e[38;5;111m'  #89B4FA
  local -r      pink=$'\e[38;5;183m'  #CBA6F7
  local -r    d_grey=$'\e[38;5;238m'  #404454
  local -r    l_grey=$'\e[38;5;103m'  #8087A2
  local -r blue_udln=$'\e[58;5;68;4m' #6D8EC5

  local -ri 10 line_len=$(( COLUMNS / 2 ))

  local -r outside_line="$l_grey${(r:$line_len::─:)}$reset"
  local -r  inside_line="$d_grey${(r:$line_len::─:)}$reset"

  # ————————————————————————————————————————————————————————————————— #

  local -r command="$1"

  local -r alias_prefix="$command: aliased to "
  local -r builtin_line="$command: shell built-in command"
  local -r file_prefix='/'

  local -r function_start="$command () {"
  local -r function_end='}'

  local -r  posix_exe_prefix='POSIX shell script text executable'
  local -r mach_o_bin_prefix='Mach-O universal binary'
  local -r     zsh_exe_infix='zsh script'
  local -r   bash_exe_prefix='Bourne-Again shell script'
  local -r        ascii_text='ASCII text'

  # ————————————————————————————————————————————————————————————————— #

  local -rA types=(
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
  for t ("${(@k)types}") if (( $#t > max_type_len )) max_type_len=${#t}

  # ————————————————————————————————————————————————————————————————— #

  # these are in order of preference, i.e. `bat` first, `$PAGER` second, etc.
  local -ra _visualisers=(
    'bat --language=zsh --paging=never --style=plain --color=always'
    "$PAGER"
    'cat'
  )

  local visualiser
  # loop through all of the possible visualisers
  for visualiser in "${(@)_visualisers}" ''; {
    # if one of the commands succeeds, then break,
    #  and `$visualiser` will be set to that value
    command -v -- "${visualiser%% *}" &>/dev/null && break
    # if they all fail, then `$visualiser` will be unset (set to '')
  }

  local which_output dash_a=
  if (( do_all )) dash_a='-a'

  which_output="$( which $dash_a -- "$command" )" || {
    echo -E "$error \`$command\` not found" >&2
    return 1
  }

  local -a all_definitions def_type
  local -i 2 is_reading_func=0
  local line file_type func_path

  for line in "${(@f)which_output}"; {

    # Function body & end
    if (( is_reading_func )) {
      # if we've reached the end, stop reading the function
      if [[ "$line[1]" == "$function_end" ]] is_reading_func=0

      # put `then`/`do` on the same line as `if`/`for`/`while`
      # if [[ "$line" =~ '^\s*(then|do) *$' ]] {
      if [[ "$line" == [[:space:]]#(then|do) ]] {
        all_definitions[-1]+="; ${(*)line/#[[:space:]]#}"
        continue
      }

      all_definitions[-1]+="$NL$line"
      continue
    }

    case "$line" {

      # function
      ( "$function_start" )
        is_reading_func=1
        def_type+=function

        func_path="$( wh::get_path "$command" )"
        all_definitions+="${func_path:+$func_path$NL}function $line"
      ;;

      # alias
      ( "$alias_prefix"* )
        def_type+=alias
        all_definitions+="${line#$alias_prefix}"
      ;;

      # builtin
      ( "$builtin_line" )
        def_type+=builtin
        all_definitions+="$line"
      ;;

      # posix_exe, mach_o_bin, bash_exe, zsh_exe, general_exe, other_exe
      ( "$file_prefix"* )
        all_definitions+="$line"
        file_type="$( file --brief "$line" )"

        # only get the first line of the output
        case "${file_type%%$NL*}" {
         (  "$posix_exe_prefix"*             ) def_type+=posix_exe   ;;
         (  "$mach_o_bin_prefix"*            ) def_type+=mach_o_bin  ;;
         (  "$bash_exe_prefix"*"$ascii_text" ) def_type+=bash_exe    ;;
         ( *"$zsh_exe_infix"*"$ascii_text"   ) def_type+=zsh_exe     ;;
         (  "$ascii_text"                    ) def_type+=general_exe ;;
         ( *                                 ) def_type+=other_exe   ;;
        }
      ;;

      ( * ) # unknown
        def_type+=unknown
        all_definitions+="$line"
      ;;
    }
  }

  # ——————————————————————————————————————————————————————————————————————— #

  local -ri 10 def_count=${#all_definitions}

  local type display_type body
  local -i 10 i run_func is_path

  if (( def_count < 2 )) do_lines=0
  if (( do_lines      )) echo "$outside_line"

  for i in {1..$def_count}; {
    type="$def_type[i]"
    body="$all_definitions[i]"

    if (( do_lines && i != 1 )) echo "$inside_line"

    # I'm storing some extra data in the first few chars of the type names
        run_func="${types[$type][1]}"
         is_path="${types[$type][3]}"
    display_type="${types[$type][5,-1]}"

    if [[ "$type" != (function|alias|builtin) ]] || (( internal_mode )) {
      echo -E - "$display_type"
    }

    if (( run_func )) {  # if there's a function for this type, run it
      wh::"$type"

    } elif (( is_path )) {  # if the type is a path, pretty print it
      wh::echo_coloured_path "$body"
      echo

    } else {  # otherwise just print the body
      echo -E - "$body"
    }
  }

  if (( do_lines )) echo "$outside_line"

  return 0
}

# ——————————————————————————————————————————————————————————————————————————— #
# ——————————————————————————————————————————————————————————————————————————— #

wh::function() {
  # greedily capture everything ( `%%` ),
  #  from the first space until the end of the string ( `%` )
  local -r vis_command="${visualiser%% *}"
  local -ra vis_args=( "${(z)visualiser/$vis_command}" )

  echo -E - "$body" | command "$vis_command" "${(@)vis_args}"
}

wh::alias() {
  setopt local_options rematch_pcre
  local -a match mbegin mend
  local    MATCH MBEGIN MEND

  local -i 2 in_secondary_mode=0

  # if the alias is just aliasing another command,
  #  then show that command's `wh` entry instead
  # also check that we're not in internal mode, so we don't end up recursing
  if ! (( internal_mode )) \
    && [[ "$body" =~ '^ *(command +)?((\w|[-+.:])+) *$' ]] {
    local -r secondary_cmd="$match[2]"
    local -r secondary_indent="$NL    $d_grey│$reset "
    in_secondary_mode=1
  }

  # —— Correctly Quote & Escape the Cmd Text ———————————————————————— #

  local quoted_body="${${(qqqq)body}[3,-2]}"
  local -i 2 contains_{sq,dq,sp}=0  # single quote, double quote, space

  if (( ${#quoted_body//\\$sq} != $#quoted_body )) contains_sq=1
  if (( ${#quoted_body//$dq}   != $#quoted_body )) contains_dq=1
  if (( ${#quoted_body// }     != $#quoted_body )) contains_sp=1

  local quote="$sq"
  if (( contains_sq && ! contains_dq )) {
    quoted_body="${quoted_body//\\$sq/$sq}"
    quote="$dq"

  } elif ! (( contains_sq || contains_dq || contains_sp )) {
    quote=

  } # else quote=$sq

  # ————————————————————————————————————————————————————————————————— #

  local -r alias_text="${pink}alias$reset "
  local -r   cmd_text="$l_blue$command$reset"
  local -r     equals="$turquoise=$reset"
  local         quote="$green$quote$reset"

  # ————————————————————————————————————————————————————————————————— #

  # greedily capture everything ( `%%` ),
  #  from the first space until the end of the string ( `%` )
  local -r vis_command="${visualiser%% *}"
  local -ra vis_args=( "${(z)visualiser/$vis_command}" )

  echo -nE "$alias_text$cmd_text$equals$quote"

  echo -nE "$quoted_body" \
    | command "$vis_command" "${(@)vis_args}" \
    | sed "s/\\\'/$l_blue\\\'$green/g"

  echo -n "$quote"

  # ————————————————————————————————————————————————————————————————— #

  if ! (( in_secondary_mode )) echo && return
  local -r second_body="${secondary_cmd:-$body}"

  local -ra sub_cmd_lines=( "${(@f)$( wh -x -- "$second_body" )}" )
  local -ra sub_cmd_body=( "${(@)sub_cmd_lines[2,-1]}" )
  local -r  sub_cmd_type="$sub_cmd_lines[1]:"

  local article='a'
  if [[ "$sub_cmd_type" == [aeiou]* ]] article='an'

  echo -nE ", where $l_blue$second_body$reset is $article $sub_cmd_type"
  echo -E "$secondary_indent${(pj:$secondary_indent:)sub_cmd_body}"
}

wh::builtin() {
  # get the last part of the path of whichever shell they're using
  local -r shl_name="${${SHELL:-$BASH}/\/*\/}"
  local -r cmd_name="${body%%:*}"

  local -r shl_coloured="$d_red$shl_name$reset"
  local -r cmd_coloured="$l_blue$cmd_name$reset"

  echo -nE "$cmd_coloured is a $shl_coloured ("
  wh::echo_coloured_path "${SHELL:-$BASH}"
  echo ') builtin'
}

# ——————————————————————————————————————————————————————————————————————————— #
# ——————————————————————————————————————————————————————————————————————————— #

wh::echo_coloured_path() {
  local -r path_="${1/$HOME/~}"

  local -r path_body="${${path_#*\/}%\/*}"
  local -r leading_segment="${path_%%\/*}"
  local -r basename="${path_##*\/}"

  echo -nE "$blue_udln$d_blue$leading_segment/"
  echo -nE "$m_blue$path_body"
  echo -nE "$no_udln/$blue_udln"
  echo -nE "$d_red$basename$reset"
}

wh::get_path() {
  local -r whence_out="$( whence -va "$1" )"
  local abs_path="${${whence_out#*is a *function from }%$NL*}"

  local -i 2 do_rel_path=1
  local rel_path; rel_path="$(
    grealpath --no-symlinks --relative-to=. -- "$abs_path"
  )" 2>/dev/null || do_rel_path=0

  abs_path="${abs_path/#$HOME/~}"

  if [[ "$rel_path" != */* && "$rel_path" != ../* ]] rel_path="./$rel_path"

  # only display `$abs_path` if it actually has a value
  echo -nE "${abs_path:+# $abs_path$NL}"

  if (( do_rel_path && $#rel_path > 0 && $#rel_path <= $#abs_path )) \
    && [[ "$PWD" != "$HOME" && "$abs_path" != '~'* ]] {
    echo -E "# $rel_path"
  }
}

# ——————————————————————————————————————————————————————————————————————————— #
# ——————————————————————————————————————————————————————————————————————————— #

wh::__test__() {
  local -r col=$'\e[38;5;105m'
  local -r rst=$'\e[m'

  local -ra _inputs_to_test=( pwda echo nv man - )  # spell:disable-line

  local input func title
  for input in "${(@)_inputs_to_test}"; {
    title="${(r:$(( COLUMNS - $#input + 7 ))::─:)input/%/$col }"
    echo -E "$col───$rst $title $rst"

    wh "$@" "$input"
  }
}

# ——————————————————————————————————————————————————————————————————————————— #
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

# spell:ignore grealpath udln
