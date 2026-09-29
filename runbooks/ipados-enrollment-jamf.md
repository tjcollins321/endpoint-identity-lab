# Runbook: iPadOS enrollment (Jamf Now)

**When to use this:** a company-owned iPad needs to be managed: enrolled in Jamf Now, placed on
the employee baseline blueprint, and verified. The iPhone flow is identical, same enrollment page
and same profile install path; the lab does not enroll an iPhone.

**When NOT to use this:** a device that has to be supervised, which is decided at setup time by
Automated Device Enrollment or Apple Configurator and cannot be added later (see the Supervision
section of `mdm/blueprints.md`); or a personal device under a BYOD program, which calls for User
Enrollment with a Managed Apple Account, something Jamf Now does not offer.

Inputs, agreed before starting:

| Input | Where it comes from | Example |
|---|---|---|
| Open Enrollment access code | Set by the admin in Jamf Now, Open Enrollment; shared out of band, never written down here | (six digits) |
| Blueprint | The device's role; `mdm/blueprints.md` | Employee baseline |
| Name and email on the device record | The user the device is issued to | Dana Okafor |
| The iPad | iPadOS 16.4 or later, on Wi-Fi, signed in to the App Store if an app is deployed | iPad Pro |

Supervision is not needed for anything in the employee baseline; every setting in it works on an
unsupervised device.

---

## 1. Turn on Open Enrollment (admin, in the console)

Open Enrollment, tick Enable Open Enrollment, set the access code, choose how long the window stays
open, Save Settings. The enrollment URL and a QR code appear at the bottom of the page.

Why a window: Open Enrollment is a self-service door. It closes by itself after the period, and it
refuses new devices once the account's device cap is reached, so a forgotten window cannot enroll a
stray device. Blueprints marked Private do not appear on the enrollment page; the user only sees
the blueprints meant for self-enrollment, and with exactly one visible blueprint the choice is
skipped altogether.

Success looks like: the page shows the link and the QR code, and the Devices page banner shows
how many devices the account can still take.

## 2. Enroll from the iPad (the user)

1. Open the Camera and scan the QR code, or type the enrollment URL into Safari.
2. Enter the access code, pick the blueprint if asked, and enter the name and email.
3. Tap Start Enrollment, then Allow when Safari asks to download a configuration profile.
4. Settings, General, VPN & Device Management, tap the downloaded profile, Install. Enter the device
   passcode if one is set. At the remote-management warning tap Install again, then Trust, then Done.

Success looks like: Settings, General, VPN & Device Management lists the company management profile.
In the console the iPad appears under Devices as Enrolled, on the chosen blueprint, within a minute.

## 3. Let the blueprint apply

The payloads arrive one at a time over the next few minutes, and the device dashboard in the console
reports them as Applied only after the next inventory:

- **Wi-Fi** applies first and needs nothing from the user.
- **Passcode**: if the iPad has no passcode, or one weaker than the policy, iPadOS prompts the user
  to set one within an hour. The Security tile stays at Not applied until that happens.
- **Restrictions** apply silently.
- **Apps**: an app the user already had installed produces a prompt asking to let the organization
  manage it; accepting converts it in place, keeping its data and sign-in. A new app asks for an
  App Store sign-in and a one-time approval of the install, because the lab deploys without volume
  purchasing (see `mdm/blueprints.md`).

Success looks like: on the device page, Security, Wi-Fi, and Restrictions all read Applied; the
Data Protection tile reads Passcode enabled; on the iPad & iPhone Apps tab the app reads Installed
and Admin-managed. If a tile lags, click Sync on the device page and reload.

## 4. Verify on the device

- Settings, General, VPN & Device Management, the management profile: the Restrictions entry lists
  what the blueprint applied.
- Settings, Touch ID & Passcode (or Face ID & Passcode): Require Passcode is Immediately when
  biometrics are on, which is stricter than the blueprint's ceiling and stands.
- Settings, General, About: no Supervised line, as expected for Open Enrollment.
- In the console, Details: Passcode Turned On, Supervised No, and the enrollment and inventory times.

## Related changes

- **Move the device to another blueprint:** device page, Assign blueprint. The device receives the
  new blueprint's payloads and loses the old ones.
- **Unenroll:** device page, the action menu, Unenroll device. Removes the management profile,
  any email account Jamf deployed, and volume-purchased apps with their data. The device record
  stays in inventory until Remove from My Devices.
- **Lock and erase** are covered in the offboarding runbook.

## Problems hit

None on the first run.
