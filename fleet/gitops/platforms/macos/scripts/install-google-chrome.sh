#!/bin/zsh
# Installs Google Chrome if it is missing, or replaces a copy whose signature no longer verifies.
# Idempotent, so it doubles as the remediation for the "Google Chrome installed" policy: on a Mac
# where Chrome is present and validly signed it prints the version and exits 0 without touching
# anything. Runs as root under fleetd; downloads Google's universal build over HTTPS and verifies
# its signature and Apple's notarization on the mounted image, before the old copy is removed and
# anything lands in /Applications; a bad download leaves the Mac as it was.
#
# The health check is a shallow `codesign --verify` on purpose: a deep, strict verification fails
# on a Chrome that has updated itself in place, and would reinstall a healthy browser. A present
# but broken Chrome is left alone while it is running; the policy keeps failing until it is quit.
set -euo pipefail

APP="/Applications/Google Chrome.app"
URL="https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg"

version() { defaults read "$APP/Contents/Info" CFBundleShortVersionString; }

if [[ -d "$APP" ]]; then
  if codesign --verify "$APP" 2>/dev/null; then
    echo "Google Chrome $(version) present and its signature verifies; nothing to do."
    exit 0
  fi
  if pgrep -x "Google Chrome" >/dev/null; then
    echo "Google Chrome is present but fails signature verification, and it is running; not replacing a running app. Quit Chrome and let the policy re-run." >&2
    exit 1
  fi
  echo "Google Chrome is present but fails signature verification; replacing it."
fi

WORK=$(mktemp -d /private/tmp/chrome-install.XXXXXX)
MNT="$WORK/mnt"
cleanup() { hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

echo "Downloading Google Chrome..."
curl -fsSL --retry 3 -o "$WORK/chrome.dmg" "$URL"
mkdir "$MNT"
hdiutil attach "$WORK/chrome.dmg" -mountpoint "$MNT" -nobrowse -quiet

codesign --verify --deep --strict "$MNT/Google Chrome.app"
spctl --assess --type execute "$MNT/Google Chrome.app"

rm -rf "$APP"
ditto "$MNT/Google Chrome.app" "$APP"
hdiutil detach "$MNT" -quiet

codesign --verify "$APP"
echo "Google Chrome $(version) installed."
