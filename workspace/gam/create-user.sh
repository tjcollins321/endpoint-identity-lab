#!/bin/bash
# Onboarding step 1: create a Google Workspace account.
#
# usage: create-user.sh [-o /OrgUnit] [-n notify@address] "First" "Last"
#
# Username convention: first initial plus last name, lowercase, letters and digits only; on a
# collision with a different person, a digit suffix (2, 3, ...). The account is created in its
# destination OU (default /Staff), never in the root and moved. The password is random and
# must be changed at first sign-in; with -n it is mailed to that address by Google, otherwise it
# is shown nowhere and the admin issues a reset. Idempotent: running it again for the same
# person reports the existing account and exits 0.

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

initial=$(printf '%s' "$first" | cut -c1 | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
surname=$(printf '%s' "$last" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
base="$initial$surname"
[ -n "$base" ] || die "names must contain at least one letter or digit each"

# Existing account for this person: report it and stop. Same username for someone else: suffix.
tab=$(printf '\t')
n=1
while [ "$n" -le 9 ]; do
  if [ "$n" -eq 1 ]; then candidate="$base@$domain"; else candidate="$base$n@$domain"; fi
  names=$(user_names "$candidate")
  if [ -z "$names" ]; then
    break
  fi
  have_first=${names%%"$tab"*}
  have_last=${names#*"$tab"}
  if [ "$have_first" = "$first" ] && [ "$have_last" = "$last" ]; then
    log "exists: $candidate ($first $last); nothing to do"
    exit 0
  fi
  log "taken: $candidate belongs to $have_first $have_last; trying the next suffix"
  n=$((n + 1))
done
[ "$n" -le 9 ] || die "no free username for $base@$domain after nine attempts"

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
