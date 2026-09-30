#!/bin/zsh
# Apply the Fleet configuration in this directory to the server fleetctl is logged in to:
# validate first (--dry-run), then apply, with the same file list both times. Secrets that the
# YAML references as $VARIABLES come from fleet/.env, which is never committed.
#
#   ./gitops.sh            # dry run, then apply
#   ./gitops.sh --dry-run  # validate only
#
# --delete-other-fleets makes these files the whole truth: a fleet created in the UI and absent
# here is removed, and its hosts become Unassigned.
set -euo pipefail
cd "${0:A:h}"
set -a; source ../.env; set +a
FLEETCTL="${FLEETCTL:-fleetctl}"

files=(-f default.yml)
for f in fleets/*.yml(N); do files+=(-f "$f"); done

"$FLEETCTL" gitops "${files[@]}" --delete-other-fleets --dry-run
[[ "${1:-}" == "--dry-run" ]] && exit 0
"$FLEETCTL" gitops "${files[@]}" --delete-other-fleets
