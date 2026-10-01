# ChromeOS and Chrome policy

What is applied to the Chromebook and to Chrome on the managed Macs, where each setting lives, and
why. Values as of 2026-10-01, read back with `gam show chromepolicies` and confirmed on the devices
at `chrome://policy` (evidence 16 and 20). The counterpart of `workspace/tenant-settings.md` and
`mdm/blueprints.md`; the enrollment procedure is `runbooks/chromeos-enrollment.md`; the reasoning
behind the OU shape is `decisions/role-based-access.md`.

## Three scopes, two trees

Chrome policy reaches a person through three routes, and the Admin console sets them on two
different trees:

| Scope | Set on | Reaches | Shown at `chrome://policy` as |
|---|---|---|---|
| Device | the device's OU, Device settings tab (`/Devices`) | an enrolled Chromebook, whoever signs in | "Device" |
| User | the user's OU, User & browser settings tab | the person's ChromeOS session, and any Chrome profile signed in with the account, on any computer | "Current user" |
| Machine | the OU of the enrollment token, User & browser settings tab | the whole of an enrolled Chrome browser on a Mac or PC, every profile | "Machine" |

The Chromebook has the first two. The Macs managed by Fleet have the third, because the Fleet
profile `chrome-enrollment.mobileconfig` delivers a root-OU enrollment token, plus the second
once a work account signs in. A contractor's own computer has only the second, inside the work
profile. In Active Directory terms: computer-OU policy, user-OU policy, and the enrolled browser
as the domain join that makes machine policy stick.

## Device policy (`/Devices`)

| Setting | Value | Why |
|---|---|---|
| Sign-in restriction | only `*@tjcollins.dev` may sign in | the door: only company identities start a session |
| Guest mode | disabled | no unmanaged session beside the managed ones |
| Powerwash | not allowed | a user cannot wipe the device to escape management |
| Forced re-enrollment | Google default, inherited: re-enroll after a wipe | a wiped device comes back managed. On Flex 131 and later the re-enrollment asks for enrollment credentials at setup rather than happening silently; the device still cannot be used unmanaged |

Google's defaults for an enrolled device are visible in the export and left alone: developer
mode blocked, the stable release channel, device reporting on. The device sits in `/Devices` and
is moved there by `lifecycle/onboard.sh` when it is assigned, since enrollment lands it in the
enrolling user's OU.

## User and browser policy

The root carries the baseline so that every child can only add to it; `/Staff` and
`/Contractors` add what their class of user needs.

| Setting | Root (everyone) | `/Staff` | `/Contractors` |
|---|---|---|---|
| Incognito mode | disabled | inherited | inherited |
| Safe Browsing | standard protection, mandatory, no user override | inherited | inherited |
| Idle | 10 minutes to sleep on power and battery, lock on sleep or lid close | inherited | inherited |
| Restrict sign-in to pattern | `.*@tjcollins\.dev` (machine-only policy: acts on enrolled browsers) | inherited | inherited |
| Sign-in to secondary accounts | allowed Google account domains: `tjcollins.dev` | **block secondary accounts** (the ChromeOS option) | inherited (the allowlist) |
| Download restrictions | | | **block all downloads** |
| External storage devices | | | **disallow** |
| Password manager | | | **disabled** |

**One setting, two options, two OUs.** "Sign-in to secondary accounts" offers either an allowed
domain list, which Chrome on Windows, Mac, Linux, and Android honors (`AllowedDomainsForApps`;
Chrome appends `gserviceaccount.com` to it) but ChromeOS does not, or a block on adding secondary
accounts in a session, which only ChromeOS honors. Staff use company devices: a Mac gets the
allowlist as machine policy from the root through the browser enrollment, and a Chromebook gets
the block from `/Staff`. Contractors use their own computers, where only user policy reaches the
work profile, so `/Contractors` inherits the allowlist instead. Each population is covered by the
layer that actually reaches it; the trade-off is written here so it is not read as drift.

**Standard, not enhanced, Safe Browsing** is a choice: enhanced protection sends more browsing
data to Google. **Blocking all downloads for contractors** is a lab stand-in for the production
control, Context-Aware Access, which allows download and sync only from a verified device.

## What the device does with it

Signed in as the Sales hire, `chrome://policy` on the Flex device lists the device policy and the
`/Staff` user policy; signed in as a contractor, the same device policy and the `/Contractors`
set. On the Mac, Chrome shows the root set at machine scope. A personal Google account cannot be
used on Google services in the managed browser ("this account is not allowed to sign in within
this network") and cannot be added to a Chromebook session. The lifecycle scripts assign the
device (`onboard.sh` annotates it with its user), disable it at offboarding (`offboard.sh`), and
re-enable it for the next person; those are `gam update cros` actions, admin-level, no delegation.

## Named, not set

- A URL blocklist entry for Chrome Remote Desktop on `/Contractors`, considered as the fourth
  contractor restriction; deferred. Remote support connections stay allowed, since an admin's
  remote support to a managed Chromebook is IT's tool.
- Managed profile separation and browser guest mode on the Macs; what a stricter shop turns on.
- Context-Aware Access, the production form of the download rule; not on this edition.

## Verifying

Console: Devices, Chrome, Settings, with the Inheritance filter set to "Locally applied" on each
OU. Workstation: `gam show chromepolicies orgunit /Contractors filter 'chrome.users.*'` and
`... orgunit /Devices filter 'chrome.devices.*'`, which name the OU each value comes from. Device:
`chrome://policy`, Reload policies, then export; the fetch times and the enrollment token are
removed from any capture before it leaves `docs/evidence/raw/`. A Mac shows under Devices,
Chrome, Managed browsers only after Chrome has been launched once, since the token only tells
Chrome where to enroll and Chrome enrolls at its first start.
