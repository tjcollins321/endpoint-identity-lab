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
through SAML to the Fleet console. The mailbox and everything in it are retained, and Google
blocks new mail to a suspended account from that moment (until the address map of step 3 is in
place, a sender gets a bounce); Drive, Calendar, groups, and devices are untouched. Nothing is lost. The checklist says how to finish. A real run of this
form, then the full form, is `docs/evidence/17-lifecycle-offboard-emergency-then-full.txt`.

## 2. Full form

```bash
lifecycle/offboard.sh -m aengineer -y praman
```

What it does, in order (a failed suspend stops the run; anything after it continues and is reported):

1. **Cut access**, as above, or `ok` if already suspended by an administrator.
2. **Data to someone who stays.** Drive ownership, private and shared files, then the calendars
   with room bookings released, both through the Data Transfer API, the same mechanism as the
   Admin console's Transfer ownership button, under the admin's own authorization. A completed
   transfer between the same two accounts is reported, not repeated. Mail is not transferred:
   what the mailbox already holds stays in it and in Vault. Google stops delivering new mail to a
   suspended account, so new mail is redirected to the manager by a recipient address map, a
   console step (step 3) because Gmail routing has no API.
3. **Access removed.** Every group membership, read directly and removed one by one.
4. **The leavers' OU.** The account moves to `/Offboarded`, the Disabled Users OU of this tenant:
   reports exclude it, a mistaken unsuspend grants nothing, and the account note records the date
   and the earliest deletion date, thirty days on.
5. **Personal devices.** Any phone or tablet under Workspace mobile management gets an account
   wipe: the work account and its data leave the device, nothing personal is touched.
6. **Company devices.** A Fleet-managed Mac found by its mapping is locked (at a terminal the
   script asks first, `-y` answers yes, and an unattended run without `-y` leaves the lock on the
   checklist), removed from its role label, and mapped back to the admin, which is IT custody. A
   virtual Mac is never locked: it cannot draw the PIN screen, so the lock could not be undone. A Chromebook annotated to the person is disabled, which shows the
   return message on its screen until re-enabled. Jamf Now has no API, so an iPad or a Mac enrolled
   there is a console step on the checklist.
7. **Application accounts identity does not remove.** The Fleet console account that just-in-time
   provisioning created is deleted through the API.
8. **Read-back,** then the checklist.

Success looks like (the Marketing hire's offboarding, section 6 of
`docs/evidence/17-lifecycle-one-hire-arc.txt`, offsets from the start of the run, GAM's own output
left out; her Mac had been locked from the Fleet console minutes earlier, so the run reports it
locked instead of sending the lock, see Problems hit):

```
t+0:00  == offboarding shaddad@tjcollins.dev (marketing)
t+0:02  deprovisioning shaddad@tjcollins.dev: app passwords, backup codes, OAuth tokens, sign-out
t+0:04  suspending shaddad@tjcollins.dev
User: shaddad@tjcollins.dev, Suspended
t+0:11  changed: access cut: shaddad@tjcollins.dev suspended
t+0:29  changed: Drive transferred to aengineer@tjcollins.dev
t+0:38  changed: Calendar transferred to aengineer@tjcollins.dev
t+0:41  changed: removed from all-staff@tjcollins.dev
t+0:42  changed: removed from marketing@tjcollins.dev
t+0:44  changed: moved to /Offboarded; delete on or after 2026-11-03
t+0:46  ok: no personal devices under Workspace mobile management
t+0:46  ok: vm1-jamf.local (ZQGCYXVWFJ) is locked
t+0:46  changed: vm1-jamf.local removed from role-marketing
t+0:47  changed: vm1-jamf.local mapped to tj@tjcollins.dev
t+0:47  ok: no Chromebook annotated to shaddad@tjcollins.dev
t+0:48  changed: Fleet console account deleted
t+0:48  == verify shaddad@tjcollins.dev
t+0:49    suspended: ADMIN
t+0:49    OU: /Offboarded
t+0:51    groups:
t+0:53    transfers completed: Drive and Docs>aengineer@tjcollins.dev Calendar>aengineer@tjcollins.dev
t+0:54    personal devices under management: 0
t+0:54    Fleet host ZQGCYXVWFJ: locked; mapping tj@tjcollins.dev; role labels:
t+0:55    Fleet console account: none
t+0:55  == manual steps
[ ] mail: forward new mail to aengineer@tjcollins.dev with a Gmail routing rule, which has no API: Admin console, Apps, Google Workspace, Gmail, Routing, add a rule for envelope recipient shaddad@tjcollins.dev (inbound and internal), Modify message, Also deliver to aengineer@tjcollins.dev; the mailbox keeps its copy for retention
[ ] on or after 2026-11-03: workspace/gam/delete.sh shaddad@tjcollins.dev (it refuses before that date, and unless suspended, in /Offboarded, with Drive transferred), then remove the routing rule
[ ] when the Mac (vm1-jamf.local, ZQGCYXVWFJ) returns: fleetctl mdm unlock --host ZQGCYXVWFJ shows the PIN; then re-provision it for the next person (runbooks/mac-provisioning-fleet.md)
[ ] Jamf Now has no API: if shaddad@tjcollins.dev holds a device enrolled there (an iPad), lock it, then wipe or unenroll it in the console (runbooks/ipados-enrollment-jamf.md)
t+0:55  == 0 failed
```

