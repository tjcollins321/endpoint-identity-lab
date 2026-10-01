#!/bin/bash
# Shared helpers for the lifecycle scripts in this folder. Sourced, never run. bash 3.2-compatible
# (macOS /bin/bash); shellcheck clean. Pulls in workspace/gam/common.sh (GAM, log, die, qualify,
# the username convention, the direct-lookup helpers) and adds: the role catalog reader, the
# ok/changed/FAIL/manual collectors every script ends with, the welcome mail, and the Fleet and
# ChromeOS calls. Every read is a direct lookup; nothing decides on a lagging search index.
#
# Fleet: curl against the server fleetctl is logged in to (address and token from ~/.fleet/config),
# or FLEET_URL and FLEET_API_TOKEN from the environment. ChromeOS: GAM's cros commands. Jamf Now has
# no API; its steps are printed as manual lines.

# shellcheck disable=SC2016  # jq programs are single-quoted on purpose; $vars there are jq variables
set -u

LIFECYCLE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$LIFECYCLE_DIR/.." && pwd)
GAM_DIR="$REPO_DIR/workspace/gam"
ROLES_DIR="$LIFECYCLE_DIR/roles"
TEMPLATES_DIR="$LIFECYCLE_DIR/templates"
# shellcheck disable=SC1091  # the path is computed above; shellcheck -x follows it
. "$GAM_DIR/common.sh"

JQ=${JQ:-/usr/bin/jq}
FLEETCTL=${FLEETCTL:-$HOME/bin/fleetctl}
FLEET_CONFIG=${FLEET_CONFIG:-$HOME/.fleet/config}
ORG_NAME=${ORG_NAME:-TJ Collins Lab}
DEVICE_OU=${DEVICE_OU:-/Devices}
OFFBOARDED_OU=${OFFBOARDED_OU:-/Offboarded}
RETENTION_DAYS=${RETENTION_DAYS:-30}

# --- result collectors ---------------------------------------------------------------------------
DRYRUN=0
FAILED=0
MANUAL=""
ok()      { log "ok: $*"; }
changed() { log "changed: $*"; }
fail()    { FAILED=$((FAILED + 1)); log "FAIL: $*"; }
warn()    { log "warning: $*"; }
manual()  { MANUAL="${MANUAL}[ ] $*"$'\n'; }
would()   { log "would: $*"; }
# do_cmd "what it does" command args...: runs the command, or in a dry run only says what it would do.
do_cmd() {
  local what="$1"
  shift
  if [ "$DRYRUN" -eq 1 ]; then
    would "$what"
    return 0
  fi
  "$@"
}
# The closing block of every script: the manual checklist, then the count. Exit 1 on any FAIL.
summary() {
  if [ -n "$MANUAL" ]; then
    log "== manual steps"
    printf '%s' "$MANUAL"
  fi
  if [ "$DRYRUN" -eq 1 ]; then
    log "== dry run: nothing was changed; $FAILED failed"
  else
    log "== $FAILED failed"
  fi
  [ "$FAILED" -eq 0 ]
}
today() { date '+%Y-%m-%d'; }
# A date N days from today, for the retention line (BSD date on macOS, GNU date elsewhere).
days_from_today() {
  date -v "+$1d" '+%Y-%m-%d' 2>/dev/null || date -d "+$1 days" '+%Y-%m-%d'
}

