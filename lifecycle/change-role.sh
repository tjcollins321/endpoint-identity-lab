#!/bin/bash
# Move an account to another role (a transfer or a reorg): the OU if it differs, the groups the new
# role grants added and the groups other catalog roles grant removed, title and department updated,
# and the device's role label moved in Fleet, or the device reclaimed when the new role entitles a
# different class. Groups that no role grants are one-off grants: kept and reported, never removed
# (-S removes everything not in the new role, for a start-clean transfer). No stored "current role":
# the catalog is the truth and the script converges the account to it. Idempotent.
#
# usage: change-role.sh [-t "Title"] [-m manager] [-d serial-or-device-id] [-S] [-D] [-n] <user> <new-role>
#   -t  title, when the role's default is not right for this person
#   -m  manager (username or address)
#   -d  a newly issued device for the new role (a Mac serial or a Chromebook device id)
#   -S  strict: remove every group not in the new role, one-off grants included
#   -D  skip the device step
#   -n  dry run
# Exit 0 all ok, 1 a step failed, 2 usage or catalog error.

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

usage() {
  echo "usage: $(basename "$0") [-t \"Title\"] [-m manager] [-d serial-or-device-id] [-S] [-D] [-n] <user> <new-role>" >&2
  echo "roles: $(role_list | tr '\n' ' ')" >&2
  exit 2
}

title=""; manager=""; device=""; strict=0; skip_device=0
while getopts "t:m:d:SDn" opt; do
  case "$opt" in
    t) title="$OPTARG" ;;
    m) manager="$OPTARG" ;;
    d) device="$OPTARG" ;;
    S) strict=1 ;;
    D) skip_device=1 ;;
    n) DRYRUN=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
addr=$(qualify "$1")
role="$2"
role_load "$role"
[ -n "$title" ] || title="$ROLE_TITLE"
user_exists "$addr" || die "$addr does not exist"
if [ -n "$manager" ]; then
  manager=$(qualify "$manager")
  user_exists "$manager" || die "manager $manager does not exist"
fi
admin=$(lab_admin)

old_dept=$(user_department "$addr")
old_role=$(role_for_department "$old_dept" || echo "")
log "== role change for $addr: ${old_role:-no catalog role} (department ${old_dept:-none}) -> $ROLE_NAME (OU $ROLE_OU, groups: $ROLE_GROUPS, device: $ROLE_DEVICE)"
reason=$(suspension_reason "$addr")
[ "$reason" != "ADMIN" ] || warn "$addr is suspended by an administrator; a role change does not reactivate it"

# 1. The OU: policy follows the new role.
ou=$(user_ou "$addr")
if [ "$ou" = "$ROLE_OU" ]; then
  ok "in $ROLE_OU"
elif do_cmd "move $addr from $ou to $ROLE_OU" "$GAM" update user "$addr" ou "$ROLE_OU"; then
  [ "$DRYRUN" -eq 1 ] || changed "moved from $ou to $ROLE_OU"
else
  fail "could not move $addr to $ROLE_OU"
fi

# 2. Groups: remove what other catalog roles grant and the new role does not; add what it grants;
#    keep and report the rest. With -S, everything outside the new role goes.
current=$(user_groups "$addr")
managed=$(role_all_groups | while read -r g; do qualify "$g"; done)
wanted=$(printf '%s\n' "$ROLE_GROUPS" | tr ' ' '\n' | while read -r g; do [ -n "$g" ] && qualify "$g"; done)
for g in $current; do
  if printf '%s\n' "$wanted" | grep -qix "$g"; then
    ok "member of $g (in the $ROLE_NAME role)"
  elif [ "$strict" -eq 1 ] || printf '%s\n' "$managed" | grep -qix "$g"; then
    if do_cmd "remove $addr from $g" "$GAM" update group "$g" delete member "$addr"; then
      [ "$DRYRUN" -eq 1 ] || changed "removed from $g"
    else
      fail "could not remove $addr from $g"
    fi
  else
    ok "kept $g (not in the catalog: a one-off grant; review it, or rerun with -S to remove it)"
  fi
