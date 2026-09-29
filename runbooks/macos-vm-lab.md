# Runbook: building macOS lab VMs in UTM with distinct device identities

**When to use this:** the lab needs disposable macOS endpoints for enrollment, provisioning, and
deprovisioning cycles without touching a physical Mac. One VM is installed per managed endpoint
from the same restore image; the image is the golden copy, and no VM is cloned (section 6).

**When NOT to use this:** for the workstation or any physical Mac; or for a VM that already
exists and only needs re-enrolling, which is `mac-enrollment-jamf.md` (Jamf Now) or
`mac-provisioning-fleet.md` (Fleet).

Inputs, agreed before starting:

| Input | Where it comes from | Example |
|---|---|---|
| Host | An Apple Silicon Mac on a macOS release at or above the guest's | MacBook Pro M3 Max, macOS 26.7 |
| Restore image | Apple's CDN (`updates.cdn-apple.com`); see section 1 | `UniversalMac_26.6.2_25G83_Restore.ipsw` |
| VM sizing | Enough for Setup Assistant, an MDM agent, and osquery | 8 GB RAM, 4 cores, 64 GB disk |
| Local admin | The only account on the golden image | `labadmin` |
| Target release | The newest release the VM can actually reach; see Problems hit | 26.6.2 |

Apple's license and the Virtualization framework allow two running macOS guests per Mac.

---

## 1. Get the restore image

UTM's "download the latest macOS" option asks Apple for the newest restore image the host
supports. Apple's catalog carries only the current major release, so when the lab standardizes
on the previous one, the image is fetched by hand from Apple's CDN and imported.

Find the image on the ipsw.me index for the `VirtualMac2,1` model (the URL it lists is Apple's
own CDN), download it with resume enabled, and check the size and SHA-1 the index reports:

```bash
curl -L -C - -o ~/Downloads/UniversalMac_26.6.2_25G83_Restore.ipsw "$IPSW_URL"
shasum -a 1 ~/Downloads/UniversalMac_26.6.2_25G83_Restore.ipsw
```

Success looks like: the file size matches the index to the byte and the SHA-1 matches. Keep the
file; every further VM is installed from it.

## 2. Create the VM

UTM, Create a New Virtual Machine, Virtualize, macOS 12+. On the macOS page, Browse to the
restore image instead of letting UTM download one. Hardware: 8192 MB memory, 4 CPU cores.
Storage: 64 GB. Summary: name the VM, leave Open VM Settings unchecked, Save.

Start the VM. The first start installs macOS from the restore image, with a progress bar in the
VM window, then reboots into Setup Assistant.

## 3. Setup Assistant

Country, language, Accessibility (Not Now), Data & Privacy, Migration Assistant (Not Now),
Apple Account (Set Up Later, then Skip), Terms, then the computer account: the local admin from
the inputs table. Location Services off, time zone chosen by hand. Analytics off. Screen Time
(Set Up Later). Siri off. Any automatic-update screen: do not enable automatic installs.

If a FileVault screen appears, leave FileVault off: the golden image stays unencrypted so that
the MDM, not Setup Assistant, turns FileVault on and captures the recovery key on the clone.

## 4. Settle

System Settings, General, Software Update, Automatic Updates: turn off "Download new updates
when available" and "Install macOS updates" so the clones stay on the lab's release and stop
staging updates they cannot apply; leave security responses on. Do not run a macOS point update
inside the VM until the hang in Problems hit is fixed upstream. When a point update is offered
alongside a newer major release, the point release sits under Also available; never take the
major upgrade.

## 5. Verify

There is no shared clipboard for macOS guests in UTM, so results leave the VM as a screenshot
or through a shared folder. In Terminal on the VM:

```bash
sw_vers
system_profiler SPHardwareDataType | grep -E 'Model|Serial|Provisioning'
```

Success looks like: `ProductVersion` is the target release; `Model Identifier` is
`VirtualMac2,1`; the serial differs from every other VM's. Then System Settings, General, About,
Name: give the Mac the name the consoles should show. Shut the VM down from the Apple menu.

## 6. More VMs: install, do not clone

UTM's Clone command copies the VM's Apple machine identifier unchanged, and the guest derives its
serial number from that identifier. A clone therefore reports the same serial as its source, and
an MDM treats the two as one device. Each managed VM is installed from the restore image
instead, repeating sections 2 to 5; every install generates its own identifier.

To confirm two VMs are distinct before either boots, compare the identifier in each bundle's
`config.plist` (the folder is under UTM's container, `Library/Containers/com.utmapp.UTM/Data/Documents`):

```bash
plutil -p ~/Library/Containers/com.utmapp.UTM/Data/Documents/<vm>.utm/config.plist | grep -A 1 MachineIdentifier
```

Success looks like: a different blob per VM; the serials printed inside each guest then differ
as well. The hardware model blob is the same for every VM, which is expected.

Copy and paste between host and guest needs UTM's guest tools inside the VM: with the VM running,
the CD icon in its toolbar, Install Guest Tools, then the package on the mounted drive. It works
when host and guest are both on macOS 15 or later.

## Problems hit

- **Clones share a serial number.** The first design built one golden VM and cloned it per
  endpoint. UTM's clone code regenerates the UUID and, optionally, MAC addresses, but not the
  machine identifier, so the clone would have enrolled as the same device. The golden VM was
  renamed and used as the first endpoint, and the second was installed from the image.

- **A macOS point update inside the VM hangs on a black screen.** Software Update from 26.6.2 to
  26.7.1 rebooted into a black window and never finished: the virtual CPUs stayed busy, but the
  disk image was not written for over twenty minutes and no network traffic moved. Reports from
  September 2026 show the same hang from any 26.x to 26.7 under Parallels, UTM, VirtualBuddy,
  and VMTek, so it sits in Apple's virtualization layer; no workaround was known at the time.
  Recovery: force stop from UTM, and the guest boots the previous release with nothing applied.
  Consequence: the VMs stay on the newest release a restore image exists for, and a policy that
  sets an OS floor uses that release.
- **Apple's catalog only serves the current major release.** UTM's automatic download would have
  produced a macOS 27 guest on a macOS 26 host: a guest newer than the framework installing it,
  and a version the lab had decided not to move to yet. No restore image exists for the exact
  point release the lab runs, so the newest previous-major image was fetched by hand and the
  point release applied inside the VM.
