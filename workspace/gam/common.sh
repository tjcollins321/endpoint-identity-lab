#!/bin/bash
# Shared helpers for the GAM lifecycle scripts in this folder. Sourced, never run.
# bash 3.2-compatible (macOS /bin/bash); shellcheck clean.
#
# GAM is found on PATH, then at the GAM7 default install path, or set GAM=/path/to/gam.
# The tenant's primary domain comes from GAM_DOMAIN, else the domain saved in gam.cfg, else
# the tenant's domain list, so bare usernames and full addresses are both accepted everywhere.
# Reads use direct lookups (info, check) rather than search queries, whose index lags for a
# minute or more after a change.

set -u

if [ -z "${GAM:-}" ]; then
  if command -v gam >/dev/null 2>&1; then
    GAM=$(command -v gam)
  elif [ -x "$HOME/bin/gam7/gam" ]; then
    GAM="$HOME/bin/gam7/gam"
  else
    echo "error: gam not found on PATH or at ~/bin/gam7/gam; install GAM7 or set GAM=/path/to/gam" >&2
    exit 2
  fi
fi

log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { echo "error: $*" >&2; exit 1; }

_LAB_DOMAIN=""
lab_domain() {
  local cfg
  if [ -n "$_LAB_DOMAIN" ]; then
    echo "$_LAB_DOMAIN"
    return
  fi
  if [ -n "${GAM_DOMAIN:-}" ]; then
    _LAB_DOMAIN="$GAM_DOMAIN"
  else
    cfg="${GAMCFGDIR:-$HOME/.gam}/gam.cfg"
    if [ -r "$cfg" ]; then
      _LAB_DOMAIN=$(sed -n 's/^domain = //p' "$cfg" | head -1 | tr -d "'\"")
    fi
    if [ -z "$_LAB_DOMAIN" ]; then
      _LAB_DOMAIN=$("$GAM" print domains 2>/dev/null | awk -F, '$4 == "primary" { print $1; exit }')
    fi
  fi
  echo "$_LAB_DOMAIN"
}

# Full address from a bare username; full addresses pass through unchanged.
qualify() {
  case "$1" in
    *@*) echo "$1" ;;
    *)   echo "$1@$(lab_domain)" ;;
  esac
}

# gam_read ARGS...: a GAM read, its output on stdout. Google's APIs fail the odd valid request
# (the Data Transfer API returned 400 invalidArgument to about one in ten identical reads on
# 2026-10-04), and GAM does not retry those. So a read that fails is tried three times, unless
# the exit status is itself an answer: 56, does not exist, or 26, check suspended's "suspended".
# The last exit status is returned, so a caller can tell an empty answer from no answer.
gam_read() {
  local out rc n=0
  while :; do
    out=$("$GAM" "$@" 2>/dev/null); rc=$?
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 56 ] || [ "$rc" -eq 26 ]; then break; fi
    n=$((n + 1))
    [ "$n" -lt 3 ] || break
    sleep 2
  done
  [ -z "$out" ] || printf '%s\n' "$out"
  return "$rc"
}

# 0 if the account exists (active or suspended), 1 if GAM says it does not. A read that keeps
# failing is neither: the script stops rather than take it for absence.
user_exists() {
  local rc
  gam_read info user "$1" quick >/dev/null; rc=$?
  [ "$rc" -ne 0 ] || return 0
  [ "$rc" -ne 56 ] || return 1
  die "could not read $1 from the directory after three tries (gam exit $rc); rerun"
}

# 0 if the group exists, 1 otherwise.
group_exists() {
  "$GAM" info group "$1" quick >/dev/null 2>&1
}

# Prints "First<TAB>Last" for an existing account, nothing when it does not exist.
user_names() {
  "$GAM" info user "$1" quick 2>/dev/null | awk -F': ' '
    /^ *First Name: / { f = $2 }
    /^ *Last Name: /  { l = $2 }
    END { if (f != "" || l != "") printf "%s\t%s\n", f, l }'
}

# Prints the suspension reason (ADMIN for an administrator's suspension; Google's own holds
# such as WEB_LOGIN_REQUIRED on a fresh account) or nothing when the account is active.
suspension_reason() {
  gam_read check suspended "$1" | sed -n 's/.*Suspension Reason: //p'
}

# 0 if the account is suspended for any reason, 1 if active. Callers check user_exists first.
user_suspended() {
  gam_read check suspended "$1" >/dev/null
  [ $? -eq 26 ]
}

# Username from the convention: first initial plus last name, lowercase, letters and digits only;
# on a collision with a different person, a digit suffix (2, 3, ...). Prints "address<TAB>exists"
# when the address already belongs to this person (same first and last name), "address<TAB>free"
# when it is unused; notes about taken candidates go to stderr. Returns 1 when no name is usable
# or no suffix is free. Used by create-user.sh and by lifecycle/onboard.sh.
resolve_username() {
  local first="$1" last="$2" domain initial surname base tab n candidate names have_first have_last
  domain=$(lab_domain)
  [ -n "$domain" ] || return 1
  initial=$(printf '%s' "$first" | cut -c1 | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  surname=$(printf '%s' "$last" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  base="$initial$surname"
  [ -n "$base" ] || return 1
  tab=$(printf '\t')
  n=1
  while [ "$n" -le 9 ]; do
    if [ "$n" -eq 1 ]; then candidate="$base@$domain"; else candidate="$base$n@$domain"; fi
    names=$(user_names "$candidate")
    if [ -z "$names" ]; then
      printf '%s\tfree\n' "$candidate"
      return 0
    fi
    have_first=${names%%"$tab"*}
    have_last=${names#*"$tab"}
    if [ "$have_first" = "$first" ] && [ "$have_last" = "$last" ]; then
      printf '%s\texists\n' "$candidate"
      return 0
    fi
    log "taken: $candidate belongs to $have_first $have_last; trying the next suffix" >&2
    n=$((n + 1))
  done
  return 1
}

# 0 if a completed Drive transfer from $1 to $2 (or to anyone, when $2 is empty) exists.
drive_transferred() {
  if [ -n "${2:-}" ]; then
    gam_read print datatransfers olduser "$1" newuser "$2" status completed | tail -n +2 | grep -q .
  else
    gam_read print datatransfers olduser "$1" status completed | tail -n +2 | grep -q .
  fi
}
