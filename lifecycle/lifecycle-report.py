#!/usr/bin/env python3
"""One table joining the two halves of the lifecycle: every Workspace account with its role, OU,
state, and the company device it holds (a Fleet-managed Mac by the person-to-device mapping, a
Chromebook by its annotated user), with the device's management and compliance state. Read-only.

Runs on the admin workstation: GAM for the Workspace side under the admin's authorization, the
Fleet REST API with the session fleetctl holds (~/.fleet/config) or FLEET_URL and FLEET_API_TOKEN
from the environment. Standard library only. Prints Markdown.

A read that fails is never taken for an empty answer. A failed account or Chromebook listing stops
the report (reason on stderr, exit 1); a Fleet that cannot be read is said so above the table and
the report exits 1; an account whose own read fails is a NOT READ row. GAM reads are retried three
times, as the shell scripts' gam_read does.

usage: lifecycle-report.py [--gam PATH]
"""
import csv
import io
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROLES = os.path.join(HERE, "roles")
GAM = os.environ.get("GAM") or os.path.expanduser("~/bin/gam7/gam")
if len(sys.argv) == 3 and sys.argv[1] == "--gam":
    GAM = sys.argv[2]


class ReadError(Exception):
    """A listing or lookup the report depends on could not be read."""


def gam(*args, tries=3):
    """A GAM read, retried like common.sh's gam_read: three tries two seconds apart, unless the
    exit status is itself an answer (56, does not exist, returns empty output). Raises ReadError
    after the last failed try rather than returning an empty answer."""
    reason = "no output"
    for n in range(tries):
        try:
            out = subprocess.run([GAM, *args], capture_output=True, text=True, check=False)
        except OSError as err:  # GAM missing, not executable, or not where GAM points
            raise ReadError("cannot run %s: %s" % (GAM, err))
        if out.returncode == 0:
            return out.stdout
        if out.returncode == 56:
            return ""
        lines = out.stderr.strip().splitlines() or out.stdout.strip().splitlines()
        reason = "exit %d: %s" % (out.returncode, lines[-1] if lines else "no output")
        if n + 1 < tries:
            time.sleep(2)
    raise ReadError("gam %s failed after %d tries (%s)" % (" ".join(args), tries, reason))


def roles():
    """department -> role name, device class, from the catalog files."""
    by_dept = {}
    for name in sorted(os.listdir(ROLES)):
        if not name.endswith(".conf"):
            continue
        conf = {}
        with open(os.path.join(ROLES, name), encoding="utf-8") as f:
            for line in f:
                if "=" in line and not line.startswith("#"):
                    k, v = line.rstrip("\n").split("=", 1)
                    conf[k] = v
        by_dept[conf.get("ROLE_DEPARTMENT", "")] = (conf.get("ROLE_NAME", name), conf.get("ROLE_DEVICE", ""))
    return by_dept


def unread_user(email, why):
    return {"email": email, "name": "", "ou": "", "department": "", "suspended": False, "reason": "", "twosv": False, "not_read": why}


def workspace_users():
    listing = gam("print", "users", "fields", "primaryemail")
    emails = [r["primaryEmail"] for r in csv.DictReader(io.StringIO(listing))]
    if not emails:
        # The administrator is always a row, so an empty listing is a failed read, not an empty tenant.
        raise ReadError("gam print users returned no accounts")
    users = []
    for e in sorted(emails):
        try:
            j = json.loads(gam("info", "user", e, "quick", "formatjson") or "{}")
        except (ReadError, ValueError) as err:
            users.append(unread_user(e, str(err)))
            continue
        if not j:
            users.append(unread_user(e, "listed, then not found"))
            continue
        orgs = j.get("organizations") or [{}]
        users.append({
            "email": e,
            "name": (j.get("name") or {}).get("fullName", ""),
            "ou": j.get("orgUnitPath", ""),
            "department": orgs[0].get("department", ""),
            "suspended": bool(j.get("suspended")),
            "reason": j.get("suspensionReason", ""),
            "twosv": bool(j.get("isEnrolledIn2Sv")),
            "not_read": "",
        })
    return users


def fleet_session():
    url, token = os.environ.get("FLEET_URL"), os.environ.get("FLEET_API_TOKEN")
    cfg = os.path.expanduser(os.environ.get("FLEET_CONFIG", "~/.fleet/config"))
    if (not url or not token) and os.path.exists(cfg):
        with open(cfg, encoding="utf-8") as f:
            for line in f:
                s = line.strip()
                if s.startswith("address:") and not url:
                    url = s.split(":", 1)[1].strip()
                if s.startswith("token:") and not token:
                    token = s.split(":", 1)[1].strip()
    return url, token


