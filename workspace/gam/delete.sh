#!/bin/bash
# Offboarding step 3: delete the account and release its license.
#
# usage: delete.sh [-f] user
#
# Refuses unless the account is suspended and a completed Drive transfer from it exists, which
# is the order suspend.sh and transfer-drive.sh produce; -f skips both checks. A deleted account
# can be restored from the Admin console for 20 days. Idempotent: a missing account is reported
# as already absent (exit 0).

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

if [ "$force" -eq 0 ]; then
  user_suspended "$user" || die "$user is active; run suspend.sh first, or use -f"
  drive_transferred "$user" || die "no completed Drive transfer from $user; run transfer-drive.sh first, or use -f"
fi

log "deleting $user"
"$GAM" delete user "$user" || die "delete failed"

log "verify:"
if user_exists "$user"; then
  die "$user still exists after the delete call"
fi
echo "User: $user, Does not exist"
