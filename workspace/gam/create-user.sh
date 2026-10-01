#!/bin/bash
# Onboarding step 1: create a Google Workspace account.
#
# usage: create-user.sh [-o /OrgUnit] [-n notify@address] "First" "Last"
#
# Username convention: first initial plus last name, lowercase, letters and digits only; on a
# collision with a different person, a digit suffix (2, 3, ...). The account is created in its
# destination OU (default /Staff), never in the root and moved. The password is random and
# must be changed at first sign-in; with -n it is mailed to that address, otherwise it is shown
# nowhere and the admin issues it another way. GAM sends that mail only through a service account
# with domain-wide delegation; where the tenant grants neither (this lab), -n is reported and the
# account is created without it. Idempotent: running it again for the same person reports the
# existing account and exits 0.

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

usage() { echo "usage: $(basename "$0") [-o /OrgUnit] [-n notify@address] \"First\" \"Last\"" >&2; exit 2; }

ou="/Staff"
notify=""
while getopts "o:n:" opt; do
  case "$opt" in
    o) ou="$OPTARG" ;;
    n) notify="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
first="$1"
last="$2"

domain=$(lab_domain)
[ -n "$domain" ] || die "could not determine the primary domain; is GAM configured and authorized?"

# The convention lives in common.sh (resolve_username): an existing account for this person is
# reported and the script stops; the same username for someone else gets a suffix.
resolved=$(resolve_username "$first" "$last") || die "no usable username for $first $last (names need a letter or digit; nine suffixes tried)"
tab=$(printf '\t')
candidate=${resolved%%"$tab"*}
state=${resolved#*"$tab"}
if [ "$state" = "exists" ]; then
  log "exists: $candidate ($first $last); nothing to do"
  exit 0
fi

# A service account file without a key is the wizard's placeholder where key creation is blocked.
sa_file="${GAMCFGDIR:-$HOME/.gam}/oauth2service.json"
if [ -n "$notify" ] && ! { [ -r "$sa_file" ] && /usr/bin/jq -e '(.private_key // "") | length > 0' "$sa_file" >/dev/null 2>&1; }; then
  log "note: GAM cannot mail the password to $notify: it sends mail only through a service account with domain-wide delegation, which this tenant does not grant; creating without the notification"
  notify=""
  no_mail=1
fi
log "creating $candidate ($first $last) in $ou"
if [ -n "$notify" ]; then
  "$GAM" create user "$candidate" firstname "$first" lastname "$last" ou "$ou" \
    password random changepassword on notify "$notify" || die "create failed"
else
  "$GAM" create user "$candidate" firstname "$first" lastname "$last" ou "$ou" \
    password random changepassword on || die "create failed"
fi

log "verify:"
"$GAM" info user "$candidate" quick 2>/dev/null \
  | grep -E 'First Name|Last Name|Org Unit Path|Account Suspended|Suspension Reason|Must Change Password'
reason=$(suspension_reason "$candidate")
if [ -n "$reason" ]; then
  log "note: Google holds the new account (reason $reason); the user clears it at the first web sign-in, an admin cannot"
fi
if [ "${no_mail:-0}" -eq 1 ]; then
  log "note: issue the initial password by another route: Admin console, Users, $first $last, Reset password, email it; or set one and hand it over with the device"
fi
