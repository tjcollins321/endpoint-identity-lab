# Runbook: onboarding

**When to use this:** a new employee or contractor starts. One command creates the account in the
role's organizational unit, grants the role's access, prepares the welcome kit, and assigns the
company device the role entitles. The role catalog in `lifecycle/roles/` decides all of it.

**When NOT to use this:** a transfer or reorg (`role-change.md`), a rehire of an offboarded
account (`gam unsuspend user`, then `role-change.md`; `onboard.sh` refuses it), or reactivating
a suspended account (Related changes).

Inputs, agreed before starting:

| Input | Where it comes from | Example |
|---|---|---|
| Role | The catalog: `engineer`, `marketing`, `sales`, `contractor` (`lifecycle/README.md`) | `marketing` |
| Full name | The hiring record | Jordan Mbeki |
| Personal address | Where the welcome kit goes before the first day; none if the manager relays it | a mailbox the hire reads |
| Manager | A username or address in the tenant; also receives Drive and Calendar at offboarding | `aengineer` |
| Start date | The hiring record | `2026-10-06` |
| Device | A Mac's serial (enrolled in Fleet first, `mac-provisioning-fleet.md`) or a Chromebook's device id (enrolled first, `chromeos-enrollment.md`); none for a BYOD role | `Z597CMKJ30` |

Preconditions: GAM authorized on the admin workstation (`gam-setup.md`); `fleetctl` logged in to
the Fleet server; the role's groups exist (`workspace/tenant-settings.md`); the device enrolled.
The hire record can also be a CSV (`lifecycle/examples/hires.csv`), one row per hire, in which
case step 1 is `lifecycle/onboard-batch.sh hires.csv` and the rest is the same.

---

## 1. Run the onboarding

```bash
lifecycle/onboard.sh -p them@example.com -m aengineer -s 2026-10-06 -d Z597CMKJ30 marketing Jordan Mbeki
```

What it does, in order, reading before every write so a second run changes nothing:

1. **Account.** The username from the convention (first initial plus last name, lowercase, a digit
   suffix on a collision with a different person), created in the role's OU with a random password
   that must be changed at the first sign-in. Never created in the root and moved: the root is the
   strictest baseline and settings inherit down.
2. **Directory attributes.** Title and department from the role, the manager relation from `-m`.
   The department is how every later command, the audit, and the report know the role.
3. **Access.** The role's groups, each read back. Groups carry access; `engineering` is also the
   SAML grant to the Fleet console, whose account appears at the first sign-in.
4. **Welcome kit.** The role's template rendered with the name, address, manager, and start date.
   GAM can send it only through domain-wide delegation, which this tenant does not grant, so the
   kit is written to `lifecycle/outbox/` for hand-sending (step 2).
5. **Device.** A Mac: mapped to the person in Fleet and added to the role label, which makes the
   role's apps arrive (Slack for every Mac; VS Code for engineers, Zoom for marketing) through the
   install policies in `fleet/gitops/`. A Chromebook: annotated with the person and moved to the
   device OU; user policy follows the person's OU. A BYOD role: nothing to assign.
6. **Read-back,** then the checklist of what a human still does.

Success looks like (offsets from the start of the run; the real transcript is
`docs/evidence/14-lifecycle-onboard-run.txt`):

```
t+0:00  == onboarding Jordan Mbeki as Marketing (OU /Staff, groups: all-staff marketing, device: mac), start 2026-10-06
t+0:02  creating jmbeki@tjcollins.dev (Jordan Mbeki) in /Staff
User: jmbeki@tjcollins.dev, Created
t+0:04  changed: created jmbeki@tjcollins.dev in /Staff
t+0:12  changed: title Marketing Manager, department Marketing
t+0:14  changed: manager aengineer@tjcollins.dev
t+0:24  ok: groups: all-staff marketing
t+0:25  changed: welcome kit rendered to lifecycle/outbox/welcome-jmbeki.txt (GAM sends mail only through domain-wide delegation, which this tenant does not grant)
t+0:26  changed: Fleet host vm2-fleet.local (Z597CMKJ30) mapped to jmbeki@tjcollins.dev
t+0:26  changed: vm2-fleet.local added to role-marketing
t+0:26  == verify jmbeki@tjcollins.dev
t+0:27    OU: /Staff (role: /Staff)
t+0:28    active
t+0:31    title: Marketing Manager; department: Marketing; manager: aengineer@tjcollins.dev
t+0:33    group all-staff: member
t+0:34    group marketing: member
t+0:35    2-step enrolled: false
t+0:36    Fleet host Z597CMKJ30: mapping jmbeki@tjcollins.dev; labels: role-marketing
t+0:36  == manual steps
[ ] issue the initial password: Admin console, Users, Jordan Mbeki, Reset password, email it to them@example.com; or set one and hand it over with the device
[ ] send lifecycle/outbox/welcome-jmbeki.txt from the admin mailbox to them@example.com
[ ] hand the Mac (vm2-fleet.local) to Jordan on 2026-10-06; at the first login they run scripts/mac-onboard.sh marketing
[ ] after the first sign-in, confirm 2-Step Verification enrollment: gam info user jmbeki@tjcollins.dev shows 2-step enrolled
t+0:36  == 0 failed
```

