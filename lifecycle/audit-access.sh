#!/bin/bash
# Access review against the role catalog, read-only. For every account: the role its department
# implies, and what differs from that role. A mismatch is the wrong OU, a missing role group, or
# membership of a group that belongs to another catalog role (the "copied from a teammate" drift).
# A membership that no role grants is a one-off grant: not a mismatch, listed for review, since a
# role change keeps it on purpose. Accounts without a catalog role (administrators, accounts with no
# department) are listed with their groups. Offboarded accounts are skipped; a suspended account
# outside the offboarded OU is a finding.
#
# usage: audit-access.sh [-q]     -q: findings only, no per-account detail
# Exit 0 when nothing mismatches, 1 otherwise.

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

quiet=0
while getopts "q" opt; do
  case "$opt" in
    q) quiet=1 ;;
    *) echo "usage: $(basename "$0") [-q]" >&2; exit 2 ;;
  esac
done

mismatches=0; reviews=0; accounts=0
detail() { [ "$quiet" -eq 1 ] || log "    $*"; }
mismatch() { mismatches=$((mismatches + 1)); log "  MISMATCH $1: $2"; }
review()   { reviews=$((reviews + 1)); log "  review   $1: $2"; }

managed=$(role_all_groups | while read -r g; do qualify "$g"; done)
log "== access review against the catalog: $(role_list | tr '\n' ' ')"
for addr in $("$GAM" print users fields primaryemail 2>/dev/null | tail -n +2); do
  accounts=$((accounts + 1))
  ou=$(user_ou "$addr")
  reason=$(suspension_reason "$addr")
  if [ "$ou" = "$OFFBOARDED_OU" ]; then
    detail "$addr: offboarded ($(user_note "$addr")); skipped"
    [ -n "$reason" ] || mismatch "$addr" "in $OFFBOARDED_OU but not suspended"
    continue
  fi
  [ -z "$reason" ] || [ "$reason" != "ADMIN" ] || mismatch "$addr" "suspended by an administrator but in $ou, not $OFFBOARDED_OU; finish the offboarding"
  dept=$(user_department "$addr")
  role=$(role_for_department "$dept" || echo "")
  current=$(user_groups "$addr")
  if [ -z "$role" ]; then
    review "$addr" "no catalog role (department '${dept:-none}', OU $ou); groups: $(printf '%s' "$current" | tr '\n' ' ')"
    continue
  fi
  role_load "$role"
  detail "$addr: $ROLE_NAME (OU $ou; groups $(printf '%s' "$current" | tr '\n' ' '))"
  [ "$ou" = "$ROLE_OU" ] || mismatch "$addr" "in $ou, the $ROLE_NAME role is $ROLE_OU"
  for g in $ROLE_GROUPS; do
    printf '%s\n' "$current" | grep -qix "$(qualify "$g")" || mismatch "$addr" "not in $g, which the $ROLE_NAME role grants"
  done
  for g in $current; do
    if printf '%s\n' "$ROLE_GROUPS" | tr ' ' '\n' | while read -r w; do qualify "$w"; done | grep -qix "$g"; then
      :
    elif printf '%s\n' "$managed" | grep -qix "$g"; then
      mismatch "$addr" "in $g, which belongs to another role, not $ROLE_NAME"
    else
      review "$addr" "one-off grant outside the catalog: $g"
    fi
  done
done
log "== $accounts accounts, $mismatches mismatch(es), $reviews item(s) to review"
[ "$mismatches" -eq 0 ]
