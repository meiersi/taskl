################################################################
# Implementation of IdemShell commands and tests.

function idem_CHOWN {
  local user="${2%:*}"
  local group="${2#*:}"
  chown "$user" "$1"
  chown :"$group" "$1"
}
function idem_CHMOD {
  chmod "$2" "$1"
}
function idem_RM {
  rm -rf "$1"
}
function idem_CP {
  { which rsync && rsync "$1" "$2" ;} || cp "$1" "$2"
}
function idem_LNs {
  { [ -L "$2" ] && rm -f "$2" ;} || rm -rf "$2"
  ln -s "$1" "$2"
}
function idem_TOUCH {
  rm -rf "$1"
  touch "$1"
}
function idem_MKDIR {
  rm -rf "$1"
  mkdir -p "$1"
}
function idem_USERADD {
  getent passwd "$1" && userdel "$1"
  useradd "$@" 
}
function idem_USERDEL {
  userdel "$1"
}
function idem_GROUPADD {
  getent group "$1" && groupdel "$1"
  groupadd "$@" 
}
function idem_GROUPDEL {
  groupdel "$1"
}
function idem_GPASSWDa {
  gpasswd "$1" -a "$2" 1>/dev/null
}
function idem_GPASSWDd {
  gpasswd "$1" -d "$2" 1>/dev/null
}

function idem_helper_LSo {
  local awk_script
  local name
  case "$2" in
    *:) name="${2%:}" ; awk_script='{print $3}' ;;
    :*) name="${2#:}" ; awk_script='{print $4}' ;;
    *)  ! echo 'Mysterious invalid call to LSo helper.' 1>&2 ;;  
  esac
  local normed="${name#+}"
  if [ "$name" = "$normed" ]  # Determine if we are using numric form.
  then
    ls -ld "$1"
  else
    ls -nd "$1"
  fi | awk "$awk_script" | fgrep -x -- "$normed"
}
function idem_LSo {
  local path="$1"
  local user="${2%:*}"
  local group="${2#*:}"
  { [ "$user" = "" ]  || idem_helper_LSo "$1" ":$user"  } &&
  { [ "$group" = "" ] || idem_helper_LSo "$1" "$group:" }
}
function idem_LSm { Path Mode
  local path="$1"
  local mode="$2"
}
function idem_DASHe {
  [ -e "$1" ]
}
function idem_DASH_ {
  [ "$1" "$2" ]
}
function idem_DIFFq {
  diff -q "$1" "$2" 2>/dev/null
}
function idem_LSl {
  [ `readlink -- "$2"` = "$1" ]
}
function idem_GETENTu {
  getent passwd "$1"
}
function idem_GETENTg {
  getent group "$1"
}
function idem_GROUPS {
  groups -- "$1" | xargs printf '%s\n' | sed '1,2 d' | fgrep -x -- "$2"
}
function idem_Not {
  ! echo 'Unimplemented IdemShell primitive should not be called!' 1>&2
}
function idem_And {
  ! echo 'Unimplemented IdemShell primitive should not be called!' 1>&2
}
function idem_Or {
  ! echo 'Unimplemented IdemShell primitive should not be called!' 1>&2
}
function idem_TRUE {
  ! echo 'Unimplemented IdemShell primitive should not be called!' 1>&2
}
function idem_FALSE {
  ! echo 'Unimplemented IdemShell primitive should not be called!' 1>&2
}


#nstance CodeGen Test where
# codeGen test               =  case collapse test of
#   LSo p o                 ->  undefined
#   LSm p m                 ->  undefined
#   DASHe p                 ->  testFS "-e" p
#   DASH_ node p            ->  testFS (nodeTest node) p
#   DIFFq p' p              ->  cmd ["diff", "-q", escEnc p, escEnc p']
#   LSl p' p                ->  readlinkEq p p'
#   GETENT ent              ->  getent ent
#   GROUPS u g              ->  (pipeline . fmap cmd)
#                                [["groups", "--", escEnc u]
#                                ,["xargs", "printf", esc "%s\\n"]
#                                ,["sed", esc "1,2 d"]
#                                ,["fgrep", "--line-regexp", "--", escEnc g]]
#   Not t                   ->  Program.Bang (codeGen t)
#   And t t'                ->  codeGen t `Program.And` codeGen t'
#   Or t t'                 ->  codeGen t `Program.Or` codeGen t'
#   TRUE                    ->  cmd ["true"]
#   FALSE                   ->  cmd ["false"]
#  where
#   readlinkEq p p'          =  Program.Sequence
#     (Program.VarAssign "link_" (escEnc p))
#     (cmd ["[", "`readlink -- \"$link_\"`", "=", escEnc p', "]"])

