# Runbook: migrating a Mac from Jamf Now to Fleet

**When to use this:** a Mac enrolled in Jamf Now by user-approved MDM must move to Fleet and
receive the Workstations baseline, with as short a gap in management as the two consoles allow.

**When NOT to use this:** a Mac that was never managed, which is `mac-provisioning-fleet.md`;
a fleet of Macs under an MDM that can push a package, where the old MDM installs fleetd first
and Fleet's own migration workflow moves each device on the user's click; Jamf Now cannot
deploy a package to a Mac, so this runbook does that step by hand.

Inputs, agreed before starting:

| Input | Where it comes from | Example |
|---|---|---|
| The Fleet enrollment link for the fleet | Fleet, Hosts, Add hosts, macOS; it carries the fleet's enroll secret, so it travels over a private channel only. The link is the same for company-owned and personal devices: the page it opens asks | `https://fleet.<domain>/enroll?enroll_secret=...` |
| The Mac's FileVault state and its escrowed key in Jamf Now | The device page in Jamf Now | Enabled, key escrowed |
| An administrator account on the Mac | Needed to approve the new MDM profile | the local admin |

---

## 1. Pre-flight

Read the device page in Jamf Now once more and keep a capture of the inventory: it is the
"before". Confirm the serial number on the device page against the Mac itself, since the
unenroll is sent to whichever device page is open. Note FileVault: if it is on, Jamf Now holds
the escrowed recovery key. Unenrolling keeps the device record and that key; both go only when
the record is removed in step 6, so the old key stays readable until the new escrow is proven.
If the Mac's disk lives on a machine with snapshots, take one now.

## 2. Unenroll from Jamf Now

In the Jamf Now console, open the device page, More, Unenroll device. Jamf sends the Mac a
command that removes its management profile, and with it every profile Jamf delivered: passcode,
restrictions, FileVault settings. FileVault itself stays on, since encryption is a state of the
disk, not a profile.

Success looks like: the device page reads "Unenrolled. Details may be out of date." and offers
Remove from My Devices; on the Mac, System Settings, General, Device Management shows no
management profile, and in Terminal

```bash
profiles status -type enrollment
sudo profiles list
```

report not enrolled and no Jamf profiles. From this moment until step 3 completes the Mac is
unmanaged, which is the window a migration tries to keep short.

If the console command does not reach the Mac, the user can remove the profile on the Mac:
System Settings, General, Device Management, select the profile, remove it with the
administrator password. That is possible only because the enrollment was user-approved rather
than automated, and it is the same fact that makes the migration possible at all.

## 3. Enroll in Fleet by the link

On the Mac, open the enrollment link in Safari. The page asks whether the device is
company-owned or personal; choose company-owned. Download, then System Settings, General, Device
Management, the downloaded enrollment profile, Install, administrator password. This is
user-approved MDM again, the same approval the Mac gave Jamf Now, and it is the Open Enrollment
page of the Fleet side: the profile carries the enroll secret, so nothing is typed and no
package is run. Fleet then installs its own signed build of fleetd through MDM.

Success looks like: `profiles status -type enrollment` reports `MDM enrollment: Yes (User
Approved)` with the Fleet server URL; Fleet Desktop in the menu bar within a few minutes; the
host on the Fleet Hosts page in the Workstations fleet with MDM On (manual). In the lab the
agent checked in ninety seconds after the MDM enrollment, and the Mac was unmanaged for about
eleven minutes between the two consoles.

## 4. What arrives

The fleet-level controls apply at once, since they are not scoped by label: the disk encryption
profile and the OS floor. FileVault is already on, so nothing is asked of the user; what has to
happen is that a recovery key reaches Fleet's escrow, and step 5 checks that it did. The
configuration profiles arrive within a minute when they are released to the whole fleet. When
this Mac enrolled they were still scoped to the canary label, so it carried Fleet's own profiles
and none of the baseline until the label filter was removed in
`fleet/gitops/fleets/workstations.yml` and `gitops.sh` run: the five profiles were acknowledged
within forty seconds of the apply and read Verified after the next refetch. The policies run
from the agent's first check-in, and the Chrome automation installs the browser if it is
missing, as it did here.

## 5. Verify

On the Mac, the same read-back as after provisioning:

```bash
profiles status -type enrollment
sudo profiles list
fdesetup status
```

In Fleet, the host page: fleet Workstations, MDM On, disk encryption with a key available,
policies evaluated, and, after the profiles are released to the fleet, each profile Verified.
Disk encryption reads Verifying for up to an hour after the key arrives, and no refetch or
logout shortens that: the server confirms that it can decrypt a stored key in an hourly job,
and only then marks it Verified. The key is readable on the host page in the meantime.

Then prove the escrow, because a migration that leaves the only recovery key in the old console
fails at the worst moment. Read the key from the Fleet host page and check it on the Mac:

```bash
sudo fdesetup validaterecovery
```

It asks for a recovery key and prints `true` when that key unlocks the disk. The key from Fleet
must return `true`.

## 6. Remove the old record

Only after the Fleet key validates: on the device page in Jamf Now, Remove from My Devices. Until
then the record still shows the old recovery key and the Activation Lock bypass code, to anyone
with console access. Removing it deletes both and frees the device slot.

## Problems hit

- **Unenroll does not remove the device from Jamf Now.** The record stays, marked Unenrolled,
  with its recovery key and bypass code still readable. That is useful as a fallback during the
  migration and a loose end afterward, so removing the record became step 6.
- **The recovery key reached Fleet without the logout Fleet's guide describes.** The guide says
  a Mac migrated with FileVault already on must log out and back in before the key is escrowed.
  On macOS 26.6.2 that did not happen: `/var/db/FileVaultPRK.dat`, the escrow file, was written
  in the same second the disk encryption profile installed, with no prompt and no logout (the
  console session dated from boot, and no authorization plugin had been installed), and Fleet
  showed a key minutes later that differed from the one in Jamf Now. The server log records
  Fleet decrypting that key with its own certificate, so the file was a fresh escrow to Fleet
  and not the one left by Jamf. A logout and login afterward changed nothing: the file kept its
  timestamp. The runbook therefore checks the outcome with `fdesetup validaterecovery` instead
  of relying on either description of the mechanism. Here the key from Fleet returned `true`
  and the key still shown in Jamf Now returned `false`: the recovery key had been rotated, and
  the old console held a dead one.
- **Disk encryption stayed at Verifying while everything else read Verified.** Not a fault: the
  hourly server job described in step 5 had not run yet. It changed at the job's next run, 47
  minutes after the key arrived, with the host page's Last fetched time unchanged, since the
  change is the server's and not new data from the Mac. On the Mac provisioned clean the same
  status took 54 minutes.
- **The enrollment link is one link.** The Add hosts dialog suggested separate company-owned
  and personal links; the page behind the link asks the user instead. In the lab the link was
  copied from the Fleet console in a browser session on the Mac itself, signed out afterward;
  with a real user it is sent to them.
