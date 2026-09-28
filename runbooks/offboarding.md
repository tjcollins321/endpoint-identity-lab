# Runbook: offboarding

**When to use this:** an employee or contractor leaves, or access has to end now while the
paperwork catches up. Step 1 alone is the emergency form; the rest can follow.

**When NOT to use this:** a leave of absence (step 1 only, nothing transferred or deleted) or a
name change (an alias, not a new account).

The order is the point: cut access first while every byte of data stays where it is, move the
data to someone who stays, deal with the devices, and delete last. The delete script refuses to
run before steps 1 and 2 have happened.

The Workspace steps run from the admin workstation with the scripts in `workspace/gam/`
(setup: `gam-setup.md`). Every script can be re-run; a second run reports and changes nothing.

---

## 1. Cut access

```bash
workspace/gam/suspend.sh dokafor
```

What it does, in this order: deletes the account's app passwords, backup verification codes,
and OAuth tokens (so nothing that was authorized keeps working), signs out every session, then
suspends the account. Deprovisioning comes first because Google refuses the backup-code step on
an account that is already suspended.

After this the person cannot sign in from anywhere. Mail keeps arriving and is retained, Drive
and Calendar are untouched, and group memberships remain but grant nothing. Nothing is lost.

Success looks like:

```
User: dokafor@tjcollins.dev, Signed Out
User: dokafor@tjcollins.dev, Deprovisioned
User: dokafor@tjcollins.dev, Suspended
User: dokafor@tjcollins.dev, Account Suspended: True, Suspension Reason: ADMIN
```

## 2. Transfer Drive ownership

```bash
workspace/gam/transfer-drive.sh dokafor aengineer
```

What it does: asks the Data Transfer API to move ownership of the leaver's Drive files, private
and shared, to the named account, and waits for completion. This is the same mechanism as the
Admin console's Transfer ownership button and runs under the admin's authorization, so it
needs no access to the leaver's account. A completed transfer between the same two accounts is
reported rather than repeated.

Calendar events can go the same way when a leaver owned shared calendars or room bookings:
`gam create datatransfer dokafor calendar aengineer releaseresources`. Mail is not transferred;
if the mailbox must be kept, set a retention rule in Vault or delegate the mailbox before step 4.

Success looks like a transfer row with `completed` in both status columns.

## 3. Devices

Written with the device phases: remote lock, wipe, and unenrollment in Jamf Now; the Fleet
host; the ChromeOS device. A company-owned device is wiped or reassigned; a personal device
has the work account removed.

## 4. Delete the account

```bash
workspace/gam/delete.sh dokafor
```

What it does: refuses unless the account is suspended and a completed Drive transfer from it
exists (`-f` overrides both, for a test account that never held anything), deletes the account,
and confirms it is gone. Deleting releases the license. The account can be restored from the
Admin console for 20 days, and its address is reserved for that long.

Success looks like:

```
User: dokafor@tjcollins.dev, Deleted
User: dokafor@tjcollins.dev, Does not exist
```

## 5. Verify

```bash
gam info user dokafor
gam print datatransfers olduser dokafor status completed
```

The first answers `Does not exist`; the second lists the transfer. The Admin console's audit
log records the suspension, the transfer, and the deletion with the actor and time.
`docs/evidence/05-workspace-gam-lifecycle-run.txt` is a complete run.

## Problems hit

- **Google's hold masks the admin's suspension.** On an account Google placed on hold
  (`WEB_LOGIN_REQUIRED`, see `onboarding.md`), `gam suspend user` succeeds but the reason keeps
  showing Google's. The suspend script therefore suspends whenever the reason is anything but
  `ADMIN`, so an offboarding is always recorded; on a held account a second run repeats the
  harmless deprovision and suspend instead of reporting "already suspended". On an account that
  has signed in at least once, the reason reads `ADMIN` and the second run is a no-op.
- **An empty Drive still exercises the transfer.** The test accounts never signed in, so their
  transfers completed in seconds with nothing to move; the API call, the wait, and the
  completed-transfer check are the same as for a full Drive.
