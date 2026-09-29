# Jamf Now blueprints

What is configured in the lab's Jamf Now blueprints, where it is set, and why. Values as of 2026-09-28. This is the Apple MDM counterpart of `workspace/tenant-settings.md` and `chromeos/policies.md`: the enrollment runbooks say how a device gets a blueprint, `docs/evidence/` shows it applied, and `docs/design.md` says what changes at scale.

A blueprint in Jamf Now bundles settings, restrictions, and apps. A device belongs to exactly one, picks it at Open Enrollment, and receives every later change to it. The lab uses two, split by role rather than by platform: a blueprint carries iPad and Mac settings side by side, and each device applies only what fits it.

| Blueprint | Devices | Role |
|---|---|---|
| Admin workstation | The MacBook, a physical machine, enrolled permanently | The administrator's daily machine: encrypted and locked, otherwise unrestricted |
| Employee baseline | VM 1, a macOS virtual machine, until its migration to Fleet; the iPad | What every managed employee device gets on day one |
| Default | None | Jamf's empty starter blueprint, kept as the enrollment fallback so a device that fails to pick a blueprint receives nothing rather than the wrong thing |

Admin workstation and Default are marked Private, so the Open Enrollment page offers a user only Employee baseline. The MacBook is enrolled from the console instead (Devices, Enroll This Device, with the administrator signed in on the machine), which is how a blueprint nobody should self-select gets assigned.

## Admin workstation

| Setting | Value | Why |
|---|---|---|
| Require Passcode | On. Complex passcode, alphanumeric, minimum 12 characters with at least one symbol; no maximum age, no history. Screen saver after 10 minutes idle; password required 1 minute after it starts | Twelve characters with a symbol matches the tenant's password policy. A Mac enforces the policy at the next password change, not at enrollment. The two timers add, so the Mac is locked eleven minutes after the last input; each is a ceiling the user can shorten but not extend. |
| Require FileVault | Off | The MacBook was encrypted before enrollment, so its recovery key is one the MDM never saw; escrowing one means rotating the key on the machine the lab must not disturb. Enforcement and escrow are demonstrated on VM 1 under the employee baseline instead. |
| Restrictions | None | A restriction the administrator will turn off is worse than none. Encryption and a locked screen are the controls that matter on this machine. |
| Wi-Fi, apps, custom profiles | None | The machine is already set up; nothing is deployed to it through MDM. |
| Jamf Protect, Jamf Connect, web protection | Off | Add-on products, out of scope. |

## Employee baseline

| Setting | Value | Why |
|---|---|---|
| Require Passcode | On. Complex passcode, minimum 8 characters, letters not required; 10 failed attempts erase the iPad. Screen saver after 10 minutes on a Mac, auto-lock after 5 minutes on the iPad; passcode required 1 minute after either | Eight digits on an iPad and eight characters on a Mac: the Secure Enclave rate-limits guesses and the erase after ten caps them, so length carries the policy without the alphanumeric requirement people resent on a tablet. The timers add; with Touch ID or Face ID in use, iPadOS demands the passcode immediately, which is stricter than the ceiling and stands. |
| Require FileVault | On; recovery keys not shown to end users, and FileVault cannot be turned off by the user | The recovery key is escrowed and readable by an administrator on the device page. On a virtual machine the encryption is not the evidence of a laptop policy, but it is where escrow is shown. |
| Wi-Fi | One network, WPA2/WPA3 Personal, auto-join. The password is typed into the console and appears in no export or evidence | The device joins the office network before anyone signs in: the classic reason to have MDM push Wi-Fi. |
| Force Encrypted Backups (iPad) | On | A local backup of a managed device must not be readable off the device. |
| Reject Untrusted HTTPS Certificates (iPad) | On | No click-through on a bad certificate. |
| Managed App Data Segregation (iPad) | On | Documents from apps deployed by MDM open only in other managed apps: the open-in control that keeps company data out of personal apps. |
| Disable iCloud Desktop & Documents (Mac) | On | Company documents stay off a personal iCloud account. |
| Apps | Slack, the iPad app, free, set to install automatically, deployed without volume purchasing: it installs after the user signs in to the App Store and approves the first install | The one deployed app possible without Apple Business Manager. Nothing can be deployed to a Mac this way: Mac App Store apps need volume purchasing, and an uploaded package must be Developer ID signed. Mac software arrives with `scripts/mac-onboard.sh`. |
| Custom profiles | None | Privacy Preferences (PPPC) and other custom payloads are delivered through Fleet, where they live as code. Jamf Now's custom-profile upload is available and unused. |

## Supervision

iPadOS applies many restrictions only on a supervised device, which takes Automated Device Enrollment through Apple Business Manager or Apple Configurator. The iPad enrolls through Open Enrollment and is unsupervised, so every restriction above was chosen from the ones that work without it. macOS treats a user-approved MDM enrollment as supervised, so a Mac would accept the supervised restrictions too; none are used.

## Not available without Apple Business Manager

Automated Device Enrollment (zero-touch), volume purchasing (Mac App Store apps, paid iPad apps, silent installs), Managed Apple Accounts, and supervision by enrollment. `docs/design.md` covers what each changes at scale. The account stays within Jamf Now's three-device allowance, which is exactly the lab's device count, and a device cap of three is set in the console so a stale record blocks a re-enrollment instead of exceeding it.

## Verifying

On a Mac, `profiles status -type enrollment` confirms MDM enrollment and user approval, `sudo profiles list` shows the delivered profiles, and `fdesetup status` shows FileVault. The device page in Jamf Now shows Security as Applied and the recovery key on the Data Protection card once the Mac has submitted inventory. On the iPad, Settings, General, VPN & Device Management lists the management profile and its restrictions.
