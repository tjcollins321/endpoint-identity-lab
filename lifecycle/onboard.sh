#!/bin/bash
# Onboard a new hire by role: the account in the role's OU with its attributes, the role's groups,
# the welcome kit, and the device the role entitles (a Mac mapped and labeled in Fleet, a Chromebook
# annotated and moved to the device OU, or nothing for a BYOD role). Idempotent: every step reads
# before it writes, and a second run reports ok on every line. Ends with a read-back, the manual
# steps a human still does, and the count of failures.
#
# usage: onboard.sh [-p personal@] [-m manager] [-s YYYY-MM-DD] [-d serial-or-device-id] [-W] [-D] [-n] <role> First Last
#   -p  personal address for the initial password and the welcome kit (else the manager, else the work address)
#   -m  manager (username or address): the directory relation, Drive and Calendar go there at offboarding
#   -s  start date (default today)
#   -d  the issued device: a Mac's serial (Fleet) or a Chromebook's device id (Workspace)
#   -W  resend the welcome kit even if the account existed
#   -D  skip the device step
#   -n  dry run: read everything, change nothing
# Exit 0 all ok, 1 a step failed, 2 usage or catalog error.

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

usage() {
  echo "usage: $(basename "$0") [-p personal@] [-m manager] [-s YYYY-MM-DD] [-d serial-or-device-id] [-W] [-D] [-n] <role> First Last" >&2
  echo "roles: $(role_list | tr '\n' ' ')" >&2
  exit 2
}

personal=""; manager=""; start=""; device=""; resend=0; skip_device=0
while getopts "p:m:s:d:WDn" opt; do
  case "$opt" in
    p) personal="$OPTARG" ;;
    m) manager="$OPTARG" ;;
    s) start="$OPTARG" ;;
    d) device="$OPTARG" ;;
    W) resend=1 ;;
    D) skip_device=1 ;;
    n) DRYRUN=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 3 ] || usage
role="$1"; first="$2"; last="$3"
role_load "$role"
[ -n "$start" ] || start=$(today)
if [ -n "$manager" ]; then
  manager=$(qualify "$manager")
  user_exists "$manager" || die "manager $manager does not exist"
fi

log "== onboarding $first $last as $ROLE_NAME (OU $ROLE_OU, groups: $ROLE_GROUPS, device: $ROLE_DEVICE), start $start"

