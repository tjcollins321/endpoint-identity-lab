# Runbook: onboarding

**When to use this:** a new employee or contractor needs a Google Workspace account, membership
of the groups their role uses, and a managed device.

**When NOT to use this:** reactivating a suspended account, or moving someone between
organizational units. Both are single commands, listed under Related changes.

Inputs, agreed before starting:

| Input | Where it comes from | Example |
|---|---|---|
| Full name | The hiring record | Dana Okafor |
| Organizational unit | Employee: `/Staff`. Contractor: `/Contractors` | `/Staff` |
| Groups | The role's access: `all-staff` for every employee; `engineering`, `contractors` by role | `all-staff`, `engineering` |
| Notification address | A personal mailbox that receives the initial password, or none | (none) |
| Device | Mac, iPad, or ChromeOS device to enroll | (device sections) |

The Workspace steps run from the admin workstation with the scripts in `workspace/gam/`
(setup: `gam-setup.md`). Every script can be re-run; a second run reports and changes nothing.

---

## 1. Create the account

```bash
workspace/gam/create-user.sh -o /Staff "Dana" "Okafor"
```

What it does: derives the username from the convention (first initial plus last name, lowercase,
letters and digits only), checks whether that address already belongs to this person (then it
stops) or to someone else (then it tries `dokafor2`, `dokafor3`, and so on), and creates the
account in the destination OU with a random password that must be changed at the first sign-in.
Accounts are created in their OU, never in the root and moved, because settings inherit down the
tree and the root is the strictest baseline. With `-n address`, Google mails the initial password
to that address; without it the password is shown nowhere and the admin issues a reset before
the first day (Related changes).

Success looks like:

```
t+0:00    creating dokafor@tjcollins.dev (Dana Okafor) in /Staff
User: dokafor@tjcollins.dev, Created
t+0:02    verify:
    First Name: Dana
    Last Name: Okafor
    Google Org Unit Path: /Staff
```

If a `note:` line follows saying Google holds the account with reason `WEB_LOGIN_REQUIRED`, see
step 3; it is not an error.

## 2. Grant access through groups

```bash
workspace/gam/add-to-groups.sh dokafor all-staff engineering
```

What it does: adds the account to each group as a member, skipping any it is already in, and
reads each membership back. Groups carry access (applications, Drive sharing, group-scoped
settings), so this is where the role's access is granted; the OU carries policy. Owners and
managers are deliberate console changes, not part of onboarding.

Success looks like:

```
  dokafor@tjcollins.dev is a member of all-staff@tjcollins.dev
  dokafor@tjcollins.dev is a member of engineering@tjcollins.dev
```

## 3. First sign-in

- The user signs in on the web with the initial password and is made to change it. The tenant
  enforces 2-Step Verification with a one-day enrollment window and no SMS or voice codes, so
  the user enrolls an authenticator app or passkey at this sign-in.
- Contractors are signed out after twelve hours by the `/Contractors` session policy; staff
  after seven days.
- An account created through the API can be placed on hold by Google (`WEB_LOGIN_REQUIRED`).
  The user clears it by signing in on the web; an administrator cannot lift it. Warn the user
  that the first sign-in may ask for a verification step.

## 4. Devices

Written with the device phases: a Mac into Jamf Now (`mac-enrollment.md`), a Mac into Fleet
(`mac-provisioning.md`), an iPad (`ipados-enrollment.md`), a ChromeOS device
(`chromeos-enrollment.md`).

## 5. Verify

```bash
gam info user dokafor
```

Shows the OU path, the groups, 2-Step Verification enrollment, and the last sign-in. The Admin
console's audit log (Reporting, Audit and investigation, Admin log events) records the create
and the group adds with the actor and time. `docs/evidence/05-workspace-gam-lifecycle-run.txt`
is a complete run.

## Related changes

- Initial password by hand: `gam update user dokafor password random changepassword on notify personal@example.com`
- Move between OUs: `gam update user dokafor ou /Contractors`
- Reactivate a suspended account: `gam unsuspend user dokafor`, then step 2 if groups changed

## Problems hit

- **New accounts held by Google.** Every account created through the API on the day-old tenant
  was suspended one second later with reason `WEB_LOGIN_REQUIRED`; accounts created in the
  console the day before were not. `gam unsuspend user` answers "Cannot restore a user
  suspended for abuse", so only the user's own web sign-in clears it. The create script reads
  the state back and prints the note; the offboarding scripts treat any suspension as
  suspended and report the reason.
- **Reads lag writes.** `gam print users query` and `gam print groups member` search an index
  that lags a minute or more; an account created seconds earlier is invisible to them and a
  deleted one lingers. The scripts use direct lookups (`gam info user`, `gam check suspended`,
  `gam print group-members` for one group) for every decision.
- **A deleted address is reserved for 20 days**, while the account can be restored, so a
  second test run needs different names.
