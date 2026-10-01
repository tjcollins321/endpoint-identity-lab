#!/bin/zsh
# Verifies a managed Mac without changing anything: identity, MDM vendor and enrollment state, the
# management agent, FileVault, the configuration profiles installed, the Command Line Tools and
# Homebrew, the baseline apps with their versions, and the per-user defaults mac-onboard.sh sets.
# One line per check (PASS, FAIL, INFO); exits 1 if any check failed, so it can gate a handover or
# run from the MDM as a compliance read.
#
# Run as the user for the per-user checks; add sudo to list the system configuration profiles;
# name the role to hold the Mac to that role's apps and tooling, else they are reported, not judged:
#   sudo ./mac-verify.sh [engineer|marketing|sales|contractor]
# Under sudo, or under an MDM script runner, which runs as root, the per-user checks read the
# console user's settings, not root's. Nothing here prints a clock time.
set -uo pipefail
role=${1:-}

# Apps every managed Mac has (Chrome by the Fleet policy script, Slack as a Fleet-maintained app).
BASELINE_APPS=(
  "Google Chrome:google-chrome:/Applications/Google Chrome.app"
  "Slack:slack:/Applications/Slack.app"
)
# Apps by role label in Fleet: "role:Name:app bundle". Judged only when the role is named.
ROLE_APPS=(
  "engineer:Visual Studio Code:/Applications/Visual Studio Code.app"
  "marketing:Zoom:/Applications/zoom.us.app"
)
BREW_ROLES=(engineer)
DEFAULTS=(
  "NSGlobalDomain:AppleShowAllExtensions:bool:true"
  "NSGlobalDomain:NSDocumentSaveNewDocumentsToCloud:bool:false"
  "com.apple.finder:ShowPathbar:bool:true"
  "com.apple.finder:ShowStatusBar:bool:true"
)

pass=0; fail=0
report() { printf '%-4s  %-34s %s\n' "$1" "$2" "$3"; }
ok()   { pass=$((pass + 1)); report PASS "$1" "$2"; }
bad()  { fail=$((fail + 1)); report FAIL "$1" "$2"; }
info() { report INFO "$1" "$2"; }

console_user=$(stat -f%Su /dev/console)
as_user() {
  if [[ $EUID -eq 0 && $console_user != root ]]; then sudo -u "$console_user" "$@"; else "$@"; fi
}

# Identity
hw=$(system_profiler SPHardwareDataType 2>/dev/null)
info "Mac" "$(scutil --get ComputerName 2>/dev/null || hostname), $(sed -n 's/^ *Model Identifier: //p' <<< "$hw"), serial $(sed -n 's/^ *Serial Number (system): //p' <<< "$hw")"
info "macOS" "$(sw_vers -productVersion) build $(sw_vers -buildVersion)"
info "Console user" "$console_user"

# MDM
enroll=$(profiles status -type enrollment 2>/dev/null)
mdm=$(sed -n 's/^MDM enrollment: //p' <<< "$enroll")
server=$(sed -n 's/^MDM server: //p' <<< "$enroll")
server_host=$(sed -E 's#^https?://([^/]*).*#\1#' <<< "$server")
case $server in
  *jamf*)                  vendor="Jamf Now" ;;
  *fleet*|*/mdm/apple/mdm*) vendor="Fleet" ;;
  "")                      vendor="none" ;;
  *)                       vendor="unknown vendor" ;;
esac
if [[ $mdm == Yes* ]]; then
  ok "MDM enrollment" "$vendor at $server_host"
  if [[ $mdm == *"User Approved"* ]]; then ok "User-approved MDM" "yes"; else bad "User-approved MDM" "no: $mdm"; fi
else
  bad "MDM enrollment" "not enrolled"
fi
dep=$(sed -n 's/^Enrolled via DEP: //p' <<< "$enroll")
info "Automated Device Enrollment" "${dep:-unknown}"

# Agent
orbit=(/opt/orbit/bin/orbit/macos/*/orbit(N))
if [[ -n ${orbit[1]:-} ]]; then
  info "Agent" "fleetd, $("${orbit[1]}" --version 2>/dev/null | head -1)"
elif [[ -d /opt/orbit ]]; then
  info "Agent" "fleetd present"
else
  info "Agent" "none; this MDM uses the MDM channel only"
fi

# FileVault
fv=$(fdesetup status 2>/dev/null | head -1)
if [[ $fv == "FileVault is On." ]]; then ok "FileVault" "on"; else bad "FileVault" "${fv:-unknown}"; fi

# Configuration profiles (system scope needs root)
if [[ $EUID -eq 0 ]]; then
  ids=$(profiles list 2>/dev/null | sed -n 's/.*profileIdentifier: //p' | sort)
  n=$(grep -c . <<< "$ids" || true)
  if (( n > 0 )); then
    ok "Configuration profiles" "$n installed"
    while read -r id; do info "  profile" "$id"; done <<< "$ids"
  else
    bad "Configuration profiles" "none installed"
  fi
else
  info "Configuration profiles" "run with sudo to list system profiles"
fi

# Tools: expected for the roles that get Homebrew, reported otherwise.
if [[ -n $role ]] && (( ${BREW_ROLES[(Ie)$role]} )); then judge=bad; else judge=info; fi
if clt=$(xcode-select -p 2>/dev/null); then ok "Command Line Tools" "$clt"; else $judge "Command Line Tools" "missing"; fi
if [[ -x /opt/homebrew/bin/brew ]]; then
  ok "Homebrew" "$(as_user /opt/homebrew/bin/brew --version 2>/dev/null | head -1)"
else
  $judge "Homebrew" "missing${role:+ (not expected for the $role role)}"
fi

# Baseline apps, then the role's apps (judged when the role is named, reported otherwise)
for entry in "${BASELINE_APPS[@]}"; do
  name=${entry%%:*}; app=${entry##*:}
  if [[ -d $app ]]; then
    ok "App: $name" "$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
  else
    bad "App: $name" "missing"
  fi
done
for entry in "${ROLE_APPS[@]}"; do
  r=${entry%%:*}; rest=${entry#*:}; name=${rest%%:*}; app=${rest#*:}
  if [[ -d $app ]]; then
    ok "App: $name ($r)" "$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
  elif [[ $role == "$r" ]]; then
    bad "App: $name ($r)" "missing"
  else
    info "App: $name ($r)" "absent${role:+; not expected for the $role role}"
  fi
done

# Per-user defaults
for entry in "${DEFAULTS[@]}"; do
  IFS=: read -r domain key type want <<< "$entry"
  have=$(as_user defaults read "$domain" "$key" 2>/dev/null || print -- unset)
  if [[ $type == bool ]]; then
    if [[ $want == true ]]; then wantv=1; else wantv=0; fi
  else
    wantv=$want
  fi
  if [[ $have == "$wantv" ]]; then ok "Default: $domain $key" "$want"; else bad "Default: $domain $key" "is $have, want $want"; fi
done

print -- "== $pass passed, $fail failed"
if (( fail > 0 )); then exit 1; fi
