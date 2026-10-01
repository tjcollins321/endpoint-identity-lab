# Runbook: offboarding

**When to use this:** an employee or contractor leaves, or access has to end now while the
paperwork catches up. The emergency form (`-e`) cuts access and stops; the full form does the rest.

**When NOT to use this:** a leave of absence (`workspace/gam/suspend.sh` alone, nothing transferred
or removed), a transfer (`role-change.md`), or a name change (an alias, not a new account).

The order is the point: cut access first while every byte of data stays where it is, move the
data to someone who stays, remove access, deal with the devices, and delete last, after a
retention period, with `delete.sh` refusing until the earlier steps are done.

Inputs: the username, and who receives the Drive files and the calendars (usually the manager
the directory names). Preconditions as in `onboarding.md`.

---

## 1. Emergency form: cut access now

```bash
lifecycle/offboard.sh -e praman
```

Deletes the account's app passwords, backup verification codes, and OAuth tokens, signs out every
session, then suspends. Deprovisioning comes first because Google refuses the backup-code step on
an account that is already suspended. After this the person cannot sign in anywhere, including
through SAML to the Fleet console. Mail keeps arriving and is retained; Drive, Calendar, groups,
and devices are untouched. Nothing is lost. The checklist says how to finish.

## 2. Full form

```bash
lifecycle/offboard.sh -m aengineer -y praman
```

What it does, in order (a failed suspend stops the run; anything after it continues and is reported):

1. **Cut access**, as above, or `ok` if already suspended by an administrator.
2. **Data to someone who stays.** Drive ownership, private and shared files, then the calendars
   with room bookings released, both through the Data Transfer API, the same mechanism as the
   Admin console's Transfer ownership button, under the admin's own authorization. A completed
   transfer between the same two accounts is reported, not repeated. Mail is not transferred: it
   stays in the suspended mailbox and in Vault, and new mail is copied to the manager by a Gmail
   routing rule, a console step (step 3) because routing has no API.
3. **Access removed.** Every group membership, read directly and removed one by one.
4. **The leavers' OU.** The account moves to `/Offboarded`, the Disabled Users OU of this tenant:
   reports exclude it, a mistaken unsuspend grants nothing, and the account note records the date
   and the earliest deletion date, thirty days on.
5. **Personal devices.** Any phone or tablet under Workspace mobile management gets an account
   wipe: the work account and its data leave the device, nothing personal is touched.
6. **Company devices.** A Fleet-managed Mac found by its mapping is locked (`-y` answers the prompt;
   without it the lock is a checklist line), removed from its role label, and mapped back to the
   admin, which is IT custody. A Chromebook annotated to the person is disabled, which shows the
   return message on its screen until re-enabled. Jamf Now has no API, so an iPad or a Mac enrolled
   there is a console step on the checklist.
7. **Application accounts identity does not remove.** The Fleet console account that just-in-time
   provisioning created is deleted through the API.
8. **Read-back,** then the checklist.

Success looks like (offsets from the start; the real transcript is
`docs/evidence/17-lifecycle-offboard-run.txt`):

```
t+0:00  == offboarding praman@tjcollins.dev (engineer)
t+0:03  deprovisioning praman@tjcollins.dev: app passwords, backup codes, OAuth tokens, sign-out
t+0:04  suspending praman@tjcollins.dev
User: praman@tjcollins.dev, Suspended
t+0:07  changed: access cut: praman@tjcollins.dev suspended
t+0:23  changed: Drive transferred to aengineer@tjcollins.dev
t+0:32  changed: Calendar transferred to aengineer@tjcollins.dev
t+0:35  changed: removed from all-staff@tjcollins.dev
t+0:37  changed: removed from engineering@tjcollins.dev
t+0:39  changed: moved to /Offboarded; delete on or after 2026-10-31
t+0:40  ok: no personal devices under Workspace mobile management
t+0:42  changed: lock sent to vm1-jamf.local (ZQGCYXVWFJ)
t+0:43  changed: vm1-jamf.local removed from role-engineer
t+0:43  changed: vm1-jamf.local mapped to tj@tjcollins.dev
t+0:44  ok: no Chromebook annotated to praman@tjcollins.dev
t+0:45  changed: Fleet console account deleted
t+0:45  == verify praman@tjcollins.dev
t+0:46    suspended: ADMIN
t+0:46    OU: /Offboarded
t+0:48    groups:
t+0:50    transfers completed: Drive and Docs>aengineer@tjcollins.dev Calendar>aengineer@tjcollins.dev
t+0:50    personal devices under management: 0
t+0:51    Fleet host ZQGCYXVWFJ: locked; mapping tj@tjcollins.dev; role labels:
t+0:51    Fleet console account: none
t+0:51  == manual steps
[ ] mail: forward new mail to aengineer@tjcollins.dev with a Gmail routing rule, which has no API: Admin console, Apps, Google Workspace, Gmail, Routing, add a rule for envelope recipient praman@tjcollins.dev (inbound and internal), Modify message, Also deliver to aengineer@tjcollins.dev; the mailbox keeps its copy for retention
[ ] on or after 2026-10-31: workspace/gam/delete.sh praman@tjcollins.dev (it refuses unless suspended, in /Offboarded, with Drive transferred), then remove the routing rule
[ ] when the Mac (vm1-jamf.local, ZQGCYXVWFJ) returns: fleetctl mdm unlock --host ZQGCYXVWFJ shows the PIN; then re-provision it for the next person (runbooks/mac-provisioning-fleet.md)
[ ] Jamf Now has no API: if praman@tjcollins.dev holds a device enrolled there (an iPad), lock it, then wipe or unenroll it in the console (runbooks/ipados-enrollment-jamf.md)
t+0:51  == 0 failed
```

