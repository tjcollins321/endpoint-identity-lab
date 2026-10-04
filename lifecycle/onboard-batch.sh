#!/bin/bash
# Onboard every hire in a CSV: the simulated hire record, what an HRIS export or a ticket webhook
# would deliver (examples/hires.csv). One onboard.sh per row; a failing row does not stop the rest;
# a results table at the end, optionally mailed to the admin where GAM can send mail.
#
# usage: onboard-batch.sh [-n] [-M] hires.csv
#   -n  dry run, passed to every onboard.sh
#   -M  mail the results table to the admin (only where GAM can send mail; otherwise it is printed)
# Columns: role,first,last,personal_email,manager,start_date,device. Lines starting with # are
# skipped. No commas inside fields. Exit 0 when every row succeeded, 1 otherwise.

set -u
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

usage() { echo "usage: $(basename "$0") [-n] [-M] hires.csv" >&2; exit 2; }
dry=""; mail=0
while getopts "nM" opt; do
  case "$opt" in
    n) dry="-n" ;;
    M) mail=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] && [ -r "$1" ] || usage
csv="$1"

results=""
rows=0; failed_rows=0
while IFS=, read -r role first last personal manager start device; do
  case "$role" in ''|'#'*|role) continue ;; esac
  rows=$((rows + 1))
  log "==== row $rows: $first $last, $role"
  set -- "$LIFECYCLE_DIR/onboard.sh"
  [ -z "$dry" ] || set -- "$@" "$dry"
  [ -z "$personal" ] || set -- "$@" -p "$personal"
  [ -z "$manager" ] || set -- "$@" -m "$manager"
  [ -z "$start" ] || set -- "$@" -s "$start"
  [ -z "$device" ] || set -- "$@" -d "$device"
  # The loop reads the CSV on stdin; the child gets /dev/null so nothing it runs can eat rows.
  if "$@" "$role" "$first" "$last" </dev/null; then
    results="$results| $first $last | $role | ok |"$'\n'
  else
    failed_rows=$((failed_rows + 1))
    results="$results| $first $last | $role | FAILED, see the run above |"$'\n'
  fi
done < "$csv"

table="| Hire | Role | Result |"$'\n'"|---|---|---|"$'\n'"$results"
log "==== $rows row(s), $failed_rows failed"
printf '%s' "$table"
if [ "$mail" -eq 1 ]; then
  if gam_can_send_mail; then
    if "$GAM" sendemail "$(lab_admin)" subject "Onboarding batch: $rows row(s), $failed_rows failed" message "$table" >/dev/null; then
      log "results mailed to $(lab_admin)"
    else
      log "could not mail the results"
    fi
  else
    log "results not mailed: GAM sends mail only through domain-wide delegation, which this tenant does not grant"
  fi
fi
[ "$failed_rows" -eq 0 ]