The mail line of this checklist has since been reworded for the setting step 3 now describes.

## 3. Redirect the mail, in the console

Gmail routing has no API and forwarding set on the mailbox would need GAM to act as the user, so
this is the one step of the full form done by hand. It matters the same day: from the moment of
suspension, Google no longer delivers new mail to the account. One recipient address map holds
every leaver, a row each.

1. Admin console, Apps, Google Workspace, Gmail, Routing, with the top organizational unit
   selected. Scroll to **Email forwarding using recipient address map**.
2. The first time, **Configure** (or **Add another rule**) and give the rule a description. After
   that, **Edit** the same rule: every leaver is a row in it, and **Bulk add** takes a list.
3. Under "To forward emails, map original recipient to new recipient", **Add**: Address is the
   leaver's address, Map to address is the manager's.
4. Messages to affect: **All incoming messages**, so that internal senders are covered too.
5. Routing options: leave "Also route to original destination" off. The lab tested it on and
   off with the same result (below): with the map in place the delivery to the suspended mailbox
   is dropped either way, so there is nothing to route there. "Add X-Gm-Original-To header" was off.
6. **Save.** The console says most changes take effect in a few minutes; this one did.
7. Verify: send a message to the leaver's address from another account, then Reporting, Email Log
   Search, by recipient. The leaver's line reads Dropped with the address map as the matched rule,
   the manager's line shows the delivery, and the sender gets no bounce.

Tested twice on 2026-10-04 with messages from outside the tenant, the offboarded hire's address
mapped to the administrator's mailbox standing in for the manager's, first with the original
destination also routed and then without, with the same result both times:
`docs/evidence/24-offboard-mail-address-map.png` shows the second. What the tests settled: new
mail after the suspension exists only in the mailbox it is mapped to, not in the leaver's, and
nobody is told the address is gone. A third test the same day, with the map switched off, settled
the other half: the sender received a bounce saying the address does not exist
(`docs/evidence/25-offboard-mail-bounce-without-map.png`). The map is what keeps a leaver's
address from reading as dead from the first day. The manager answers senders with context, which does the work of an auto-reply
without the duplicates one would cause. Remove the leaver's row when the account is deleted.
Delegation, which opens the whole mailbox to the manager, is never a default here; it is an
admin-approved, logged exception.

## 4. Devices, after the run

- **Mac.** The lock shows a PIN screen on a physical Mac; `fleetctl mdm unlock --host <serial>`
  prints the PIN when the Mac comes back. The lab could not show the unlock: its Fleet-managed Macs
  are virtual, and a locked virtual Mac stays dark (Problems hit). A returned Mac is re-provisioned for the next person
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

Refuses unless the account is suspended, in `/Offboarded`, has a completed Drive transfer, and
has reached the deletion date in its note (`-f` overrides, for a test account that never held
anything). Deleting releases the license. The
account can be restored from the Admin console for 20 days, and its address is reserved for that
long. Remove the leaver's row from the address map of step 3 the same day; mail to a deleted address bounces, which
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
- Leave of absence: `workspace/gam/suspend.sh user`; back: `gam unsuspend user user`. Google delivers no new mail to the account while it is suspended, so map the address to a colleague (step 3) for the duration if that mail must not be lost.
- A leaver whose mailbox must be kept beyond the retention period: a Vault retention rule, or an archived-user license, before `delete.sh`.
- Mail nobody should receive (no manager, a role that no longer exists): a routing rule that rejects with a custom notice instead of delivering.

## Problems hit

- **Google's hold masks the admin's suspension.** On an account Google placed on hold
  (`WEB_LOGIN_REQUIRED`, see `onboarding.md`), `gam suspend user` succeeds but the reason keeps
  showing Google's. The suspend script therefore suspends whenever the reason is anything but
  `ADMIN`, so an offboarding is always recorded; on a held account a second run repeats the
  harmless deprovision and suspend instead of reporting "already suspended".