A `FAIL:` line names the step; fix the cause and run the same command again, which repeats
nothing that succeeded. `-n` shows every step without changing anything.

## 2. Send the welcome kit and issue the password

Two steps a person does, because the tenant grants GAM no authority to act as a mailbox
(`docs/design.md`, identity section):

- Open `lifecycle/outbox/welcome-<username>.txt`; the first two lines are the recipient and the
  subject. Send it from the admin mailbox, then delete the file.
- Admin console, Users, the person, Reset password, "Email password" to the personal address; or
  set a password and hand it over with the device on the first day.

## 3. Hand over the device

- **Mac.** The MDM has already delivered the baseline (passcode, FileVault, restrictions, the
  Chrome enrollment token) and the apps follow the role label within the policy interval. At the
  first login the person runs, as themselves, `scripts/mac-onboard.sh <role>`: Homebrew for
  engineers, the per-user defaults for everyone; a second run reports nothing to do. Then
  `sudo scripts/mac-verify.sh <role>` reads everything back, or the same script runs from Fleet:

  ```bash
  fleetctl run-script --host <hostname> --script-path scripts/mac-verify.sh
  ```

- **Chromebook.** The person signs in with the work account; the device is already enrolled and
  annotated to them. `chrome://policy` on the device shows the user policies of their OU.
- **Own computer (contractors).** Nothing is installed. The welcome kit says to use Chrome signed
  in with the work account, which receives the browser settings and the twelve-hour session.

## 4. First sign-in

- The initial password must be changed. The tenant enforces 2-Step Verification with a one-day
  enrollment window counted from this first sign-in, no SMS or voice codes, so the person enrolls
  an authenticator app or a passkey now.
- Contractors are signed out after twelve hours by the `/Contractors` session policy; staff after
  seven days.
- An account created through the API can be placed on hold by Google (`WEB_LOGIN_REQUIRED`). The
  person clears it by signing in on the web; an administrator cannot. The run reports the hold as
  a note, not an error.

## 5. Verify

```bash
lifecycle/onboard.sh -p them@example.com -m aengineer -s 2026-10-06 -d Z597CMKJ30 marketing Jordan Mbeki
gam info user jmbeki
lifecycle/audit-access.sh
```

The first repeats the run and prints `ok:` on every line with `0 failed`. The second shows the OU,
title, department, manager, groups, and 2-Step Verification state. The audit confirms the account
matches its role and lists any grant outside the catalog. The Fleet host page shows the mapping
under "Used by", the role label, and the role's apps once installed; `lifecycle/lifecycle-report.py`
shows the same in one table. The Admin console's audit log records every write with the actor.

## Related changes

- One step by hand, when the orchestrator is not wanted: `workspace/gam/create-user.sh -o /Staff "First" "Last"`, `workspace/gam/add-to-groups.sh user group...`, then the Fleet mapping and label from the host page.
- Resend the welcome kit: add `-W` to the same command.
- Assign a device later: the same command with `-d <serial or device id>`.
- Reactivate a suspended account that was not offboarded: `gam unsuspend user <user>`.
- A rehire: `gam unsuspend user <user>`, then `lifecycle/change-role.sh <user> <role>`.

## Problems hit

- **GAM cannot send mail here.** `gam sendemail` and the `notify` option of `gam create user`
  fail with "Service Account OAuth2 File ... Does not exist or has invalid format": GAM mails only
  through a service account with domain-wide delegation, acting as a user, and the admin OAuth
  client cannot. The tenant grants neither by decision, and the file in `~/.gam` is the setup
  wizard's keyless placeholder, so the scripts check for a key before trying. The welcome kit
  became a file in the outbox and the password a console step; where delegation exists the same
  scripts send through GAM.
- **A new membership reads back late.** `add-to-groups.sh` reported "NOT a member" two seconds
  after a successful add on a brand-new account; the membership was there ten seconds later. The
  verify in that script and the lifecycle read-backs retry for about twenty seconds before calling
  a membership missing.
- **Fleet's host object hides the mapping.** `GET /hosts/identifier/<serial>` returns
  `device_mapping: null` even after a successful `PUT .../device_mapping`; the mapping is read
  from `GET /hosts/<id>/device_mapping` or from the host list with `device_mapping=true`.
- **New accounts held by Google.** Every account created through the API on the day-old tenant was
  suspended one second later with reason `WEB_LOGIN_REQUIRED`; only the person's own web sign-in
  clears it. The scripts treat the hold as a note; the offboarding scripts treat any suspension as
  suspended and report the reason.
- **Reads lag writes.** `gam print users query` and `gam print groups member` search an index that
  lags a minute or more; the scripts use direct lookups (`gam info user`, `gam user X print groups`,
  `gam print group-members` for one group) for every decision.
- **A deleted address is reserved for 20 days**, while the account can be restored, so a second
  test run needs different names.