# 1. The account, in the role's OU. An account that exists for this person is left alone; if it
#    sits in another OU that is a role change, not an onboarding.
resolved=$(resolve_username "$first" "$last") || die "no usable username for $first $last"
tab=$(printf '\t')
addr=${resolved%%"$tab"*}
state=${resolved#*"$tab"}
created=0
present=1
if [ "$state" = "exists" ]; then
  ok "account $addr exists"
  ou=$(user_ou "$addr")
  if [ "$ou" = "$OFFBOARDED_OU" ]; then
    fail "$addr was offboarded; a rehire is gam unsuspend user $addr, then change-role.sh $addr $role"
  elif [ "$ou" != "$ROLE_OU" ]; then
    fail "$addr is in $ou, the $ROLE_NAME role is $ROLE_OU; use change-role.sh for a transfer"
  else
    ok "in $ROLE_OU"
  fi
else
  if [ -n "$personal" ]; then
    do_cmd "create $addr in $ROLE_OU, password mailed to $personal" "$GAM_DIR/create-user.sh" -o "$ROLE_OU" -n "$personal" "$first" "$last"
  else
    do_cmd "create $addr in $ROLE_OU (no personal address: the admin issues the password by hand)" "$GAM_DIR/create-user.sh" -o "$ROLE_OU" "$first" "$last"
  fi
  rc=$?
  if [ "$DRYRUN" -eq 1 ]; then
    present=0
  elif ! user_exists "$addr"; then
    fail "create failed for $addr"
    summary; exit 1
  else
    created=1
    changed "created $addr in $ROLE_OU"
    [ "$rc" -eq 0 ] || warn "create-user.sh reported an error after the account appeared; see above"
    if [ -n "$personal" ] && gam_can_send_mail; then
      ok "initial password mailed to $personal"
    else
      manual "issue the initial password: Admin console, Users, $first $last, Reset password, email it${personal:+ to $personal}; or set one and hand it over with the device (GAM mails it only through domain-wide delegation, which this tenant does not grant)"
    fi
  fi
fi

# 2. Directory attributes: title and department from the role, the manager relation.
if [ "$present" -eq 1 ]; then
  if [ "$(user_title "$addr")" = "$ROLE_TITLE" ] && [ "$(user_department "$addr")" = "$ROLE_DEPARTMENT" ]; then
    ok "title $ROLE_TITLE, department $ROLE_DEPARTMENT"
  else
    if do_cmd "set title $ROLE_TITLE, department $ROLE_DEPARTMENT" "$GAM" update user "$addr" organization type work name "$ORG_NAME" title "$ROLE_TITLE" department "$ROLE_DEPARTMENT" primary; then
      changed "title $ROLE_TITLE, department $ROLE_DEPARTMENT"
    else
      fail "could not set title and department on $addr"
    fi
  fi
  if [ -n "$manager" ]; then
    if [ "$(user_manager "$addr")" = "$manager" ]; then
      ok "manager $manager"
    elif do_cmd "set manager $manager" "$GAM" update user "$addr" relation manager "$manager"; then
      changed "manager $manager"
    else
      fail "could not set the manager on $addr"
    fi
  fi
else
  would "set title $ROLE_TITLE, department $ROLE_DEPARTMENT${manager:+, manager $manager}"
fi

# 3. Access: the role's groups. add-to-groups.sh skips memberships that exist and reads back.
if [ "$present" -eq 1 ]; then
  # shellcheck disable=SC2086
  if do_cmd "add $addr to: $ROLE_GROUPS" "$GAM_DIR/add-to-groups.sh" "$addr" $ROLE_GROUPS; then
    ok "groups: $ROLE_GROUPS"
  else
    fail "a group add failed; see above"
  fi
else
  would "add $addr to: $ROLE_GROUPS"
fi

# 4. The welcome kit, on the run that created the account or on request.
if [ "$created" -eq 1 ] || [ "$resend" -eq 1 ] || [ "$DRYRUN" -eq 1 ]; then
  to="$personal"
  if [ -z "$to" ] && [ -n "$manager" ]; then to="$manager"; warn "no personal address: the welcome kit goes to the manager, $manager"; fi
  if [ -z "$to" ]; then to="$addr"; warn "no personal address or manager: the welcome kit goes to the new work address, which the person cannot read before the first sign-in"; fi
  mgr_display="$manager"
  if [ -n "$manager" ]; then mgr_display="$(user_fullname "$manager") ($manager)"; else mgr_display="your manager"; fi
  if [ "$DRYRUN" -eq 1 ]; then
    if gam_can_send_mail; then would "send the welcome kit for $ROLE_NAME to $to"; else would "render the welcome kit for $ROLE_NAME to the outbox for hand-sending to $to (GAM cannot send mail here)"; fi
  elif out=$(send_welcome "$to" "$first" "$addr" "$mgr_display" "$start"); then
    if [ -n "$out" ] && [ -f "$REPO_DIR/$out" ]; then
      changed "welcome kit rendered to $out (GAM sends mail only through domain-wide delegation, which this tenant does not grant)"
      manual "send $out from the admin mailbox to $to"
    else
      changed "welcome kit sent to $to"
    fi
  else
    fail "welcome kit not produced for $to; rerun with -W"
  fi
else
  ok "welcome kit: sent only on the run that creates the account, or with -W"
fi

# 5. The device the role entitles.
if [ "$skip_device" -eq 1 ]; then
  ok "device step skipped (-D)"
else
  case "$ROLE_DEVICE" in
    mac)
      if [ -z "$device" ]; then
        manual "issue a Mac: provision it into Fleet (runbooks/mac-provisioning-fleet.md), then rerun with -d <serial> to assign it to $addr"
      else
        host=$(fleet_host_json "$device")
        if [ -z "$host" ] || [ "$host" = "null" ]; then
          fail "no Fleet host with identifier $device"
        else
          hid=$(fleet_host_id "$host"); hname=$(fleet_host_name "$host")
          if [ "$(fleet_mapping_of "$hid")" = "$addr" ]; then
            ok "Fleet host $hname ($device) is mapped to $addr"
          elif do_cmd "map Fleet host $hname ($device) to $addr" fleet_set_mapping "$hid" "$addr"; then
            [ "$DRYRUN" -eq 1 ] || changed "Fleet host $hname ($device) mapped to $addr"
          else
            fail "could not map Fleet host $hname to $addr"
          fi
          if fleet_host_labels "$host" | grep -qx "$ROLE_FLEET_LABEL"; then
            ok "$hname carries the $ROLE_FLEET_LABEL label"
          elif do_cmd "add $hname to the $ROLE_FLEET_LABEL label (its role software follows)" fleet_add_label "$hid" "$ROLE_FLEET_LABEL"; then
            [ "$DRYRUN" -eq 1 ] || changed "$hname added to $ROLE_FLEET_LABEL"
          else
            fail "could not add $hname to $ROLE_FLEET_LABEL (does the label exist? fleet/gitops/labels/)"
          fi
          manual "hand the Mac ($hname) to $first on $start; at the first login they run scripts/mac-onboard.sh $role"
        fi
      fi
      ;;
    chromeos)
      if [ -z "$device" ]; then
        manual "issue a Chromebook: enroll it (runbooks/chromeos-enrollment.md), then rerun with -d <device id> to assign it to $addr"
      else
        cj=$(cros_json "$device")
        if [ -z "$cj" ]; then
          fail "no ChromeOS device with id or serial $device"
        else
          cid=$(cros_field "$cj" deviceId); cuser=$(cros_field "$cj" annotatedUser); cou=$(cros_field "$cj" orgUnitPath); cserial=$(cros_field "$cj" serialNumber)
          if [ "$cuser" = "$addr" ]; then
            ok "Chromebook $cserial is annotated to $addr"
          elif do_cmd "annotate Chromebook $cserial with user $addr" "$GAM" update cros "$cid" user "$addr"; then
            [ "$DRYRUN" -eq 1 ] || changed "Chromebook $cserial annotated to $addr"
          else
            fail "could not annotate Chromebook $cserial"
          fi
          if [ "$cou" = "$DEVICE_OU" ]; then
            ok "Chromebook $cserial is in $DEVICE_OU"
          elif do_cmd "move Chromebook $cserial from $cou to $DEVICE_OU" "$GAM" update cros "$cid" ou "$DEVICE_OU"; then
            [ "$DRYRUN" -eq 1 ] || changed "Chromebook $cserial moved to $DEVICE_OU"
          else
            fail "could not move Chromebook $cserial to $DEVICE_OU"
          fi
          manual "hand the Chromebook ($cserial) to $first on $start; user policy follows the $ROLE_OU OU, checked at chrome://policy after the first sign-in"
        fi
      fi
      ;;
    byod)
      ok "no company device for $ROLE_NAME; the welcome kit says what the company controls on $first's own computer"
      ;;
  esac