# --- role catalog --------------------------------------------------------------------------------
# One roles/<role>.conf per role, KEY=value lines, read with sed and never sourced, so the file is
# data a reviewer can trust. role_load sets the ROLE_* variables and validates them.
role_file()   { echo "$ROLES_DIR/$1.conf"; }
role_exists() { [ -r "$(role_file "$1")" ]; }
role_get()    { sed -n "s/^$2=//p" "$(role_file "$1")" | head -1; }
role_list() {
  local f
  for f in "$ROLES_DIR"/*.conf; do
    basename "$f" .conf
  done
}
role_load() {
  local role="$1"
  role_exists "$role" || die "unknown role '$role'; the catalog has: $(role_list | tr '\n' ' ')"
  ROLE_NAME=$(role_get "$role" ROLE_NAME)
  ROLE_OU=$(role_get "$role" ROLE_OU)
  ROLE_GROUPS=$(role_get "$role" ROLE_GROUPS)
  ROLE_TITLE=$(role_get "$role" ROLE_TITLE)
  ROLE_DEPARTMENT=$(role_get "$role" ROLE_DEPARTMENT)
  ROLE_DEVICE=$(role_get "$role" ROLE_DEVICE)
  ROLE_FLEET_LABEL=$(role_get "$role" ROLE_FLEET_LABEL)
  ROLE_WELCOME=$(role_get "$role" ROLE_WELCOME)
  [ -n "$ROLE_NAME" ] || die "roles/$role.conf: ROLE_NAME is required"
  [ -n "$ROLE_OU" ] || die "roles/$role.conf: ROLE_OU is required"
  [ -n "$ROLE_GROUPS" ] || die "roles/$role.conf: ROLE_GROUPS is required"
  [ -n "$ROLE_TITLE" ] || die "roles/$role.conf: ROLE_TITLE is required"
  [ -n "$ROLE_DEPARTMENT" ] || die "roles/$role.conf: ROLE_DEPARTMENT is required"
  [ -n "$ROLE_WELCOME" ] || die "roles/$role.conf: ROLE_WELCOME is required"
  [ -r "$TEMPLATES_DIR/$ROLE_WELCOME" ] || die "roles/$role.conf: templates/$ROLE_WELCOME not found"
  case "$ROLE_DEVICE" in
    mac) [ -n "$ROLE_FLEET_LABEL" ] || die "roles/$role.conf: ROLE_FLEET_LABEL is required when ROLE_DEVICE=mac" ;;
    chromeos|byod) ;;
    *) die "roles/$role.conf: ROLE_DEVICE must be mac, chromeos, or byod" ;;
  esac
  export ROLE_NAME ROLE_OU ROLE_GROUPS ROLE_TITLE ROLE_DEPARTMENT ROLE_DEVICE ROLE_FLEET_LABEL ROLE_WELCOME
}
# Every group any role grants: the groups the catalog manages. A membership outside this set is a
# one-off grant, which a role change keeps and the audit reports.
role_all_groups() {
  local f
  for f in "$ROLES_DIR"/*.conf; do
    sed -n 's/^ROLE_GROUPS=//p' "$f"
  done | tr ' ' '\n' | grep . | sort -u
}
role_all_labels() {
  local f
  for f in "$ROLES_DIR"/*.conf; do
    sed -n 's/^ROLE_FLEET_LABEL=//p' "$f"
  done | grep . | sort -u
}
# The catalog role whose department matches the account's, or nothing.
role_for_department() {
  local f
  for f in "$ROLES_DIR"/*.conf; do
    if [ "$(sed -n 's/^ROLE_DEPARTMENT=//p' "$f")" = "$1" ]; then
      basename "$f" .conf
      return 0
    fi
  done
  return 1
}
# "a" or "an" for the role name in prose.
role_article() {
  case "$1" in
    [AEIOUaeiou]*) echo "an" ;;
    *) echo "a" ;;
  esac
}

# --- Workspace account reads (direct lookups, JSON) ----------------------------------------------
user_json()       { "$GAM" info user "$1" quick formatjson 2>/dev/null; }
user_field()      { user_json "$1" | "$JQ" -r "$2 | if . == null then empty else tostring end"; }
user_ou()         { user_field "$1" '.orgUnitPath'; }
user_title()      { user_field "$1" '.organizations[0].title'; }
user_department() { user_field "$1" '.organizations[0].department'; }
user_manager()    { user_field "$1" '[.relations[]? | select(.type == "manager") | .value][0]'; }
user_note()       { user_field "$1" '.notes.value'; }
user_2sv()        { user_field "$1" '.isEnrolledIn2Sv'; }
# The account's groups, full addresses, one per line (a direct lookup, not the search index).
user_groups()     { "$GAM" user "$1" print groups 2>/dev/null | tail -n +2 | cut -d, -f2; }
user_in_group()   { user_groups "$1" | grep -qix "$(qualify "$2")"; }
user_fullname() {
  local names
  names=$(user_names "$1")
  [ -n "$names" ] && printf '%s\n' "$names" | tr '\t' ' '
}

# --- the welcome kit -------------------------------------------------------------------------------
# GAM sends mail (sendemail, and the notify option of create user) only through a service account
# with domain-wide delegation, acting as the admin. This tenant grants neither, so by design the
# kit is rendered to a file in lifecycle/outbox/ (ignored by git) and the admin sends it from their
# own mailbox; where delegation exists, the same function sends it through GAM. The body is
# templates/welcome-common.txt with the role's device section dropped in.
OUTBOX_DIR="$LIFECYCLE_DIR/outbox"
# True when GAM holds a service account with a key (the wizard leaves a keyless placeholder file
# where key creation is blocked, as in this tenant); LIFECYCLE_MAIL=outbox forces the file path.
gam_can_send_mail() {
  local f="${GAMCFGDIR:-$HOME/.gam}/oauth2service.json"
  [ "${LIFECYCLE_MAIL:-}" != "outbox" ] && [ -r "$f" ] \
    && "$JQ" -e '((.private_key // "") | length > 0) and ((.client_email // "") | length > 0)' "$f" >/dev/null 2>&1
}
lab_admin() { "$GAM" oauth info 2>/dev/null | sed -n 's/^Google Workspace Admin: //p' | head -1; }
welcome_subject() { echo "Welcome to $ORG_NAME, $1: your first day is $2"; }
# render_welcome FIRST USERNAME MANAGER-DISPLAY START-DATE: the message body, using the loaded ROLE_*.
render_welcome() {
  local first="$1" username="$2" manager="$3" start="$4" section msg
  section=$(cat "$TEMPLATES_DIR/$ROLE_WELCOME")
  msg=$(cat "$TEMPLATES_DIR/welcome-common.txt")
  msg=${msg//\{First\}/$first}
  msg=${msg//\{Username\}/$username}
  msg=${msg//\{Manager\}/$manager}
  msg=${msg//\{StartDate\}/$start}
  msg=${msg//\{Role\}/$ROLE_NAME}
  msg=${msg//\{RoleArticle\}/$(role_article "$ROLE_NAME")}
  msg=${msg//\{DeviceSection\}/$section}
  printf '%s\n' "$msg"
}
# send_welcome TO FIRST USERNAME MANAGER-DISPLAY START-DATE: through GAM when it can send mail;
# otherwise to the outbox. Prints the outbox path in that case.
send_welcome() {
  local to="$1" first="$2" username="$3" manager="$4" start="$5" out
  if gam_can_send_mail; then
    "$GAM" sendemail "$to" from "$(lab_admin)" subject "$(welcome_subject "$first" "$start")" \
      message "$(render_welcome "$first" "$username" "$manager" "$start")"
    return
  fi
  mkdir -p "$OUTBOX_DIR" && chmod 700 "$OUTBOX_DIR"
  out="$OUTBOX_DIR/welcome-${username%%@*}.txt"
  {
    echo "To: $to"
    echo "Subject: $(welcome_subject "$first" "$start")"
    echo
    render_welcome "$first" "$username" "$manager" "$start"
  } > "$out" && chmod 600 "$out" && echo "${out#"$REPO_DIR"/}"
}

# --- group membership right after a write -------------------------------------------------------
# A membership can take a few seconds to read back after it is added, so a check made right after
# the write retries briefly before it is called missing.
user_in_group_settled() {
  local addr="$1" group="$2" tries="${3:-6}" n=0
  while [ "$n" -lt "$tries" ]; do
    user_in_group "$addr" "$group" && return 0
    n=$((n + 1))
    sleep 3
  done
  return 1
}

# --- Fleet (the Macs) -------------------------------------------------------------------------------
fleet_url()   { if [ -n "${FLEET_URL:-}" ]; then echo "$FLEET_URL"; else sed -n 's/^ *address: //p' "$FLEET_CONFIG" 2>/dev/null | head -1; fi; }
fleet_token() { if [ -n "${FLEET_API_TOKEN:-}" ]; then echo "$FLEET_API_TOKEN"; else sed -n 's/^ *token: //p' "$FLEET_CONFIG" 2>/dev/null | head -1; fi; }
# fleet_api METHOD PATH [JSON-BODY]: prints the response body; fails on an HTTP error.
fleet_api() {
  local method="$1" path="$2" body="${3:-}" url token
  url=$(fleet_url); token=$(fleet_token)
  if [ -z "$url" ] || [ -z "$token" ]; then
    echo "error: no Fleet session (run fleetctl login) and no FLEET_URL/FLEET_API_TOKEN" >&2
    return 1
  fi
  if [ -n "$body" ]; then
    curl -sS -f -X "$method" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$body" "$url$path"
  else
    curl -sS -f -X "$method" -H "Authorization: Bearer $token" "$url$path"
  fi
}
# A host by serial, hostname, or UUID: the host object, or nothing when unknown.
fleet_host_json()    { fleet_api GET "/api/v1/fleet/hosts/identifier/$1" 2>/dev/null | "$JQ" '.host'; }
fleet_host_id()      { "$JQ" -r '.id' <<< "$1"; }
fleet_host_labels()  { "$JQ" -r '.labels[]?.name' <<< "$1"; }
# The custom (person-to-device) mapping of a host, by host id: the host object itself omits it.
fleet_mapping_of()   { fleet_api GET "/api/v1/fleet/hosts/$1/device_mapping" 2>/dev/null | "$JQ" -r '[.device_mapping[]? | select(.source == "custom") | .email][0] // empty'; }
fleet_host_lock()    { "$JQ" -r '.mdm.device_status // "unknown"' <<< "$1"; }
fleet_host_pending() { "$JQ" -r '.mdm.pending_action // empty' <<< "$1"; }
fleet_host_serial()  { "$JQ" -r '.hardware_serial' <<< "$1"; }
fleet_host_name()    { "$JQ" -r '.hostname' <<< "$1"; }
# Hosts whose custom mapping is the given address: "id<TAB>serial<TAB>hostname" per line.
fleet_hosts_by_email() {
  fleet_api GET "/api/v1/fleet/hosts?device_mapping=true&per_page=500" 2>/dev/null \
    | "$JQ" -r --arg e "$1" '.hosts[] | select(any(.device_mapping[]?; .email == $e and .source == "custom")) | [.id, .hardware_serial, .hostname] | @tsv'
}
fleet_set_mapping()  { fleet_api PUT "/api/v1/fleet/hosts/$1/device_mapping" "$("$JQ" -cn --arg e "$2" '{email: $e}')" >/dev/null; }
fleet_add_label()    { fleet_api POST "/api/v1/fleet/hosts/$1/labels" "$("$JQ" -cn --arg l "$2" '{labels: [$l]}')" >/dev/null; }
fleet_remove_label() { fleet_api DELETE "/api/v1/fleet/hosts/$1/labels" "$("$JQ" -cn --arg l "$2" '{labels: [$l]}')" >/dev/null; }
fleet_user_id()      { fleet_api GET "/api/v1/fleet/users" 2>/dev/null | "$JQ" -r --arg e "$1" '.users[] | select(.email == $e) | .id'; }
fleet_delete_user()  { fleet_api DELETE "/api/v1/fleet/users/$1" >/dev/null; }

# --- ChromeOS (the Chromebooks, from the Workspace console through GAM) ---------------------------
# cros_json DEVICE: the device as JSON (deviceId, serialNumber, status, orgUnitPath, annotatedUser),
# or nothing when unknown. DEVICE is the console's device id (a UUID) or the serial number.
cros_json() {
  local sel="$1"
  case "$sel" in
    ????????-????-????-????-????????????) ;;
    *) sel="cros_sn $sel" ;;
  esac
  # shellcheck disable=SC2086  # "cros_sn SERIAL" is two words on purpose
  "$GAM" info cros $sel fields deviceid,serialnumber,status,orgunitpath,annotateduser formatjson 2>/dev/null
}
cros_field()  { "$JQ" -r ".$2 // empty" <<< "$1"; }
# Devices annotated to an address: "deviceId<TAB>serialNumber<TAB>status<TAB>annotatedUser" per line.
# The user: query is the only way to find a device by person, but it is a search index: it also
# matches recent users, and its status column lagged a disable by ten seconds or more on 2026-10-01.
# So the query only finds candidates; each one is read back directly before its annotation is
# checked and its status reported.
cros_by_user() {
  local who="$1" id cj
  for id in $("$GAM" print cros query "user:$who" fields deviceid 2>/dev/null \
      | awk -F, 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next } NF >= 1 { print $h["deviceId"] }'); do
    cj=$(cros_json "$id")
    [ -n "$cj" ] || continue
    [ "$(cros_field "$cj" annotatedUser | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$who" | tr '[:upper:]' '[:lower:]')" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$id" "$(cros_field "$cj" serialNumber)" "$(cros_field "$cj" status)" "$(cros_field "$cj" annotatedUser)"
  done
}

# --- more Workspace reads for offboarding --------------------------------------------------------
# 0 if a completed Calendar transfer from $1 to $2 exists.
calendar_transferred() {
  "$GAM" print datatransfers olduser "$1" newuser "$2" status completed 2>/dev/null \
    | awk -F, 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next } $h["application"] == "Calendar" { f = 1 } END { exit !f }'
}
# Completed transfers from $1: "application<TAB>newOwner" per line.
transfers_from() {
  "$GAM" print datatransfers olduser "$1" status completed 2>/dev/null \
    | awk -F, 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next } { print $h["application"] "\t" $h["newOwnerUserEmail"] }'
}
# Personal devices under Workspace mobile management for $1: "resourceId<TAB>status<TAB>model" per line.
mobiles_of() {
  "$GAM" print mobile query "email:$1" fields resourceid,status,model 2>/dev/null \
    | awk -F, 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next } NF > 1 { print $h["resourceId"] "\t" $h["status"] "\t" $h["model"] }'
}
