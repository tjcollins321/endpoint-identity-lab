# Runbook: ChromeOS Flex enrollment

**When to use this:** a ChromeOS Flex device, here a virtual machine on the lab's x86 host, is to
be enterprise-enrolled into the Workspace tenant so the console manages it and the lifecycle
scripts can assign it to a person.

**When NOT to use this:** a user signing in to an already-enrolled device (nothing to do; policy
follows the account), or a Chromebook bought with zero-touch enrollment, which enrolls itself.

Inputs:

| Input | Where it comes from | Example |
|---|---|---|
| The Flex image | `dl.google.com/chromeos-flex/images/latest.bin.zip`, a raw disk image | `chromeos_16765.41.0_reven_recovery_stable-channel_RevenMPKeys-v11.bin` |
| A hypervisor with a display the image can drive | QEMU with KVM and `virtio-vga` (see Problems hit for why not VMware) | QEMU 10.2.1 inside WSL2 |
| An enrollment license | the ChromeOS Enterprise Upgrade trial, started in the Admin console | 50 upgrades for 30 days |
| Enrolling credentials | an administrator, or a user allowed to enroll by the enrollment permissions of their OU | the super admin with 2-Step Verification |

---

## 1. The trial

Admin console, Billing, Buy or upgrade, Device and browser security, ChromeOS Enterprise Upgrade,
Start free trial. In this tenant the Start trial button Google's help places on Devices, Chrome,
Devices did not exist; Billing is where it is. Afterwards Billing, Subscriptions shows the trial
with a Trial plan and no payment plan, and the Devices page banner names the end date. Success:
"You can enroll up to 50 devices" on the Devices, Chrome, Devices page.

## 2. The virtual machine

The lab runs Flex under QEMU with KVM inside a WSL2 Ubuntu distribution on the x86 host, the window
shown through WSLg. The definition is one shell script (`run-flex.sh`, kept with the VM, not in
this repository); its essentials:

| Component | Setting | Why |
|---|---|---|
| Machine | q35, host CPU passthrough, 4 vCPU, 8 GB | Flex wants an x86-64 UEFI machine |
| Firmware | OVMF, Secure Boot off, a per-VM copy of the variable store | Flex boots UEFI without Secure Boot |
| Display | `virtio-vga`, GTK window, no GL | the only display driver the image ships for a VM |
| System disk | 32 GiB qcow2 on SATA, port 0 | the install target |
| Installer disk | the image converted with `qemu-img convert -O qcow2`, attached on another SATA port only for the install | the installer auto-selects the largest non-boot disk of 14 GiB or more as its target |
| Network | virtio-net on user-mode NAT | outbound only, which is all enrollment and policy need |
| Input | XHCI with a USB tablet and keyboard | an absolute-position pointer, so the cursor tracks |

Boot the installer, choose Install ChromeOS Flex, let it finish and reboot into the Setup
(out-of-box) flow, and stop at the sign-in screen. Remove the installer disk from the definition.

Set a real identity before the first boot of the installed system: a readable SMBIOS serial, a
UUID, and a distinct MAC address in the QEMU definition. Flex derives its device identifier from
the DMI serial if present, else from the MAC of its first interface, and the console shows that
identifier as the serial number; the identifier is preserved from the first boot on and only a
reinstall changes it. The lab's VM enrolled on QEMU's defaults and shows as
`Flex-52:54:00:12:34:56`, the shared MAC of every QEMU default NIC with a `Flex-` prefix, which
is harmless for one device and a collision waiting to happen for two.

## 3. Enrollment

At the sign-in screen, before any user signs in, press Ctrl+Alt+E (or choose Enterprise
enrollment) and sign in with the enrolling account and its second factor. The device registers,
downloads policy, and returns to a sign-in screen that reads "managed by <domain>". The honest
measure for a VM: if it has not enrolled within an hour, stop and log it; this one enrolled in
minutes with nothing refused. Google's "certified devices" list is about support, not about whether
enrollment works.

Where it lands: the Device enrollment setting of the enrolling user's OU, "Keep ChromeOS device in
current location" by default, puts the device in the root OU. The lifecycle moves it: `onboard.sh`
annotates the device with its user and moves it to `/Devices`, the device OU, when the device is
assigned (`onboarding.md`). Device policy follows that OU; user policy follows the OU of whoever
signs in. That split, device tree versus user tree, is the point of `chromeos/policies.md`.

Success looks like: Admin console, Devices, Chrome, Devices lists the device as Provisioned with
the serial above, the enrolling user, and a policy sync time; from the workstation:

```
gam info cros <device id> fields serialnumber,status,orgunitpath,annotateduser
```

shows `ACTIVE`, the OU, and the annotated user.

## 4. Verify on the device

Sign in as a user, open `chrome://policy`, and Reload policies: the device policies and the user's
OU policies appear with their source and status. `chrome://management` says what the management
can see. Both pages show fetch times, which are cropped from any capture (dates and offsets only).

## 5. The lifecycle, in short

Assign: `lifecycle/onboard.sh -d <device id> sales First Last`. Reassign: `lifecycle/change-role.sh`.
Leave: `lifecycle/offboard.sh` disables the device (`gam update cros <id> action disable`); it shows
the return message until `action reenable`. Retire: `action deprovision_retiring_device`, then
`gam issuecommand cros <id> command remote_powerwash`, which releases the upgrade license and
wipes the device. Day to day the VM is started from a launcher on the host; anything that restarts
WSL stops it.

## Problems hit

- **No VMware display driver in the current image.** VMware Workstation Pro was the plan. The
  guest booted, Chrome could not find a display, the UI crash loop rebooted it once, then the
  screen stayed black. Mounting the image and reading its kernel's driver set showed i915, amdgpu,
  radeon, nouveau, gma500, and a built-in virtio-gpu, and nothing for VMware (`vmwgfx`), Hyper-V,
  or VirtualBox, and no simple framebuffer fallback. No VMware setting changes that. QEMU with
  `virtio-vga` is the hypervisor that works. Older reports that Flex runs under VMware were true of
  older images.
- **The identity fallback.** See step 2: enroll once with a proper serial, or live with a MAC-derived
  identifier forever.
- **Two NATs.** The guest sits behind QEMU's user-mode NAT inside WSL2's own NAT: outbound works,
  nothing on the LAN can reach it, and nothing needs to; a port forward in the definition is the
  answer if that ever changes.
- **The trial lives under Billing**, not on the Devices page, in this tenant.
- **The console prints clock times** on the device list and the device page (enrollment, last
  policy sync, last activity), as does `chrome://policy`; every capture is cropped before it leaves
  the raw folder.
