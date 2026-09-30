# Device baselines: Jamf Now blueprints and the Fleet Workstations fleet

What is configured in the lab's Jamf Now blueprints and in its Fleet fleet, where it is set, and why. Jamf values as of 2026-09-28, Fleet values as of 2026-09-29. This is the Apple MDM counterpart of `workspace/tenant-settings.md` and `chromeos/policies.md`: the enrollment runbooks say how a device gets a blueprint, `docs/evidence/` shows it applied, and `docs/design.md` says what changes at scale.

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

## Fleet: the Workstations fleet

Fleet's counterpart of the Employee baseline blueprint, held as files under `fleet/gitops/` and applied by `fleetctl gitops` (`fleet/gitops/README.md` maps the files; `runbooks/fleet-setup.md` says how to run it). A Mac joins the fleet through the enroll secret in its fleetd package, the way a device picks a blueprint at Open Enrollment, and receives every later change to the files. The profiles reproduce the Employee baseline where a Mac is concerned; each `.mobileconfig` carries its own description.

| Profile | Payload | Value | Why |
|---|---|---|---|
| Passcode policy | `com.apple.mobiledevice.passwordpolicy` | Minimum 8 characters, letters not required, simple sequences not allowed; screen saver after 10 minutes idle, password required 1 minute after it starts or the display sleeps; 10 failed attempts lock the account for 15 minutes | The same numbers as the Jamf Now Employee baseline. On a Mac the passcode payload also carries the screen-saver timers, so one payload covers what Jamf shows as two settings. A Mac is not erased by failed attempts; the tenth locks the account instead. |
| Restrictions | `com.apple.applicationaccess` | iCloud Desktop & Documents off | As in Jamf: company documents stay off a personal iCloud account. |
| Login window | `com.apple.MCX`, `com.apple.loginwindow` | Guest account off; automatic login off | Every session is an identified user with a password. Not in the Jamf blueprint; the baseline's third item, and one osquery can confirm from the `managed_policies` table. |
| Full disk access for fleetd | `com.apple.TCC.configuration-profile-policy` (PPPC) | Full Disk Access for fleetd's `orbit` binary, matched by code-signing requirement | The canonical PPPC case: osquery reads protected paths only with Full Disk Access, and a PPPC grant is honoured only when MDM delivers it. Fleet's published profile, used verbatim. |
| Google Chrome enrollment | `com.google.Chrome` | Enrollment token from a Fleet custom variable; cloud reporting on | Enrolls the browser in Chrome Enterprise Core, so it receives the Workspace tenant's browser policy for its organizational unit and reports to the Admin console: the Fleet side meeting the Workspace side. The token never appears in the repository. |

Not delivered through Fleet: Wi-Fi, because the Fleet-managed Macs are virtual machines without Wi-Fi hardware and macOS installs no Wi-Fi payload on such a machine (a redacted copy of the Jamf payload is `mdm/profiles/wifi-redacted.mobileconfig`); apps, since Mac software arrives with `scripts/mac-onboard.sh`. FileVault is a fleet-level control in Fleet, enforcement with key escrow, rather than a profile; it is described below.

**Controls and policies.** Two fleet-level controls enforce what a profile cannot: FileVault on, with the recovery key escrowed in Fleet and readable by an administrator on the host's page (the Jamf blueprint's Require FileVault), and a macOS floor of 26.6.2 with a deadline, after which Fleet forces the update. Three osquery policies read the state back independently, per host, pass or fail: FileVault enabled, macOS at or above the floor, and Google Chrome installed. The last has an install script attached that Fleet runs on a host that fails it, so a missing browser repairs itself; the script is idempotent and does nothing on a Mac where Chrome is present and intact. Chrome is the required app because the enrollment profile above is inert without it. Every profile was first scoped to a `canary` label, one host by hardware serial, and proven there; removing the label filter released it to the whole fleet, and a changed profile goes the same way.

## Verifying

On a Mac, `profiles status -type enrollment` confirms MDM enrollment and user approval, `sudo profiles list` shows the delivered profiles, and `fdesetup status` shows FileVault. The device page in Jamf Now shows Security as Applied and the recovery key on the Data Protection card once the Mac has submitted inventory. On the iPad, Settings, General, VPN & Device Management lists the management profile and its restrictions. On a Fleet-managed Mac the same `profiles` commands apply, and the host's page in Fleet lists each profile with its delivery status.
