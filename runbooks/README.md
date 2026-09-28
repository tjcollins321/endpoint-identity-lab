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
