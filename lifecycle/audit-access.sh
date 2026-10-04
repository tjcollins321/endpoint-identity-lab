#!/bin/bash
# Access review against the role catalog, read-only. For every account: the role its department
# implies, and what differs from that role. A mismatch is the wrong OU, a missing role group, or
# membership of a group that belongs to another catalog role (the "copied from a teammate" drift).
# A membership that no role grants is a one-off grant: not a mismatch, listed for review, since a
# role change keeps it on purpose. Accounts without a catalog role (administrators, accounts with no
# department) are listed with their groups. Offboarded accounts are skipped; a suspended account
# outside the offboarded OU is a finding. An account whose read fails three times is reported as
# not read and never judged: an empty read is not an empty OU or an empty group list.
#
# usage: audit-access.sh [-q]     -q: findings only, no per-account detail
# Exit 0 when nothing mismatches and every account was read, 1 otherwise.

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

mismatches=0; reviews=0; accounts=0; unread=0
detail() { [ "$quiet" -eq 1 ] || log "    $*"; }
mismatch() { mismatches=$((mismatches + 1)); log "  MISMATCH $1: $2"; }
review()   { reviews=$((reviews + 1)); log "  review   $1: $2"; }
unreadable() { unread=$((unread + 1)); log "  NOT READ $1: $2"; }
# retry_read COMMAND...: the command's output, tried up to three times while it comes back empty.
retry_read() {
  local out="" n=0
  while [ -z "$out" ] && [ "$n" -lt 3 ]; do
    [ "$n" -eq 0 ] || sleep 2
    out=$("$@"); n=$((n + 1))
  done
  printf '%s' "$out"
}

managed=$(role_all_groups | while read -r g; do qualify "$g"; done)
log "== access review against the catalog: $(role_list | tr '\n' ' ')"
for addr in $("$GAM" print users fields primaryemail 2>/dev/null | tail -n +2); do
  accounts=$((accounts + 1))
  # One read of the account for everything judged below.
  json=$(retry_read user_json "$addr")
  ou=$("$JQ" -r '.orgUnitPath // empty' <<< "$json")
  if [ -z "$ou" ]; then
    unreadable "$addr" "the directory read failed three times; not judged"
    continue
  fi
  reason=$("$JQ" -r 'if .suspended then (.suspensionReason // "UNKNOWN") else empty end' <<< "$json")
  if [ "$ou" = "$OFFBOARDED_OU" ]; then
    detail "$addr: offboarded ($("$JQ" -r '.notes.value // empty' <<< "$json")); skipped"
    [ -n "$reason" ] || mismatch "$addr" "in $OFFBOARDED_OU but not suspended"
    continue
  fi
  [ -z "$reason" ] || [ "$reason" != "ADMIN" ] || mismatch "$addr" "suspended by an administrator but in $ou, not $OFFBOARDED_OU; finish the offboarding"
  dept=$("$JQ" -r '.organizations[0].department // empty' <<< "$json")
  role=$(role_for_department "$dept" || echo "")
  # The listing prints its header even for an account with no groups, so empty means it failed.
  groups_csv=$(retry_read "$GAM" user "$addr" print groups 2>/dev/null)
  if [ -z "$groups_csv" ]; then
    unreadable "$addr" "the group read failed three times; not judged"
    continue
  fi
  current=$(printf '%s\n' "$groups_csv" | tail -n +2 | cut -d, -f2)
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
if [ "$unread" -eq 0 ]; then
  log "== $accounts accounts, $mismatches mismatch(es), $reviews item(s) to review"
else
  log "== $accounts accounts, $mismatches mismatch(es), $reviews item(s) to review, $unread not read"
fi
[ "$mismatches" -eq 0 ] && [ "$unread" -eq 0 ]