## 3. Forward the mail, in the console

Gmail routing has no API and user-level forwarding would need GAM to act as the user, so this is
the one step of the full form done by hand. Admin console, Apps, Google Workspace, Gmail, Routing,
Routing, Add rule: envelope recipient matches the leaver's address; messages affected: inbound and
internal; action "Modify message", "Also deliver to" the manager. Save; the rule applies within an
hour. "Also deliver to" rather than "Change envelope recipient", so the suspended mailbox keeps
its copy for retention and the manager gets one too. The manager answers senders with context,
which does the work of an auto-reply without the duplicates one would cause. Remove the rule when
the account is deleted. Delegation, which opens the whole mailbox to the manager, is never a
default here; it is an admin-approved, logged exception.

## 4. Devices, after the run

- **Mac.** The lock shows a PIN screen; `fleetctl mdm unlock --host <serial>` prints the PIN when
  the Mac comes back. A returned Mac is re-provisioned for the next person
  (`mac-provisioning-fleet.md`); nothing of the leaver's role follows it, since the label and the
  mapping were removed. A wipe (`fleetctl mdm wipe`) is for a Mac that is not coming back.
- **Chromebook.** `gam update cros <id> action reenable` and `lifecycle/onboard.sh -d <id> ...`
  reassign it; `action deprovision_retiring_device` and `gam issuecommand cros <id> command
  remote_powerwash` retire it.
- **Jamf Now devices.** Lock from the device page, then wipe or unenroll (`ipados-enrollment-jamf.md`).
- **Personal devices** need nothing further: the account wipe removed the work account.

## 5. Delete, after the retention period

```bash
workspace/gam/delete.sh praman
```

Refuses unless the account is suspended, in `/Offboarded`, and has a completed Drive transfer
(`-f` overrides, for a test account that never held anything). Deleting releases the license. The
account can be restored from the Admin console for 20 days, and its address is reserved for that
long. Remove the routing rule from step 3 the same day; mail to a deleted address bounces, which
is the right answer thirty days on.

## 6. Verify

```bash
lifecycle/offboard.sh -m aengineer -y praman
gam info user praman
gam print datatransfers olduser praman status completed
```

The first repeats the run and prints `ok:` on every line with `0 failed`. The second shows the
suspension, the OU, and the note; the third lists both transfers. `lifecycle/lifecycle-report.py`
shows the account suspended and the Mac in IT custody. The Admin console's audit log records the
suspension, the transfers, the group removals, and the move with the actor.

## Related changes

- One step by hand: `workspace/gam/suspend.sh user`, `workspace/gam/transfer-drive.sh user owner`, `gam create datatransfer user calendar owner release_resources`, `gam update group G delete member user`, `gam update user user ou /Offboarded`.
- Leave of absence: `workspace/gam/suspend.sh user`; back: `gam unsuspend user user`.
- A leaver whose mailbox must be kept beyond the retention period: a Vault retention rule, or an archived-user license, before `delete.sh`.
- Mail nobody should receive (no manager, a role that no longer exists): a routing rule that rejects with a custom notice instead of delivering.

## Problems hit

- **Google's hold masks the admin's suspension.** On an account Google placed on hold
  (`WEB_LOGIN_REQUIRED`, see `onboarding.md`), `gam suspend user` succeeds but the reason keeps
  showing Google's. The suspend script therefore suspends whenever the reason is anything but
  `ADMIN`, so an offboarding is always recorded; on a held account a second run repeats the
  harmless deprovision and suspend instead of reporting "already suspended".
- **An empty Drive still exercises the transfer.** The test accounts never signed in, so their
  transfers completed in seconds with nothing to move; the API call, the wait, and the
  completed-transfer check are the same as for a full Drive. The calendar transfer takes the
  `release_resources` keyword, not `releaseresources`.
- **The lock asks.** Locking a Mac is reversible but disruptive, so the script asks before the
  first `fleetctl mdm lock` unless `-y` is given; in a non-interactive run without `-y` it leaves
  the lock on the checklist rather than guessing.
- **The console's `user:` search is wider than the annotation.** `gam print cros query "user:..."`
  also matches recent users of a Chromebook, so the script acts only on devices whose annotated
  user is the leaver.
- **The same search lags a disable.** The first Sales offboarding disabled the Chromebook and, ten
  seconds later, read it back as `ACTIVE` from that query, while `gam info cros` on the device
  already said `DISABLED` (the second run read `DISABLED` from the query too). The query now only
  finds candidate devices; each one is read directly before the script decides or reports.
