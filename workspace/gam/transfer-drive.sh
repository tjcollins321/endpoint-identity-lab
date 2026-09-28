#!/bin/bash
# Offboarding step 2: hand the leaver's Drive files to someone who stays.
#
# usage: transfer-drive.sh leaver new-owner
#
# Uses the Admin SDK Data Transfer API, the same mechanism as the Admin console's Transfer
# ownership button, so it runs under the admin's own authorization and needs no access to the
# leaver's account. Transfers private and shared files. Waits up to two minutes for completion.
# Idempotent: a completed transfer between the same two accounts is reported, not repeated.

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

[ $# -eq 2 ] || { echo "usage: $(basename "$0") leaver new-owner" >&2; exit 2; }

old=$(qualify "$1")
new=$(qualify "$2")
user_exists "$old" || die "no such account: $old"
user_exists "$new" || die "no such account: $new"
[ "$old" != "$new" ] || die "leaver and new owner are the same account"

if drive_transferred "$old" "$new"; then
  log "already transferred: Drive of $old to $new; nothing to do"
  "$GAM" print datatransfers olduser "$old" newuser "$new" status completed 2>/dev/null
  exit 0
fi

log "transferring Drive ownership: $old to $new (private and shared files)"
"$GAM" create datatransfer "$old" drive "$new" all wait 5 24 || die "transfer request failed"

log "verify:"
"$GAM" print datatransfers olduser "$old" newuser "$new" status completed 2>/dev/null
drive_transferred "$old" "$new" || die "no completed transfer yet; check with: gam print datatransfers olduser $old"