def fleet_get(path):
    url, token = fleet_session()
    if not url or not token:
        raise ReadError("no Fleet session: run fleetctl login, or set FLEET_URL and FLEET_API_TOKEN")
    # The server sits behind a Cloudflare tunnel, which refuses Python's default User-Agent, so the
    # request names itself for what it is.
    req = urllib.request.Request(url + path, headers={"Authorization": "Bearer " + token, "User-Agent": "endpoint-identity-lab/lifecycle-report"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except (urllib.error.URLError, OSError, ValueError) as err:
        raise ReadError("Fleet %s: %s" % (path, err))


def fleet_hosts():
    """custom-mapped email -> list of host summaries (also 'unmapped' for hosts with none). Raises
    ReadError when Fleet cannot be read; an empty dict means Fleet answered and has no hosts."""
    data = fleet_get("/api/v1/fleet/hosts?device_mapping=true&per_page=500")
    hosts = {}
    for h in data.get("hosts", []):
        full = fleet_get("/api/v1/fleet/hosts/%d" % h["id"]).get("host", {})
        pols = full.get("policies") or []
        passing = sum(1 for p in pols if p.get("response") == "pass")
        failing = [p["name"] for p in pols if p.get("response") == "fail"]
        pending = sum(1 for p in pols if not p.get("response"))
        emails = [m["email"] for m in (h.get("device_mapping") or []) if m.get("source") == "custom"]
        summary = {
            "kind": "Mac",
            "id": "%s (%s)" % (h.get("hostname", ""), h.get("hardware_serial", "")),
            "mgmt": "Fleet, MDM %s, %s" % ((full.get("mdm") or {}).get("enrollment_status", "?"), h.get("status", "?")),
            "labels": ", ".join(l["name"] for l in full.get("labels", []) if l["name"].startswith("role-")) or "no role label",
            "compliance": "%d/%d policies pass" % (passing, len(pols)) + (", failing: " + "; ".join(failing) if failing else "") + (", %d not yet evaluated" % pending if pending else ""),
            "lock": (full.get("mdm") or {}).get("device_status", ""),
        }
        for e in emails or ["unmapped"]:
            hosts.setdefault(e.lower(), []).append(summary)
    return hosts


def chromebooks():
    """annotated user -> list of device summaries. A tenant with no Chromebooks answers with a header
    and no rows, which is an answer; a failed listing raises from gam()."""
    out = {}
    rows = csv.DictReader(io.StringIO(gam("print", "cros", "fields", "deviceid,serialnumber,status,orgunitpath,annotateduser")))
    for r in rows:
        out.setdefault((r.get("annotatedUser") or "unmapped").lower(), []).append({
            "kind": "Chromebook",
            "id": r.get("serialNumber", ""),
            "mgmt": "Workspace, %s, OU %s" % (r.get("status", "?"), r.get("orgUnitPath", "?")),
            "labels": "",
            "compliance": "user policy follows the user's OU",
            "lock": "",
        })
    return out


def main():
    by_dept = roles()
    try:
        users = workspace_users()
        cros = chromebooks()
    except ReadError as err:
        print("error: %s; nothing reported" % err, file=sys.stderr)
        return 1
    fleet_note = ""
    try:
        macs = fleet_hosts()
    except ReadError as err:
        macs = {}
        fleet_note = str(err)
    if fleet_note:
        print("> **Fleet not read** (%s): no Mac is shown for anyone below, and the Device column holds Chromebooks only." % fleet_note)
        print()
    print("| Account | Role | OU | State | Device | Management | Compliance |")
    print("|---|---|---|---|---|---|---|")
    for u in users:
        if u["not_read"]:
            print("| %s | | | NOT READ (%s) | | | |" % (u["email"], u["not_read"].replace("|", "/")))
            continue
        role, dev_class = by_dept.get(u["department"], ("none", ""))
        state = ("suspended (%s)" % u["reason"]) if u["suspended"] else ("active, 2SV %s" % ("on" if u["twosv"] else "off"))
        devices = macs.get(u["email"].lower(), []) + cros.get(u["email"].lower(), [])
        if not devices:
            dev = "none (own computer)" if dev_class == "byod" else "none"
            if fleet_note and dev_class not in ("byod", "chromeos"):
                dev = "Mac not read"
            print("| %s | %s | %s | %s | %s | | |" % (u["email"], role, u["ou"], state, dev))
        for d in devices:
            extra = (", " + d["labels"]) if d["labels"] else ""
            lock = (", " + d["lock"]) if d["lock"] else ""
            print("| %s | %s | %s | %s | %s %s | %s%s%s | %s |" % (u["email"], role, u["ou"], state, d["kind"], d["id"], d["mgmt"], extra, lock, d["compliance"]))
    for key, label in (("unmapped", "IT custody, unassigned"),):
        for d in macs.get(key, []) + cros.get(key, []):
            print("| (%s) | | | | %s %s | %s%s | %s |" % (label, d["kind"], d["id"], d["mgmt"], (", " + d["labels"]) if d["labels"] else "", d["compliance"]))
    unread = sum(1 for u in users if u["not_read"])
    if unread:
        print()
        print("> **%d account(s) not read** after three tries each; rerun before acting on this table." % unread)
    return 1 if fleet_note or unread else 0


if __name__ == "__main__":
    sys.exit(main())
