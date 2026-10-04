# Runbooks

One runbook per procedure in the employee lifecycle, plus the setup procedures the lifecycle
depends on. A runbook says when to use it and when not to, the exact steps with what success
looks like, how to verify, and what went wrong the first time it was run (Problems hit, at the
end). Platform settings live in `workspace/tenant-settings.md`, `mdm/blueprints.md`, and
`chromeos/policies.md`; the reasoning behind the larger choices is in `decisions/`.

| Procedure | Runbook | State |
|---|---|---|
| Onboarding by role: account, attributes, access, welcome kit, the Mac or Chromebook assigned, first sign-in | [onboarding.md](onboarding.md) | written around `lifecycle/onboard.sh`; run by batch for the Marketing and Sales hires (2026-10-01) and by hand for an engineer with a Mac (2026-10-04) |
| Offboarding: access cut first, Drive and Calendar transferred, groups removed, the leavers' OU, work account wiped from personal devices, Mac locked or Chromebook disabled, console account deleted, deletion queued | [offboarding.md](offboarding.md) | written around `lifecycle/offboard.sh`; run for the Chromebook's holder (2026-10-01) and for two holders of a Fleet-managed Mac, one by the emergency form first (2026-10-04) |
| Role change (transfer, reorg, rehire): OU, groups, attributes, and the device's role label converged to the new role, one-off grants kept | [role-change.md](role-change.md) | written; run as a round trip on the Marketing hire (2026-10-01) and as a transfer inside one hire's lifecycle (2026-10-04) |
| GAM on the admin workstation | [gam-setup.md](gam-setup.md) | written |
| iPadOS enrollment into Jamf Now (Open Enrollment) | [ipados-enrollment-jamf.md](ipados-enrollment-jamf.md) | written |
| macOS enrollment into Jamf Now (user-approved MDM) | [mac-enrollment-jamf.md](mac-enrollment-jamf.md) | written; both paths exercised, the MacBook from the console and a VM by Open Enrollment |
| ChromeOS enrollment: a ChromeOS Flex device enrolled to the tenant, device policy by its OU, user policy by the person's OU | [chromeos-enrollment.md](chromeos-enrollment.md) | written; run on a Flex virtual machine (2026-10-01) |
| macOS lab VMs in UTM with distinct device identities | [macos-vm-lab.md](macos-vm-lab.md) | written |
| Fleet server: Compose stack behind a Cloudflare Tunnel, Apple MDM on, configuration as code applied, fleetd package built | [fleet-setup.md](fleet-setup.md) | written |
| macOS provisioning into Fleet: fleetd package, user-approved MDM, the baseline delivered and verified | [mac-provisioning-fleet.md](mac-provisioning-fleet.md) | written; run on a VM from a clean install (2026-09-30) |
| MDM migration: a Mac from Jamf Now to Fleet by unenrolling and enrolling through Fleet's link, recovery key escrow checked | [mdm-migration-jamf-to-fleet.md](mdm-migration-jamf-to-fleet.md) | written; run on a VM enrolled in Jamf Now (2026-09-30) |
| SAML single sign-on to a third-party app (the Fleet console), Google Workspace as identity provider, access by group, just-in-time provisioning | [sso-app-setup.md](sso-app-setup.md) | written; run once, with a test user (2026-09-30) |
