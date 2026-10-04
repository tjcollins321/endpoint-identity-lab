#!/usr/bin/env python3
"""One table joining the two halves of the lifecycle: every Workspace account with its role, OU,
state, and the company device it holds (a Fleet-managed Mac by the person-to-device mapping, a
Chromebook by its annotated user), with the device's management and compliance state. Read-only.

Runs on the admin workstation: GAM for the Workspace side under the admin's authorization, the
Fleet REST API with the session fleetctl holds (~/.fleet/config) or FLEET_URL and FLEET_API_TOKEN
from the environment. Standard library only. Prints Markdown.

usage: lifecycle-report.py [--gam PATH]
"""
import csv
import io
import json
import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROLES = os.path.join(HERE, "roles")
GAM = os.environ.get("GAM") or os.path.expanduser("~/bin/gam7/gam")
if len(sys.argv) == 3 and sys.argv[1] == "--gam":
    GAM = sys.argv[2]


def gam(*args):
    out = subprocess.run([GAM, *args], capture_output=True, text=True, check=False)
    return out.stdout


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


def workspace_users():
    emails = [r["primaryEmail"] for r in csv.DictReader(io.StringIO(gam("print", "users", "fields", "primaryemail")))]
    users = []
    for e in sorted(emails):
        j = json.loads(gam("info", "user", e, "quick", "formatjson") or "{}")
        orgs = j.get("organizations") or [{}]
        users.append({
            "email": e,
            "name": (j.get("name") or {}).get("fullName", ""),
            "ou": j.get("orgUnitPath", ""),
            "department": orgs[0].get("department", ""),
            "suspended": bool(j.get("suspended")),
            "reason": j.get("suspensionReason", ""),
            "twosv": bool(j.get("isEnrolledIn2Sv")),
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
        return None
    # The server sits behind a Cloudflare tunnel, which refuses Python's default User-Agent, so the
    # request names itself for what it is.
    req = urllib.request.Request(url + path, headers={"Authorization": "Bearer " + token, "User-Agent": "endpoint-identity-lab/lifecycle-report"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def fleet_hosts():
    """custom-mapped email -> list of host summaries (also 'unmapped' for hosts with none)."""
    data = fleet_get("/api/v1/fleet/hosts?device_mapping=true&per_page=500")
    if data is None:
        return {}
    hosts = {}
    for h in data.get("hosts", []):
        full = (fleet_get("/api/v1/fleet/hosts/%d" % h["id"]) or {}).get("host", {})
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
    """annotated user -> list of device summaries."""
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
    users = workspace_users()
    macs = fleet_hosts()
    cros = chromebooks()
    print("| Account | Role | OU | State | Device | Management | Compliance |")
    print("|---|---|---|---|---|---|---|")
    for u in users:
        role, dev_class = by_dept.get(u["department"], ("none", ""))
        state = ("suspended (%s)" % u["reason"]) if u["suspended"] else ("active, 2SV %s" % ("on" if u["twosv"] else "off"))
        devices = macs.get(u["email"].lower(), []) + cros.get(u["email"].lower(), [])
        if not devices:
            dev = "none (own computer)" if dev_class == "byod" else "none"
            print("| %s | %s | %s | %s | %s | | |" % (u["email"], role, u["ou"], state, dev))
        for d in devices:
            extra = (", " + d["labels"]) if d["labels"] else ""
            lock = (", " + d["lock"]) if d["lock"] else ""
            print("| %s | %s | %s | %s | %s %s | %s%s%s | %s |" % (u["email"], role, u["ou"], state, d["kind"], d["id"], d["mgmt"], extra, lock, d["compliance"]))
    for key, label in (("unmapped", "IT custody, unassigned"),):
        for d in macs.get(key, []) + cros.get(key, []):
            print("| (%s) | | | | %s %s | %s%s | %s |" % (label, d["kind"], d["id"], d["mgmt"], (", " + d["labels"]) if d["labels"] else "", d["compliance"]))


if __name__ == "__main__":
    main()
