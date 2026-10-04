# Role-based lifecycle automation

One command per lifecycle event, driven by a role catalog, across Google Workspace, Fleet (the
Macs), and the ChromeOS devices in the Workspace console. Jamf Now has no API, so its steps are
printed as a checklist. The five single-purpose GAM scripts in `workspace/gam/` do the Workspace
writes; the scripts here decide what to do from the role and read everything back.

| Command | Event | What it does |
|---|---|---|
| `onboard.sh <role> First Last` | a hire | account in the role's OU with title, department, and manager; the role's groups; the welcome kit; the Mac mapped and labeled in Fleet, or the Chromebook annotated and moved to the device OU |
| `change-role.sh <user> <role>` | a transfer or reorg | OU, groups, title, department, and the device's role label converged to the new role; one-off grants kept and reported |
| `offboard.sh <user>` | a leaver | access cut first; Drive and Calendar to the manager; groups removed; the `/Offboarded` OU; work account wiped from personal devices; the Mac locked and reclaimed or the Chromebook disabled; the console account deleted; deletion queued |
| `onboard-batch.sh hires.csv` | the hire record | one `onboard.sh` per row of what an HRIS export or a ticket would deliver (`examples/hires.csv`) |
| `audit-access.sh` | a review | every account's OU and groups against the catalog: mismatches, and one-off grants to review |

Every script can be re-run: a second run reports `ok:` on every line and changes nothing. A lookup
that fails, in the directory or in Fleet, is retried and then reported as `FAIL`, never taken for
"nothing to do". Each ends with a read-back (`== verify`), the steps a human still does
(`== manual steps`), and the count of
failures; exit 0 all ok, 1 a step failed or a precondition did not hold (an unknown role, a missing
account), 2 usage error. `-n` is a read-only dry run.
The scripts run on the admin workstation under the admin's own authorization: bash 3.2, shellcheck
clean, no service account, no domain-wide delegation. When the trigger is a system rather than a
person, this moves to a service on an always-on runner; `docs/design.md` says what else changes.

## The role catalog

One file per role in `roles/`, `KEY=value`, read as data (never sourced). The OU carries policy,
the groups carry access, the device line is the entitlement, the Fleet label scopes role software.

| Role | OU | Groups | Title / department | Company device | Fleet label | Apps by label |
|---|---|---|---|---|---|---|
| Engineer | `/Staff` | `all-staff`, `engineering` | Software Engineer / Engineering | Mac | `role-engineer` | Slack, VS Code |
| Marketing | `/Staff` | `all-staff`, `marketing` | Marketing Manager / Marketing | Mac | `role-marketing` | Slack, Zoom |
| Sales | `/Staff` | `all-staff`, `sales` | Account Executive / Sales | Chromebook | none | none |
| Contractor | `/Contractors` | `contractors` | Contractor / External | none (own computer) | none | none |

`engineering` is also the SAML grant to the Fleet console (`runbooks/sso-app-setup.md`). The
`/Contractors` OU signs its users out after twelve hours. A group that no role grants is a one-off:
a role change keeps it and says so, and the audit lists it for review.

## One device per person, chosen by the role

| Device | Owned by | Managed by | How it enrolls |
|---|---|---|---|
| Mac | company | Fleet; Jamf Now for the admin workstation | user-approved MDM, baseline from GitOps |
| iPad | company | Jamf Now | Open Enrollment |
| Chromebook | company | Workspace, ChromeOS Enterprise Upgrade | enterprise enrollment at first sign-in |
| Phone, iOS or Android | personal | Workspace mobile management | add the work account, approve the device |
| Contractor computer | personal or agency | not enrolled: account layer only (OU session policy, the Chrome profile the work account signs into, Drive sharing) | sign in to Chrome with the work account |

Nobody gets two company devices; a personal phone can carry the work account whatever the primary
device. Jamf Now never sees a personal device. The reasoning is in `docs/design.md`.

## How the device assignment works in Fleet

