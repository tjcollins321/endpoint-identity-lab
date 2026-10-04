#!/bin/bash
# Offboarding step 3: delete the account and release its license.
#
# usage: delete.sh [-f] user
#
# Refuses unless the account is suspended, a completed Drive transfer from it exists, it is in
# the leavers' OU, and the deletion date lifecycle/offboard.sh wrote into its note has arrived,
# which is the order the offboarding produces; -f skips the checks. An account with no date in its
# note (offboarded by hand) is not held back. A deleted account can be restored from the Admin
# console for 20 days. Idempotent: a missing account is reported as already absent (exit 0).

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

usage() { echo "usage: $(basename "$0") [-f] user" >&2; exit 2; }

force=0
while getopts "f" opt; do
  case "$opt" in
    f) force=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage

user=$(qualify "$1")
if ! user_exists "$user"; then
  log "already absent: $user; nothing to do"
  exit 0
fi

offboarded_ou="${OFFBOARDED_OU:-/Offboarded}"
if [ "$force" -eq 0 ]; then
  user_suspended "$user" || die "$user is active; run suspend.sh first, or use -f"
  drive_transferred "$user" || die "no completed Drive transfer from $user; run transfer-drive.sh first, or use -f"
  info=$("$GAM" info user "$user" quick 2>/dev/null)
  ou=$(printf '%s\n' "$info" | sed -n 's/^ *Google Org Unit Path: //p' | head -1)
  [ "$ou" = "$offboarded_ou" ] || die "$user is in $ou, not $offboarded_ou; run lifecycle/offboard.sh first, or use -f"
  delete_on=$(printf '%s\n' "$info" | sed -n 's/.*delete on or after \([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p' | head -1)
  if [ -n "$delete_on" ] && [ "$(date '+%Y-%m-%d')" \< "$delete_on" ]; then
    die "$user is in its retention period; delete on or after $delete_on, or use -f"
  fi
fi

log "deleting $user"
"$GAM" delete user "$user" || die "delete failed"

log "verify:"
if user_exists "$user"; then
  die "$user still exists after the delete call"
fi
echo "User: $user, Does not exist"
