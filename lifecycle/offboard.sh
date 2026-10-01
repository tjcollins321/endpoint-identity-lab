#!/bin/bash
# Offboard a leaver. The order is the point: cut access first while every byte of data stays where
# it is, move the data to someone who stays, remove access, deal with the devices, and leave the
# deletion to delete.sh after the retention period. Every step reads before it writes, so a second
# run reports ok and changes nothing; a failed suspend stops the run, anything after it continues
# and is reported. Ends with a read-back, the steps a human still does, and the count of failures.
#
# usage: offboard.sh [-e] [-m new-owner] [-y] [-D] [-n] <user>
#   -e  emergency form: cut access and stop; the rest can follow
#   -m  who receives the Drive files and the calendars (usually the manager)
#   -y  lock a Fleet-managed Mac without asking
#   -D  skip the device steps
#   -n  dry run
# Exit 0 all ok, 1 a step failed, 2 usage error.

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

usage() { echo "usage: $(basename "$0") [-e] [-m new-owner] [-y] [-D] [-n] <user>" >&2; exit 2; }

emergency=0; owner=""; yes=0; skip_device=0
while getopts "em:yDn" opt; do
  case "$opt" in
    e) emergency=1 ;;
    m) owner="$OPTARG" ;;
    y) yes=1 ;;
    D) skip_device=1 ;;
    n) DRYRUN=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
addr=$(qualify "$1")
user_exists "$addr" || die "$addr does not exist"
if [ -n "$owner" ]; then
  owner=$(qualify "$owner")
  user_exists "$owner" || die "new owner $owner does not exist"
  [ "$owner" != "$addr" ] || die "the new owner cannot be the leaver"
fi
admin=$(lab_admin)
role=$(role_for_department "$(user_department "$addr")" || echo "")
log "== offboarding $addr (${role:-no catalog role})$([ "$emergency" -eq 1 ] && echo ', emergency form: access only')"

# 1. Cut access: app passwords, backup codes, and tokens revoked, sessions signed out, suspended.
reason=$(suspension_reason "$addr")
if [ "$reason" = "ADMIN" ]; then
  ok "already suspended by an administrator"
elif do_cmd "cut access (revoke app passwords, backup codes, tokens; sign out everywhere; suspend)" "$GAM_DIR/suspend.sh" "$addr"; then
  [ "$DRYRUN" -eq 1 ] || changed "access cut: $addr suspended"
else
  fail "suspend failed; stopping, since nothing else is safe while the person can still sign in"
  summary; exit 1
fi
if [ "$emergency" -eq 1 ]; then
  manual "finish the offboarding when the paperwork catches up: $(basename "$0") -m <new-owner> $addr"
  summary; exit $?
fi

# 2. Data to someone who stays: Drive and Calendar through the Data Transfer API (admin-level).
if [ -z "$owner" ]; then
  warn "no new owner given (-m): Drive and Calendar are not transferred on this run"
  manual "transfer Drive and Calendar: rerun with -m <new-owner>; the directory names $(user_manager "$addr") as the manager"
else
  if drive_transferred "$addr" "$owner"; then
    ok "Drive already transferred to $owner"
  elif do_cmd "transfer Drive ownership to $owner" "$GAM_DIR/transfer-drive.sh" "$addr" "$owner"; then
    [ "$DRYRUN" -eq 1 ] || changed "Drive transferred to $owner"
  else
    fail "Drive transfer to $owner failed"
  fi
  if calendar_transferred "$addr" "$owner"; then
    ok "Calendar already transferred to $owner"
  elif do_cmd "transfer the calendars to $owner, releasing room bookings" "$GAM" create datatransfer "$addr" calendar "$owner" release_resources wait 5 24; then
    [ "$DRYRUN" -eq 1 ] || changed "Calendar transferred to $owner"
  else
    fail "Calendar transfer to $owner failed"
  fi