done
for g in $wanted; do
  if printf '%s\n' "$current" | grep -qix "$g"; then
    :
  elif do_cmd "add $addr to $g" "$GAM" update group "$g" add member "$addr"; then
    [ "$DRYRUN" -eq 1 ] || changed "added to $g"
  else
    fail "could not add $addr to $g"
  fi
done

# 3. Title, department, manager.
if [ "$(user_title "$addr")" = "$title" ] && [ "$(user_department "$addr")" = "$ROLE_DEPARTMENT" ]; then
  ok "title $title, department $ROLE_DEPARTMENT"
elif do_cmd "set title $title, department $ROLE_DEPARTMENT" "$GAM" update user "$addr" organization type work name "$ORG_NAME" title "$title" department "$ROLE_DEPARTMENT" primary; then
  [ "$DRYRUN" -eq 1 ] || changed "title $title, department $ROLE_DEPARTMENT"
else
  fail "could not set title and department"
fi
if [ -n "$manager" ]; then
  if [ "$(user_manager "$addr")" = "$manager" ]; then
    ok "manager $manager"
  elif do_cmd "set manager $manager" "$GAM" update user "$addr" relation manager "$manager"; then
    [ "$DRYRUN" -eq 1 ] || changed "manager $manager"
  else
    fail "could not set the manager"
  fi
fi

# 4. The device. A Mac the person holds follows them into a Mac role (label moved) and goes back to
#    IT otherwise; a Chromebook likewise; a newly issued device comes in with -d.
reclaim_mac() { # id serial hostname
  local l
  for l in $(role_all_labels); do
    if fleet_host_labels "$(fleet_host_json "$2")" | grep -qx "$l"; then
      if do_cmd "remove $3 from the $l label" fleet_remove_label "$1" "$l"; then [ "$DRYRUN" -eq 1 ] || changed "$3 removed from $l"; else fail "could not remove $3 from $l"; fi
    fi
  done
  if do_cmd "return $3 to IT custody (mapping -> $admin)" fleet_set_mapping "$1" "$admin"; then [ "$DRYRUN" -eq 1 ] || changed "$3 mapped to $admin"; else fail "could not remap $3"; fi
  manual "collect the Mac ($3, $2) from the person; it is no longer part of their role; re-provision it for the next person (runbooks/mac-provisioning-fleet.md)"
}
if [ "$skip_device" -eq 1 ]; then
  ok "device step skipped (-D)"
