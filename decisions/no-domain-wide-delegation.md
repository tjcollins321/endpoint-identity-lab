# Decision: no domain-wide delegation; the tooling runs as the administrator

Decided 2026-09-28, confirmed 2026-10-01 once its cost was known. Status: in force.

## Context

GAM, the command-line tool behind `workspace/gam/` and `lifecycle/`, can hold two kinds of
authority. Through an OAuth client it acts as the administrator who consented: users, groups,
organizational units, devices, suspension, and the Drive and Calendar ownership transfer all run
that way. Through a service account with domain-wide delegation it acts as any user in the
tenant: it can read and send their mail, change their mailbox settings, and open their files.

GAM's setup wizard creates the service account and tries to upload a key for it. On this tenant
the upload was refused: Google applies secure-by-default organization policies to a new Cloud
organization, and one of them forbids uploading a key to a service account
(`constraints/iam.disableServiceAccountKeyUpload`). The documented way past it is to override
that policy on the project and upload the key. `runbooks/gam-setup.md` records the refusal under
Problems hit.

## Decision

- **Keep the default.** No override, no service-account key, no domain-wide delegation. GAM runs
  on the admin OAuth client only.
- **Every write is the administrator's.** It runs under the administrator's own consent, given
  with their second factor, and the audit log attributes it to them. No long-lived key sits on
  the workstation, and nothing on the workstation can act as another user.
- **The scripts do not assume the limit.** They test whether GAM can send mail and use it where
  it can; on this tenant the test fails, and they fall back to a file and a checklist line.

## What it costs

The cost was not visible until the lifecycle scripts were written, on 2026-10-01. GAM sends mail,
and changes anything on a mailbox, only by acting as a user, which is delegation. So:

- The welcome kit is rendered to a file and the administrator sends it from their own mailbox.
- The initial password is issued from the Admin console or handed over with the device, not
  mailed by the create step.
- A leaver's new mail is redirected to the manager by a recipient address map set in the console,
  since Gmail routing has no API and forwarding on the mailbox itself would need the delegation.
  An auto-reply or mailbox delegation for a leaver would be a console step for the same reason.

Each of these is a line on the checklist the scripts print, not something done silently or
skipped. Everything else in the lifecycle runs without delegation.

## Alternatives considered

- **Override the policy and upload a key**, GAM's documented fix: rejected. A downloaded key
  with domain-wide delegation is a file that can impersonate every user, kept on a workstation;
  it is the credential Google's own guidance says to avoid, and nothing here needed it.
- **Delegation limited to sending mail and mailbox settings**: the right shape for the three
  costs above, deferred. It removes the manual steps without granting access to mail or files,
  and it is what the design note proposes at scale.
- **Keyless delegation through Workload Identity Federation**: how delegation would be added if
  a task needs it, so that there is still no key to download. Not built; nothing in the lab calls
  for it.
- **Mail from somewhere else**: at a company the welcome mail and the password come from the HR
  system or the ticketing integration, not from an administrator's script. Out of reach for a
  lab with neither.

## Consequences

Three manual steps stay on the onboarding and offboarding checklists, and the runbooks say why.
The tenant has no credential that can read a user's mail or files, which is also a privacy
position: an administrator's script cannot open a leaver's mailbox, and delegation to a manager
is an approved, logged exception rather than a default. The audit trail names a person for every
change. At scale the trade reverses in one respect: the scripts should run under a service
identity with a scoped admin role rather than a super administrator's session, and sending
should be delegated narrowly; `docs/design.md` lists both under what changes at 500 users.
