#!/bin/bash
# Offboarding step 1: cut access now, keep the data.
#
# usage: suspend.sh user
#
# Order matters: deprovision first (delete app passwords, backup codes, and OAuth tokens; sign
# out every session), then suspend. Mail, Drive, and Calendar stay intact for transfer-drive.sh
# and delete.sh. Idempotent: an account an administrator already suspended is reported and left
# alone (exit 0). An account under one of Google's own holds (for example WEB_LOGIN_REQUIRED on
# a fresh account) is still deprovisioned and suspended; Google keeps showing its own reason.

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

[ $# -eq 1 ] || { echo "usage: $(basename "$0") user" >&2; exit 2; }

user=$(qualify "$1")
user_exists "$user" || die "no such account: $user"

reason=$(suspension_reason "$user")
if [ "$reason" = "ADMIN" ]; then
  log "already suspended by an administrator: $user; nothing to do"
  exit 0
fi
if [ -n "$reason" ]; then
  log "note: $user is under a Google hold (reason $reason); suspending anyway so the offboarding is recorded"
fi

log "deprovisioning $user: app passwords, backup codes, OAuth tokens, sign-out"
if ! "$GAM" user "$user" deprovision signout; then
  log "warning: deprovision reported a failure above; continuing with the suspension"
fi

log "suspending $user"
"$GAM" suspend user "$user" || die "suspend failed"

# A suspension can take a few seconds to read back, so the verify retries briefly.
tries=0
while ! user_suspended "$user" && [ "$tries" -lt 6 ]; do
  tries=$((tries + 1))
  sleep 3
done
log "verify:"
"$GAM" check suspended "$user"
user_suspended "$user" || die "account is not suspended after the call"