else
  macs=$(fleet_hosts_by_email "$addr")
  croses=$(cros_by_user "$addr")
  case "$ROLE_DEVICE" in
    mac)
      if [ -z "$macs" ] && [ -z "$device" ]; then
        manual "issue a Mac for the $ROLE_NAME role: provision it (runbooks/mac-provisioning-fleet.md), then rerun with -d <serial>"
      fi
      if [ -n "$device" ] && ! printf '%s\n' "$macs" | cut -f2 | grep -qx "$device"; then
        host=$(fleet_host_json "$device")
        if [ -z "$host" ] || [ "$host" = "null" ]; then
          fail "no Fleet host with identifier $device"
        else
          hid=$(fleet_host_id "$host")
          if do_cmd "map Fleet host $(fleet_host_name "$host") ($device) to $addr" fleet_set_mapping "$hid" "$addr"; then [ "$DRYRUN" -eq 1 ] || changed "$device mapped to $addr"; else fail "could not map $device"; fi
          macs=$(printf '%s\t%s\t%s\n' "$hid" "$device" "$(fleet_host_name "$host")")
        fi
      fi
      while IFS="$(printf '\t')" read -r hid serial hname; do
        [ -n "$hid" ] || continue
        labels=$(fleet_host_labels "$(fleet_host_json "$serial")")
        for l in $(role_all_labels); do
          if [ "$l" != "$ROLE_FLEET_LABEL" ] && printf '%s\n' "$labels" | grep -qx "$l"; then
            if do_cmd "remove $hname from the $l label" fleet_remove_label "$hid" "$l"; then [ "$DRYRUN" -eq 1 ] || changed "$hname removed from $l"; else fail "could not remove $hname from $l"; fi
          fi
        done
        if printf '%s\n' "$labels" | grep -qx "$ROLE_FLEET_LABEL"; then
          ok "$hname carries the $ROLE_FLEET_LABEL label"
        elif do_cmd "add $hname to the $ROLE_FLEET_LABEL label (its role software follows)" fleet_add_label "$hid" "$ROLE_FLEET_LABEL"; then
          [ "$DRYRUN" -eq 1 ] || changed "$hname added to $ROLE_FLEET_LABEL"
        else
          fail "could not add $hname to $ROLE_FLEET_LABEL"
        fi
      done <<< "$macs"
      ;;
    chromeos|byod)
      while IFS="$(printf '\t')" read -r hid serial hname; do
        [ -n "$hid" ] || continue
        reclaim_mac "$hid" "$serial" "$hname"
      done <<< "$macs"
      ;;
  esac
  case "$ROLE_DEVICE" in
    chromeos)
      if [ -n "$device" ]; then
        cj=$(cros_json "$device")
        if [ -z "$cj" ]; then
          fail "no ChromeOS device with id or serial $device"
        else
          cid=$(cros_field "$cj" deviceId); cserial=$(cros_field "$cj" serialNumber)
          if [ "$(cros_field "$cj" annotatedUser)" = "$addr" ]; then ok "Chromebook $cserial is annotated to $addr"
          elif do_cmd "annotate Chromebook $cserial with user $addr" "$GAM" update cros "$cid" user "$addr"; then [ "$DRYRUN" -eq 1 ] || changed "Chromebook $cserial annotated to $addr"
          else fail "could not annotate Chromebook $cserial"; fi
          if [ "$(cros_field "$cj" orgUnitPath)" = "$DEVICE_OU" ]; then ok "Chromebook $cserial is in $DEVICE_OU"
          elif do_cmd "move Chromebook $cserial to $DEVICE_OU" "$GAM" update cros "$cid" ou "$DEVICE_OU"; then [ "$DRYRUN" -eq 1 ] || changed "Chromebook $cserial moved to $DEVICE_OU"
          else fail "could not move Chromebook $cserial"; fi
        fi
      elif [ -z "$croses" ]; then
        manual "issue a Chromebook for the $ROLE_NAME role: enroll it (runbooks/chromeos-enrollment.md), then rerun with -d <device id>"
      else
        ok "Chromebook(s) annotated to $addr: $(printf '%s\n' "$croses" | cut -f2 | tr '\n' ' ')"
      fi
      ;;
    mac|byod)
      while IFS="$(printf '\t')" read -r cid cserial cstatus _; do
        [ -n "$cid" ] || continue
        if do_cmd "return Chromebook $cserial to IT custody (annotated user -> $admin)" "$GAM" update cros "$cid" user "$admin"; then [ "$DRYRUN" -eq 1 ] || changed "Chromebook $cserial annotated to $admin"; else fail "could not re-annotate Chromebook $cserial"; fi
        manual "collect the Chromebook ($cserial) from the person; it is no longer part of their role"
      done <<< "$croses"
      ;;
  esac
fi

# 5. Read-back.
log "== verify $addr"
log "  OU: $(user_ou "$addr") (role: $ROLE_OU)"
log "  title: $(user_title "$addr"); department: $(user_department "$addr"); manager: $(user_manager "$addr")"
for g in $wanted; do
  if [ "$DRYRUN" -eq 1 ]; then
    if user_in_group "$addr" "$g"; then log "  group $g: member"; else log "  group $g: not yet a member (dry run)"; fi
  elif user_in_group_settled "$addr" "$g" 4; then log "  group $g: member"; else log "  group $g: MISSING"; fail "not a member of $g"; fi
done
for g in $(user_groups "$addr"); do
  printf '%s\n' "$wanted" | grep -qix "$g" || log "  group $g: member (outside the $ROLE_NAME role)"
done
for row in $(fleet_hosts_by_email "$addr" | cut -f2); do
  log "  Fleet host $row: labels $(fleet_host_labels "$(fleet_host_json "$row")" | grep '^role-' | tr '\n' ' ')"
done
while IFS="$(printf '\t')" read -r cid cserial cstatus _; do
  [ -n "$cid" ] && log "  Chromebook $cserial: $cstatus"
done <<< "$(cros_by_user "$addr")"
summary
