# GAM lifecycle scripts

Five scripts that run the Google Workspace half of the employee lifecycle from the admin
workstation with [GAM](https://github.com/GAM-team/GAM). The runbooks
(`runbooks/onboarding.md`, `runbooks/offboarding.md`) say when to run each one and what to
check afterwards; this file is the reference.

| Script | Step | What it does |
|---|---|---|
| `create-user.sh` | Onboarding 1 | Creates the account in its destination OU with the username convention (first initial plus last name; digit suffix on collision with a different person), random password, change at first sign-in |
| `add-to-groups.sh` | Onboarding 2, reorgs | Adds the account to one or more groups as a member, skipping groups it is already in |
| `suspend.sh` | Offboarding 1 | Deletes app passwords, backup codes, and OAuth tokens, signs out every session, then suspends |
| `transfer-drive.sh` | Offboarding 2 | Transfers Drive ownership to a named account through the Data Transfer API and waits for completion |
| `delete.sh` | Offboarding 3 | Deletes the account; refuses unless it is suspended, its Drive has been transferred, it is in `/Offboarded`, and the deletion date in its note has arrived (`-f` overrides) |

Conventions: `#!/bin/bash`, bash 3.2-compatible (the macOS system bash), `shellcheck` clean,
idempotent (a second run reports and changes nothing), and each script ends with a read-back
that verifies what it did. Bare usernames take the tenant's primary domain. GAM is found on
`PATH` or at `~/bin/gam7/gam`, or set `GAM`. Everything runs through the admin's OAuth
authorization; no service account and no domain-wide delegation are involved.
