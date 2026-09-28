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

# 0 if the account exists (active or suspended), 1 otherwise.
user_exists() {
  "$GAM" info user "$1" quick >/dev/null 2>&1
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
  "$GAM" check suspended "$1" 2>/dev/null | sed -n 's/.*Suspension Reason: //p'
}

# 0 if the account is suspended for any reason, 1 if active. Callers check user_exists first.
user_suspended() {
  "$GAM" check suspended "$1" >/dev/null 2>&1
  [ $? -eq 26 ]
}

# 0 if a completed Drive transfer from $1 to $2 (or to anyone, when $2 is empty) exists.
drive_transferred() {
  if [ -n "${2:-}" ]; then
    "$GAM" print datatransfers olduser "$1" newuser "$2" status completed 2>/dev/null | tail -n +2 | grep -q .
  else
    "$GAM" print datatransfers olduser "$1" status completed 2>/dev/null | tail -n +2 | grep -q .
  fi
}
