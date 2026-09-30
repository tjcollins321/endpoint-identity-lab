# Runbooks

One runbook per procedure in the employee lifecycle, plus the setup procedures the lifecycle
depends on. A runbook says when to use it and when not to, the exact steps with what success
looks like, how to verify, and what went wrong the first time it was run (Problems hit, at the
end). Platform settings live in `workspace/tenant-settings.md`, `mdm/blueprints.md`, and
`chromeos/policies.md`; the reasoning behind the larger choices is in `decisions/`.

| Procedure | Runbook | State |
|---|---|---|
| Onboarding: account, access, first sign-in, devices | [onboarding.md](onboarding.md) | Workspace sections written; device sections follow the MDM work |
| Offboarding: cut access, transfer data, devices, delete | [offboarding.md](offboarding.md) | Workspace sections written; device sections follow the MDM work |
| GAM on the admin workstation | [gam-setup.md](gam-setup.md) | written |
| iPadOS enrollment into Jamf Now (Open Enrollment) | [ipados-enrollment-jamf.md](ipados-enrollment-jamf.md) | written |
| macOS enrollment into Jamf Now (user-approved MDM) | [mac-enrollment-jamf.md](mac-enrollment-jamf.md) | written; both paths exercised, the MacBook from the console and a VM by Open Enrollment |
| macOS lab VMs in UTM with distinct device identities | [macos-vm-lab.md](macos-vm-lab.md) | written |
| Fleet server: Compose stack behind a Cloudflare Tunnel, Apple MDM on, configuration as code applied, fleetd package built | [fleet-setup.md](fleet-setup.md) | written |
| macOS provisioning into Fleet: fleetd package, user-approved MDM, the baseline delivered and verified | [mac-provisioning-fleet.md](mac-provisioning-fleet.md) | written; run on a VM from a clean install (2026-09-30) |
| MDM migration: a Mac from Jamf Now to Fleet by unenrolling and enrolling through Fleet's link, recovery key escrow checked | [mdm-migration-jamf-to-fleet.md](mdm-migration-jamf-to-fleet.md) | written; run on a VM enrolled in Jamf Now (2026-09-30) |
| SAML single sign-on to a third-party app (the Fleet console), Google Workspace as identity provider, access by group, just-in-time provisioning | [sso-app-setup.md](sso-app-setup.md) | written; run once, with a test user (2026-09-30) |
