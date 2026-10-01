# Decision: access and devices follow a role catalog

Decided 2026-10-01. Status: implemented in `lifecycle/`.

## Context

The tenant started with two organizational units, three groups, and prose: "employee or
contractor". Onboarding was five single-purpose scripts run by hand in the right order. That
works for the tenth hire and fails for the hundredth, the way copying a teammate's group list does
in any directory: access accumulates, nobody can say what a role is supposed to have, and a
transfer either strips too much or leaves too much behind.

## Decision

- **OUs carry policy, groups carry access, the catalog is data.** An organizational unit is where
  settings inherit (session length, service controls, device policy); a group is what grants
  something (a list, an app, a share). No OU per department, because no policy in this tenant
  differs by department; the day one does, a sub-OU is added for that reason and not before. The
  role catalog is one small file per role (`lifecycle/roles/`), read as data: the OU, the groups,
  the title and department defaults, the device entitlement, and the welcome template.
- **The role is written into the directory.** The department attribute names the role; nothing
  else is stored by the scripts. Every command reads the account and converges it to the catalog,
  which makes second runs free and makes an audit possible at any time.
- **A role change removes only what the catalog granted.** Groups that belong to other catalog
  roles come off on a transfer; groups that no role grants are one-off exceptions, kept and
  reported, reviewed by the audit, removable with a strict option. Silent removal of an exception
  is how automation creates its own tickets.
- **One company device per person, chosen by the role, and nobody gets two.** Browser-only roles
  get a Chromebook, local-tooling roles get a Mac, external people bring their own computer and
  get account-layer controls only, phones are personal and managed by Google on both platforms.
  The Apple MDM (Jamf Now for the physical devices, Fleet for the Macs) never sees a personal
  device.
- **In Fleet, a role is a label whose definition lives in git and whose membership lives in the
  API.** The label is declared in GitOps without a host list, which Fleet preserves across
  applies; software and policies are scoped to it in git; which Macs hold it is set by the
  lifecycle scripts through the API, since a device assignment is operational state, not
  configuration. A label created outside git is deleted on the next apply; assigning a device
  needs no apply.
- **No domain-wide delegation.** Every write runs under the administrator's own authorization and
  is attributed to them. The cost is real and accepted: GAM cannot send mail (the welcome kit is a
  rendered file the admin sends; the initial password is a console step), and a leaver's auto-reply
  or delegation is a console step. Where delegation exists the same scripts send through GAM.

## Alternatives considered

- **An OU per department**, the Active Directory habit: rejected until a policy needs it.
- **Removing every group not in the new role on a transfer**: the first design; replaced by the
  exceptions rule after thinking through a tenant where one-off grants exist. Kept as `-S`.
- **Fleets per role instead of labels**: a fleet is exclusive, Premium, and carries its own
  package and enroll secret; it is the right unit for a different baseline, not for role
  entitlements that overlap. One baseline fleet plus role labels mirrors OU plus groups.
- **A service account with delegation for mail only**: deferred; a sending-only identity is the
  at-scale answer, and the trade-off is written down rather than taken quietly.

## Consequences

Onboarding, offboarding, and a role change are one command each, re-runnable, with a read-back and
a checklist of what stays manual. `audit-access.sh` reports drift against the catalog. At scale the
trigger becomes an HRIS event or a ticket, the runner a service rather than a workstation, the
language Python against the APIs, and SCIM carries the role into applications and into Fleet's
host vitals; `docs/design.md` says what else changes.