fi

# 6. Read-back.
log "== verify $addr"
if [ "$present" -eq 1 ]; then
  log "  OU: $(user_ou "$addr") (role: $ROLE_OU)"
  reason=$(suspension_reason "$addr")
  if [ -n "$reason" ]; then log "  suspended: $reason (Google's hold clears at the first web sign-in)"; else log "  active"; fi
  log "  title: $(user_title "$addr"); department: $(user_department "$addr"); manager: $(user_manager "$addr")"
  for g in $ROLE_GROUPS; do
    if [ "$DRYRUN" -eq 1 ]; then
      if user_in_group "$addr" "$g"; then log "  group $g: member"; else log "  group $g: not a member (dry run)"; fi
    elif user_in_group_settled "$addr" "$g" 4; then log "  group $g: member"; else log "  group $g: MISSING"; fail "not a member of $g"; fi
  done
  log "  2-step enrolled: $(user_2sv "$addr")"
  case "$ROLE_DEVICE" in
    mac) [ -z "$device" ] || { host=$(fleet_host_json "$device"); log "  Fleet host $device: mapping $(fleet_mapping_of "$(fleet_host_id "$host")"); labels: $(fleet_host_labels "$host" | grep '^role-' | tr '\n' ' ')"; } ;;
    chromeos) [ -z "$device" ] || { cj=$(cros_json "$device"); log "  Chromebook $(cros_field "$cj" serialNumber): user $(cros_field "$cj" annotatedUser); OU $(cros_field "$cj" orgUnitPath); status $(cros_field "$cj" status)"; } ;;
  esac
else
  log "  (dry run: the account does not exist yet)"
fi
manual "after the first sign-in, confirm 2-Step Verification enrollment: gam info user $addr shows 2-step enrolled"
summary
