#!/bin/bash
# Onboarding step 2 (and reorgs): grant access by adding an account to groups.
#
# usage: add-to-groups.sh user group [group ...]
#
# Bare names take the tenant's primary domain. Membership is checked before each add, so a
# second run changes nothing. Members are added with the MEMBER role; owners and managers are
# deliberate console changes. Exits 1 if any group was missing or an add failed.

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

[ $# -ge 2 ] || { echo "usage: $(basename "$0") user group [group ...]" >&2; exit 2; }

user=$(qualify "$1")
shift
user_exists "$user" || die "no such account: $user"

is_member() {
  "$GAM" print group-members group "$1" fields email 2>/dev/null | grep -qix "$1,$2"
}

failed=0
for g in "$@"; do
  group=$(qualify "$g")
  if ! group_exists "$group"; then
    echo "error: no such group: $group" >&2
    failed=1
    continue
  fi
  if is_member "$group" "$user"; then
    log "member already: $user in $group"
    continue
  fi
  log "adding $user to $group"
  if ! "$GAM" update group "$group" add member "$user"; then
    failed=1
  fi
done

log "verify:"
for g in "$@"; do
  group=$(qualify "$g")
  if is_member "$group" "$user"; then
    echo "  $user is a member of $group"
  else
    echo "  $user is NOT a member of $group"
    failed=1
  fi
done
exit "$failed"