- **A failed read looked like nothing to do.** The lookups threw away the tool's exit status, so
  the scripts could not tell "none" from "could not ask". With Fleet unreachable, an offboarding
  printed `ok: no Fleet-managed Mac mapped` and `ok: no Fleet console account` and ended with 0
  failed; a failed group, phone, or Chromebook listing read the same way, and a failed account
  read was reported as "does not exist". Found by reading every script for the pattern after the
  access audit turned one empty read into four findings (`role-change.md`). One cause was
  measured that day: Google's Data Transfer API answered two of twenty identical, valid requests
  with `400 invalidArgument`, which GAM does not retry; the failed account reads were not caught
  in the act. Reads are now retried, the
  lookups return failure when the read failed, and `offboard.sh` and `change-role.sh` print
  `FAIL: could not read ...` and end non-zero, so a rerun finishes the job. Tested by injecting
  the failures: Fleet unreachable, each listing failing, the account read failing once and always.
  Not changed: a read-back line can still print a blank for a single field it could not read.
  The account-to-device report, which showed a blank row for an account it could not read, was
  closed later with the audit's listing (`role-change.md`).
- **The mail step was written before it was run.** Step 3 first described a routing rule with
  "Also deliver to" and said the suspended mailbox would keep its own copy of new mail, and step 1
  said mail kept arriving after suspension. Neither had been tried. Run for the first time on
  2026-10-04, with the recipient address map, which is the setting made for this: the message is
  delivered to the mapped address and the delivery to the suspended mailbox is dropped, whether
  or not the original destination is also routed, and the sender sees nothing. The first write-up
  took that for Google's default ("dropped without a bounce"). A control test with the map off
  showed the sender gets a bounce, so the silence was the map's doing; corrected. The
  steps, the checklist line the script prints, and the help article now say what happens. The
  checklist lines in transcripts captured before the step was first run keep the old wording.
- **A suspension can read back late.** On one emergency run the check one second after the suspend
  call printed `Account Suspended: False`; Google stamped the suspension a second after that, and
  the script's next read, the one it decides on, saw it. The account was suspended throughout the
  rest of the run, but a slower read would have stopped it with a false failure. The verify now
  retries for about twenty seconds before it prints or decides, as the group verify does.
- **An empty Drive still exercises the transfer.** The test accounts never signed in, so their
  transfers completed in seconds with nothing to move; the API call, the wait, and the
  completed-transfer check are the same as for a full Drive. The calendar transfer takes the
  `release_resources` keyword, not `releaseresources`.
- **The lock asks.** Locking a Mac is reversible but disruptive, so the script asks before the
  first `fleetctl mdm lock` unless `-y` is given; in a non-interactive run without `-y` it leaves
  the lock on the checklist rather than guessing.
- **The lock prompt never appeared.** The first offboarding of someone holding a Mac, run at a
  terminal without `-y`, printed no prompt and left the lock on the checklist: the loop over the
  person's Macs read its rows on standard input, so inside it the script saw no terminal and took
  the unattended branch. The outcome was the safe one, by the wrong path. The loop now reads its
  rows on a separate descriptor, and the checklist line no longer says to rerun with `-y`, which
  cannot work once the run has returned the Mac to IT custody: the lock is sent by hand.
- **The console's `user:` search is wider than the annotation.** `gam print cros query "user:..."`
  also matches recent users of a Chromebook, so the script acts only on devices whose annotated
  user is the leaver.
- **A lock is one-way on a virtual Mac.** The first lock, sent from the Fleet console to a virtual
  Mac (`VirtualMac2,1` under UTM), was acknowledged within half a minute and Fleet showed the host
  Locked and offline. The virtual machine then showed only a black window, on a normal start and
  on a start in recovery mode, and entering the PIN blind did nothing: the PIN screen runs from
  recovery and this virtual hardware never draws it. No copy of the VM had been taken first, so
  that Mac stays locked until it is rebuilt (`macos-vm-lab.md`, `mac-provisioning-fleet.md`). The
  script now reads the hardware model from Fleet and never locks a virtual Mac, with or without
  `-y`; it says so and puts the VM on the checklist. Because that lock came from the console, the
  script's own prompt and send were exercised separately, at a terminal with the Fleet API and
  `fleetctl` replaced by stubs: answering yes issues `fleetctl mdm lock`, answering no does not.
  The unlock by PIN has not been shown; it needs a physical Mac.
- **The same search lags a disable.** The first Sales offboarding disabled the Chromebook and, ten
  seconds later, read it back as `ACTIVE` from that query, while `gam info cros` on the device
  already said `DISABLED` (the second run read `DISABLED` from the query too). The query now only
  finds candidate devices; each one is read directly before the script decides or reports.