fi
manual "mail: forward new mail to ${owner:-the manager} with a Gmail routing rule, which has no API: Admin console, Apps, Google Workspace, Gmail, Routing, add a rule for envelope recipient $addr (inbound and internal), Modify message, Also deliver to ${owner:-the manager}; the mailbox keeps its copy for retention"

# 3. Access removed: every group membership.
groups=$(user_groups "$addr")
if [ -z "$groups" ]; then
  ok "no group memberships"
else
  while read -r g; do
    [ -n "$g" ] || continue
    if do_cmd "remove $addr from $g" "$GAM" update group "$g" delete member "$addr"; then
      [ "$DRYRUN" -eq 1 ] || changed "removed from $g"
    else
      fail "could not remove $addr from $g"
    fi
  done <<< "$groups"
fi

# 4. The leavers' OU, with the date and the earliest deletion date in the account note.
delete_on=$(days_from_today "$RETENTION_DAYS")
ou=$(user_ou "$addr")
if [ "$ou" = "$OFFBOARDED_OU" ]; then
  note=$(user_note "$addr")
  ok "in $OFFBOARDED_OU${note:+ ($note)}"
  d=$(printf '%s' "$note" | sed -n 's/.*delete on or after \([0-9-]*\).*/\1/p')
  [ -z "$d" ] || delete_on="$d"
elif do_cmd "move $addr from $ou to $OFFBOARDED_OU" "$GAM" update user "$addr" ou "$OFFBOARDED_OU" note "Offboarded $(today) by offboard.sh; delete on or after $delete_on"; then
  [ "$DRYRUN" -eq 1 ] || changed "moved to $OFFBOARDED_OU; delete on or after $delete_on"
else
  fail "could not move $addr to $OFFBOARDED_OU"
fi
manual "on or after $delete_on: workspace/gam/delete.sh $addr (it refuses unless suspended, in $OFFBOARDED_OU, with Drive transferred), then remove the routing rule"

# 5. The work account on personal devices under Workspace management.
mobiles=$(mobiles_of "$addr")
if [ -z "$mobiles" ]; then
  ok "no personal devices under Workspace mobile management"
else
  while IFS="$(printf '\t')" read -r rid mstatus model; do
    [ -n "$rid" ] || continue
    case "$mstatus" in
      APPROVED|PENDING|BLOCKED)
        if do_cmd "wipe the work account from $model ($mstatus)" "$GAM" update mobile "$rid" action admin_account_wipe; then
          [ "$DRYRUN" -eq 1 ] || changed "account wipe sent to $model"
        else
          fail "account wipe failed for $model"
        fi ;;
      *) ok "$model: $mstatus, nothing to do" ;;
    esac
  done <<< "$mobiles"
fi

# 6. Company devices: a Fleet-managed Mac is locked and returned to IT custody; a Chromebook is
#    disabled; Jamf Now devices are a console step.
touched_macs=""
if [ "$skip_device" -eq 1 ]; then
  ok "device steps skipped (-D)"
