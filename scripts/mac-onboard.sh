#!/bin/zsh
# The per-user part of a Mac's setup, by role, after the Mac is enrolled in MDM and the MDM has
# delivered what it owns: passcode policy, FileVault, restrictions, the Chrome enrollment token, and
# the apps (Slack for every Mac; VS Code or Zoom by the role label in Fleet). What is left is what
# only a user session can do: Homebrew, which refuses root, for engineers, and a few per-user
# defaults for everyone. Idempotent: every step checks before it acts and reports what it changed;
# a second run changes nothing. mac-verify.sh confirms the result without changing anything.
#
# Run in Terminal as the user who will use the Mac, who is an administrator, after enrollment:
#   ./mac-onboard.sh engineer      # Homebrew (its installer adds the Command Line Tools) plus the defaults
#   ./mac-onboard.sh marketing     # the defaults only
# Roles are the catalog in lifecycle/roles/; only engineer gets Homebrew. Not as root and not under
# an MDM's script runner: Homebrew refuses root, and a per-user default written by root lands in
# root's home. At scale the defaults become a managed-preference profile and this script disappears;
# see docs/design.md.
set -euo pipefail

# Roles that get Homebrew and the developer tooling it brings.
BREW_ROLES=(engineer)
# "domain:key:type:value", written for the current user only when the value differs.
DEFAULTS=(
  "NSGlobalDomain:AppleShowAllExtensions:bool:true"
  "NSGlobalDomain:NSDocumentSaveNewDocumentsToCloud:bool:false"
  "com.apple.finder:ShowPathbar:bool:true"
  "com.apple.finder:ShowStatusBar:bool:true"
)
BREW=/opt/homebrew/bin/brew
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 NONINTERACTIVE=1

changed=0
log() { print -- "$*"; }
did() { changed=$((changed + 1)); log "changed: $*"; }

role=${1:-}
if [[ -z $role ]]; then
  print -u2 "usage: mac-onboard.sh <role>   (engineer, marketing, sales, contractor: see lifecycle/roles/)"
  exit 2
fi
if [[ $EUID -eq 0 ]]; then
  print -u2 "mac-onboard.sh: run as the user who will use this Mac, not as root."
  exit 2
fi
if [[ $(uname -m) != arm64 ]]; then
  print -u2 "mac-onboard.sh: written for Apple silicon, Homebrew at /opt/homebrew."
  exit 2
fi

log "== onboarding $(scutil --get ComputerName 2>/dev/null || hostname), macOS $(sw_vers -productVersion), user $USER, role $role"

# 1. Homebrew, for the roles that get it. Its installer needs sudo for /opt/homebrew and for the
#    Command Line Tools, so the password is asked once up front and the ticket is kept alive.
if (( ${BREW_ROLES[(Ie)$role]} )); then
  if [[ -x $BREW ]]; then
    log "ok: $($BREW --version | head -1) present"
  else
    log "installing Homebrew; your password is asked once"
    sudo -v
    ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
    keepalive=$!
    trap 'kill $keepalive 2>/dev/null' EXIT
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    did "Homebrew installed"
  fi
  # 2. Homebrew on the PATH for new shells.
  zprofile=$HOME/.zprofile
  shellenv_line='eval "$(/opt/homebrew/bin/brew shellenv)"'
  if [[ -f $zprofile ]] && grep -qF "$shellenv_line" "$zprofile"; then
    log "ok: Homebrew shellenv in ~/.zprofile"
  else
    print -- "$shellenv_line" >> "$zprofile"
    did "Homebrew shellenv added to ~/.zprofile"
  fi
else
  log "ok: no Homebrew for the $role role; apps arrive from the MDM"
fi

# 3. Per-user defaults. `defaults read` prints booleans as 1 and 0.
finder_changed=0
for entry in "${DEFAULTS[@]}"; do
  IFS=: read -r domain key type want <<< "$entry"
  have=$(defaults read "$domain" "$key" 2>/dev/null || print -- unset)
  if [[ $type == bool ]]; then
    if [[ $want == true ]]; then wantv=1; else wantv=0; fi
  else
    wantv=$want
  fi
  if [[ $have == "$wantv" ]]; then
    log "ok: $domain $key = $want"
  else
    defaults write "$domain" "$key" "-$type" "$want"
    did "$domain $key: $have -> $want"
    finder_changed=1
  fi
done
if (( finder_changed )); then
  killall Finder 2>/dev/null || true
  log "Finder relaunched to pick up the new defaults"
fi

if (( changed == 0 )); then
  log "== done: nothing to do, this Mac already matches the baseline"
else
  log "== done: $changed change(s); run mac-verify.sh to confirm"
fi
