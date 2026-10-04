# Runbook: provisioning a Mac into Fleet (clean install to baseline applied)

**When to use this:** a Mac that has never been managed, or has been wiped, needs to be brought
under Fleet and receive the Workstations baseline before it goes to an employee. Done at the
machine by an administrator; the employee's first login happens afterward.

Nothing here binds the Mac to the directory, so the employee's account on it is a local one,
created at handover (System Settings, Users & Groups; an administrator only where the role needs
it, as `scripts/mac-onboard.sh engineer` does for Homebrew). The lab's virtual machines keep the
single administrator account from the golden image, which stands in for the person. With Automated
Device Enrollment the person would create the account during Setup Assistant, named from the
identity provider sign-in, and the MDM would add and rotate a separate administrator account.

**When NOT to use this:** a Mac already enrolled in another MDM, which is
`mdm-migration-jamf-to-fleet.md`; a Mac bought through Apple Business Manager, which would enroll
itself during Setup Assistant with the same package as its bootstrap package, a flow this lab
cannot exercise without ABM.

Inputs, agreed before starting:

| Input | Where it comes from | Example |
|---|---|---|
| The fleetd package | Built by `fleet-setup.md` section 7 for the Workstations fleet; carries the server URL and the fleet's enroll secret | `~/fleet-pkg/fleet-osquery.pkg` |
| An administrator account on the Mac | Created at first boot; the package and the MDM approval both need it | the local admin |
| The host's identity in Fleet | Its hardware serial; the canary label matches one serial | `system_profiler SPHardwareDataType` |

In this lab the Mac is a virtual machine in UTM on the admin workstation (`macos-vm-lab.md`),
and the package reaches it through a shared folder.

---

## 1. Get the package onto the Mac

Any route that does not publish the file works, since it carries the enroll secret. For the VM:
in UTM, with the VM shut down, edit it, Sharing, directory share mode VirtioFS, and choose the
folder holding the package. Boot the VM. macOS mounts the share at `/Volumes/My Shared Files`.

Success looks like: `ls "/Volumes/My Shared Files"` in the VM lists `fleet-osquery.pkg`.

If the share does not appear, serve the folder from the workstation for the minute it takes:
`python3 -m http.server 8000` in that folder, then in the VM
`curl -O http://<workstation address>:8000/fleet-osquery.pkg`. The transfer stays on the
machine, since the VM's traffic to the host never leaves it.

## 2. Install fleetd

The package is unsigned, so Gatekeeper refuses a double-click; the command-line installer does
not consult Gatekeeper for packages:

```bash
sudo installer -pkg "/Volumes/My Shared Files/fleet-osquery.pkg" -target /
```

Success looks like: `installer: The install was successful.`; within a minute the Fleet Desktop
icon appears in the menu bar, and on the Fleet Hosts page the Mac is listed under the
Workstations fleet with its serial, its status Online, and MDM Off. The agent is enrolled; the
device is not yet.

What the installer put down, for the reader who wants to know: `/opt/orbit` (orbit, osqueryd,
Fleet Desktop), a launch daemon `com.fleetdm.orbit` that runs as root at boot, and a root-only
file with the enroll secret, which is used once and then replaced by the host's own node key.

## 3. Turn on MDM

Fleet Desktop menu, My device. The browser opens the host's own page in Fleet with a banner
offering to turn on MDM; it downloads the enrollment profile. Install it in System Settings,
General, Device Management, and approve with the administrator password. This is user-approved
MDM enrollment, the same approval a Mac gives Jamf Now, and it is what makes configuration
profiles, disk-encryption enforcement, and the OS floor possible.

Success looks like: System Settings shows the Fleet management profile as installed and
approved; the host page in Fleet shows MDM On (manual); `profiles status -type enrollment` in
Terminal reports enrolled and user approved.

## 4. What arrives, and in what order

The Mac now receives what the Workstations fleet says (`fleet/gitops/fleets/workstations.yml`):

- The configuration profiles, delivered by MDM within minutes; on the host page each shows
  Verifying, then Verified. On the first Mac through this runbook each was still scoped to the
  `canary` label and arrived because that Mac is the canary; they have since been released to
  the whole fleet, so a Mac provisioned now receives them without the label.
- Disk encryption: Fleet Desktop asks the user to log out so FileVault turns on; at the next
  login the recovery key is escrowed and appears on the host page for an administrator.
- The policies, evaluated by the agent from its first check-in, which is before MDM is on:
  FileVault fails until the logout, macOS at or above the floor passes, Google Chrome installed
  fails on a clean Mac, which runs the install script as its automation; the next run passes.
  On the first Mac through this runbook the script ran 37 seconds before MDM enrollment
  completed, because policies come from the agent and MDM is the later step.
- The Chrome enrollment profile does its work the first time Chrome opens: the browser enrolls in
  Chrome Enterprise Core and appears in the Workspace Admin console under Devices, Chrome.

## 5. Verify on the Mac and in Fleet

On the Mac:

```bash
profiles status -type enrollment
sudo profiles list
fdesetup status
ls "/Applications/Google Chrome.app"
```

In Fleet, the host page: fleet Workstations, MDM On, each profile Verified, the three policies
passing, the FileVault key present under Disk encryption, the script's run in the activity feed
with exit code 0.

## Problems hit

First run, a macOS 26.6.2 virtual machine, 2026-09-30: none that blocked. Two things to know.
The device's own page in the browser (Fleet Desktop, My device) lags: it showed MDM off and two
failing policies for a minute after both had changed, until Refetch. And the order of events is
not the order of the sections: the agent enrolls and runs policies at once, so the Chrome
automation had installed the browser before MDM enrollment completed, and the profiles then
verified within a minute of it. Fleet also installs three profiles of its own next to the
baseline, `Fleetd configuration`, `Fleet root certificate authority (CA)`, and `Disk encryption`;
they are Fleet's, not the repository's, and they belong there. `Disk encryption` read Verifying
for 54 minutes after the key arrived, until the server's hourly check of stored keys had run.
- **The browser enrolls at first launch, not at install.** The Chrome enrollment profile only
  delivers the token; Chrome reads it and enrolls with Chrome Enterprise Core the first time it
  starts. A Mac whose Chrome was installed by the policy script and never opened is fully
  provisioned in Fleet and absent from Devices, Chrome, Managed browsers until someone launches
  Chrome once. Found 2026-10-01 on the second VM; the first had been opened during its migration.