else
  macs=$(fleet_hosts_by_email "$addr")
  if [ -z "$macs" ]; then
    ok "no Fleet-managed Mac mapped to $addr"
  else
    while IFS="$(printf '\t')" read -r hid serial hname; do
      [ -n "$hid" ] || continue
      touched_macs="$touched_macs $serial"
      host=$(fleet_host_json "$serial")
      lock=$(fleet_host_lock "$host"); pend=$(fleet_host_pending "$host")
      if [ "$lock" = "locked" ] || [ "$pend" = "lock" ]; then
        ok "$hname ($serial) is $lock${pend:+, pending $pend}"
      elif [ "$DRYRUN" -eq 1 ]; then
        would "lock $hname ($serial) through Fleet (it shows a PIN screen until unlocked)"
      else
        go=$yes
        if [ "$go" -eq 0 ] && [ -t 0 ]; then
          printf 'Lock %s (%s) now? It shows a PIN screen until IT unlocks it. [y/N] ' "$hname" "$serial"
          read -r ans
          case "$ans" in y|Y) go=1 ;; esac
        fi
        if [ "$go" -eq 1 ]; then
          if "$FLEETCTL" mdm lock --host "$serial"; then changed "lock sent to $hname ($serial)"; else fail "lock failed for $hname"; fi
        else
          manual "lock the Mac: fleetctl mdm lock --host $serial (not sent: no confirmation; rerun with -y)"
        fi
      fi
      for l in $(role_all_labels); do
        if fleet_host_labels "$host" | grep -qx "$l"; then
          if do_cmd "remove $hname from the $l label" fleet_remove_label "$hid" "$l"; then [ "$DRYRUN" -eq 1 ] || changed "$hname removed from $l"; else fail "could not remove $hname from $l"; fi
        fi
      done
      if do_cmd "return $hname to IT custody (mapping -> $admin)" fleet_set_mapping "$hid" "$admin"; then [ "$DRYRUN" -eq 1 ] || changed "$hname mapped to $admin"; else fail "could not remap $hname"; fi
      manual "when the Mac ($hname, $serial) returns: fleetctl mdm unlock --host $serial shows the PIN; then re-provision it for the next person (runbooks/mac-provisioning-fleet.md)"
    done <<< "$macs"
  fi
  croses=$(cros_by_user "$addr")
  if [ -z "$croses" ]; then
    ok "no Chromebook annotated to $addr"
  else
    while IFS="$(printf '\t')" read -r cid cserial cstatus _; do
      [ -n "$cid" ] || continue
      if [ "$cstatus" = "DISABLED" ]; then
        ok "Chromebook $cserial is disabled"
      elif do_cmd "disable Chromebook $cserial (it shows the return message until re-enabled)" "$GAM" update cros "$cid" action disable; then
        [ "$DRYRUN" -eq 1 ] || changed "Chromebook $cserial disabled"
      else
        fail "could not disable Chromebook $cserial"
      fi
      manual "when the Chromebook ($cserial) returns: re-enable and reassign it (gam update cros $cid action reenable; lifecycle/onboard.sh -d $cid ...), or retire it (gam update cros $cid action deprovision_retiring_device, then gam issuecommand cros $cid command remote_powerwash)"
    done <<< "$croses"
  fi
  manual "Jamf Now has no API: if $addr holds a device enrolled there (an iPad), lock it, then wipe or unenroll it in the console (runbooks/ipados-enrollment-jamf.md)"
fi

# 7. Application accounts that identity does not remove: the Fleet console user JIT created.
fid=$(fleet_user_id "$addr")
if [ -z "$fid" ]; then
  ok "no Fleet console account"
elif do_cmd "delete the Fleet console account (just-in-time provisioning creates and never removes)" fleet_delete_user "$fid"; then
  [ "$DRYRUN" -eq 1 ] || changed "Fleet console account deleted"
else
  fail "could not delete the Fleet console account $fid"
fi

# 8. Read-back.
log "== verify $addr"
log "  suspended: $(suspension_reason "$addr")"
log "  OU: $(user_ou "$addr")"
log "  groups: $(user_groups "$addr" | tr '\n' ' ')"
log "  transfers completed: $(transfers_from "$addr" | tr '\t' '>' | tr '\n' ' ')"
log "  personal devices under management: $(mobiles_of "$addr" | grep -c .)"
for serial in $touched_macs; do
  host=$(fleet_host_json "$serial")
  pend=$(fleet_host_pending "$host")
  log "  Fleet host $serial: $(fleet_host_lock "$host")${pend:+ (pending $pend)}; mapping $(fleet_mapping_of "$(fleet_host_id "$host")"); role labels: $(fleet_host_labels "$host" | grep '^role-' | tr '\n' ' ')"
done
while IFS="$(printf '\t')" read -r cid cserial cstatus _; do
  [ -n "$cid" ] && log "  Chromebook $cserial: $cstatus"
done <<< "$(cros_by_user "$addr")"
log "  Fleet console account: $(fleet_user_id "$addr" | grep -q . && echo present || echo none)"
summary
