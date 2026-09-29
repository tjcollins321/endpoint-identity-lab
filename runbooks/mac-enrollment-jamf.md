# Runbook: macOS enrollment into Jamf Now (user-approved MDM)

**When to use this:** a Mac needs to be managed by Jamf Now: enrolled by a user-approved MDM
profile, placed on a blueprint, and verified. Two paths share the runbook: the administrator
enrolling a Mac from the console while signed in on it (the admin workstation), and a user
enrolling through Open Enrollment (the employee baseline; VM 1 takes this path).

**When NOT to use this:** a Mac that should enroll itself out of the box, which is Automated
Device Enrollment through Apple Business Manager and is not available to the lab; or a Mac that
is moving from Jamf Now to Fleet, which is `mdm-migration-jamf-to-fleet.md`.

Inputs, agreed before starting:

| Input | Where it comes from | Example |
|---|---|---|
| Blueprint | The machine's role; `mdm/blueprints.md` | Admin workstation |
| Open Enrollment access code (user path only) | Set in Jamf Now, Open Enrollment; shared out of band | (six digits) |
| An admin account on the Mac | The profile install asks for it | the local admin |
| Device name | What the console will show; make it unmistakable next to the other devices | TJ's MacBook Pro |

No sign-out of iCloud and no Find My change is needed. Jamf's documentation asks for Find My to
be off so the MDM can capture an Activation Lock bypass code; in this lab the code was captured
with Find My left on.

---

## 1a. Admin path: enroll from the console, on the Mac itself

Sign in to Jamf Now on the Mac being enrolled. Devices, Enroll This Device. Enter the name,
choose the blueprint (a Private blueprint is selectable here, which is the point of this path),
enter the email if asked, Download Configuration Profile.

## 1b. User path: Open Enrollment

The administrator turns Open Enrollment on as in `ipados-enrollment-jamf.md`, section 1. On the Mac,
open the enrollment URL in Safari, enter the access code, pick the blueprint if more than one is
offered, enter the name and email, and download the configuration profile. Jamf recommends
Safari because it hands the profile to the system directly; another browser leaves it in
Downloads, where a double-click does the same thing.

## 2. Install the profile

System Settings, General, Device Management. The downloaded profile is listed; double-click it,
Install, Continue, Continue again at the enrollment notice, Install, then the Mac admin password.

Success looks like: Device Management shows the management profile with the company name, and
the console lists the Mac as Enrolled on the chosen blueprint within a minute.

## 3. Verify

On the Mac:

```bash
profiles status -type enrollment
```

prints `MDM enrollment: Yes (User Approved)` and the MDM server URL. Then:

```bash
sudo profiles list
```

lists the system profiles. Three arrive from Jamf Now on any blueprint:

| Profile identifier | What it is |
|---|---|
| `com.bushel.encrypted-profile-service` | The enrollment and device identity (Bushel was Jamf Now's original name) |
| `com.jamf.servicemanagement.appinstallers` | A Service Management payload that pre-approves Jamf's App Installers helper as a managed background item; delivered whether or not App Installers are used |
| `com.bushel.security.osx` | The blueprint's Security section: password policy and screen-lock ceilings |

A blueprint with restrictions or custom profiles adds one profile per section; the employee
baseline adds `com.bushel.restrictions.osx`. Two of its sections behave differently on a Mac:

- **Wi-Fi** is installed only on a Mac with Wi-Fi hardware. On a virtual machine, which has a
  virtual Ethernet adapter and nothing else, the payload is not installed and the console's Wi-Fi
  tile reads Not applied. The iPad is where that payload is exercised.
- **FileVault** is deferred to the next login: log out, and the login screen asks to turn FileVault
  on. After that, `fdesetup status` prints FileVault is On, and the device page's Data Protection
  tile shows FileVault enabled with a Show recovery key button, which is the escrowed key.

To see a restriction take effect rather than merely install, read the payload back:

```bash
sudo profiles show -type configuration -output stdout-xml | grep -B1 -A1 allowCloudDesktop
```

prints `allowCloudDesktopAndDocuments` as false, the iCloud Desktop and Documents restriction.

In the console, the device page shows Security and Restrictions as Applied after the first
inventory (click Sync to force one). The Details tab shows the model, OS version, FileVault
state, Activation Lock, and Supervised: Yes.

## 4. What supervised means on a Mac

macOS has no separate supervision flag. A user-approved MDM enrollment is treated as supervised
on macOS 11 and later, so every payload and command Jamf Now offers for Macs is available. It
does not make the profile non-removable: the user can remove it in Device Management with the
Mac admin password, and the console can send Unenroll. Only Automated Device Enrollment can pin
the profile in place. That is the honest limit of what a hand-enrolled Mac demonstrates.

## Related changes

- **Move the Mac to another blueprint:** device page, Assign blueprint.
- **Unenroll from the Mac:** System Settings, General, Device Management, select the profile,
  remove it, admin password. The console learns of it at the next check-in.
- **Unenroll from the console:** device page, action menu, Unenroll device.
- **Escrow a FileVault key on a Mac that was encrypted before enrollment:** the blueprint must
  require FileVault; then on the Mac run `sudo fdesetup changerecovery -personal`, which mints a
  new personal recovery key and invalidates the old one, and click Sync on the device page. The
  key appears on the Data Protection tile. Not done on the admin workstation; see
  `mdm/blueprints.md`.

## Problems hit

- **"Recovery key is not escrowed" on the Data Protection tile.** Expected for a Mac encrypted
  before enrollment: the MDM only receives a key generated after its profile arrived. The
  rotation command above resolves it when escrow is wanted.