A Mac's role is a label. The label is declared in `fleet/gitops/labels/role-<role>.yml` as a manual
label with no `hosts:` key, on purpose: Fleet keeps a manual label's membership when the key is
absent and clears it when the key is present, even empty. So configuration owns what a label is and
what it entitles (the software scoped to it in `fleet/gitops/fleets/workstations.yml`), and
`onboard.sh`, `change-role.sh`, and `offboard.sh` own which Macs are in it, through the API. A
label created outside git is deleted on the next apply; assigning a device needs no apply at all.
Two rules follow: never add a `hosts:` key to a role label file, and never rename a role label in
YAML once a Mac holds it, since Fleet deletes and re-creates a renamed label and clears its members.
The person-to-device link is Fleet's custom human-device mapping, set by the same scripts.

## What stays manual, and why

- Any mail from GAM, and any setting on a mailbox. GAM sends mail (the welcome kit, the
  initial-password notification) and changes mailbox settings (forwarding) only through a service
  account with domain-wide delegation, acting as a user; the tenant grants neither, by decision.
  So `onboard.sh` renders the welcome kit to `lifecycle/outbox/` (ignored by git) and the admin
  sends it from their own mailbox; the initial password is issued from the Admin console or handed
  over with the device; and a leaver's new mail is redirected to the manager by a recipient address
  map in the console, which has no API, while the mailbox keeps what it already held (Google
  delivers nothing new to a suspended account). Delegation, which
  opens the whole mailbox, is never a default. Where delegation exists, the same scripts send
  through GAM. At scale the mail and the forwarding come from the HRIS or ticketing integration, or
  from a service identity scoped to sending and mailbox settings.
- Jamf Now: lock, wipe, and unenroll for the iPad and the admin workstation are console steps.
- The initial password when no personal address is given; the unlock PIN when a locked Mac returns.
- The lock on a virtual Mac. `offboard.sh` reads the hardware model from Fleet and never locks a
  virtual Mac, which cannot draw the PIN screen and so could never be unlocked; the VM is shut down
  or wiped by hand (`runbooks/offboarding.md`, Problems hit).
- Slack deactivation, where a free workspace exists; SCIM is the at-scale answer.

## Command reference

Bare usernames get the tenant's domain; `-n` is a dry run on every script; every run ends with
`== verify`, `== manual steps`, and `N failed`.

```
onboard.sh [-p personal@] [-m manager] [-s YYYY-MM-DD] [-d serial-or-device-id] [-W] [-D] [-n] <role> First Last
   -p where the welcome kit goes (and the password, where GAM can mail it); -m the manager relation;
   -s the start date (default today); -d the issued Mac's serial or the Chromebook's device id;
   -W render or send the welcome kit again; -D skip the device step
offboard.sh [-e] [-m new-owner] [-y] [-D] [-n] <user>
   -e emergency form: cut access and stop; -m who receives Drive and the calendars;
   -y lock a Fleet-managed Mac without asking; -D skip the device steps
change-role.sh [-t "Title"] [-m manager] [-d serial-or-device-id] [-S] [-D] [-n] <user> <new-role>
   -t a title other than the role's default; -d a newly issued device; -S strict: remove every group
   not in the new role, one-off grants included
onboard-batch.sh [-n] [-M] hires.csv        one onboard.sh per row; -M mails the results where GAM can
audit-access.sh [-q]                        read-only; exit 1 on any mismatch
lifecycle-report.py                         read-only; the joined table in Markdown
```

Example runs, from the repository root:

```bash
lifecycle/onboard.sh -p them@example.com -m aengineer -s 2026-10-06 -d ZQGCYXVWFJ engineer Priya Raman
lifecycle/onboard-batch.sh lifecycle/examples/hires.csv
lifecycle/change-role.sh -d Z597CMKJ30 jmbeki engineer
lifecycle/offboard.sh -m aengineer praman
lifecycle/offboard.sh -e praman          # access cut now, the rest when the paperwork catches up
lifecycle/audit-access.sh
```

A rehire of an offboarded account is `gam unsuspend user <user>` followed by `change-role.sh`;
`onboard.sh` refuses it on purpose. Deletion is `workspace/gam/delete.sh`, which refuses unless the
account is suspended, in `/Offboarded`, has a completed Drive transfer, and has reached the
deletion date `offboard.sh` wrote into its note.

## Where the state lives

Nothing is stored by these scripts. The role is the account's department; the device assignment
is Fleet's human-device mapping and the Chromebook's annotated user; the offboarding date and the
earliest deletion date are in the account's note. Every run reads that state and converges to the
catalog, which is why a second run changes nothing and why `audit-access.sh` can be run at any
time.
