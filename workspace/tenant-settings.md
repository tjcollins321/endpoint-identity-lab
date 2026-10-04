# Google Workspace tenant settings

What is configured in the lab tenant, where it is set, and why. Values as of 2026-10-04. This is the Workspace counterpart of `mdm/blueprints.md` and `chromeos/policies.md`: the runbooks say how, `docs/evidence/` shows it applied, and `docs/design.md` says what changes at scale.

Edition: Business Plus, chosen for advanced endpoint management. Tenant domain: `tjcollins.dev`, DNS hosted at Cloudflare. Where a value is a lab choice that a production tenant would revisit, the table says so.

## Directory

| Setting | Value | Why |
|---|---|---|
| Organizational units | `/Staff`, `/Contractors`, `/Devices`, `/Offboarded` under the root. `/Offboarded` is the leavers' OU, created with GAM and carrying no policy of its own: `lifecycle/offboard.sh` moves a suspended account there with its deletion date in the note, `lifecycle/audit-access.sh` leaves it out of the review, and `workspace/gam/delete.sh` refuses an account that is anywhere else. Google also adds `/Workspace Guests` for external guest accounts; not created by the lab and unused | Settings inherit down the tree. The root carries the strictest baseline; children loosen or tighten on purpose, so a user who lands in the root by mistake gets less, not more. Users are created in their destination OU, never created in the root and moved. |
| Username convention | First initial plus last name, lowercase; digit suffix on collision | No tenant setting exists for this. The onboarding runbook states it and the GAM create-user script enforces it, which is stronger than a console default. A changed primary address keeps the old one as an alias. |
| Groups | `all-staff`, `engineering`, `marketing`, `sales`, `contractors`, all with the Security label, each with an explicit owner. One group per role in the catalog (`lifecycle/roles/`), plus `all-staff` | Groups grant access (apps, Drive sharing, group-based settings), so they are marked as security groups. The label is irreversible and a security group can nest only security groups. Every group has an owner so someone is accountable for it. |
| Group access model | Anyone in the organization can view members and post; conversations visible to members only; joining by invitation; no external members. Exception: posting on `all-staff` limited to owners and managers | The internal distribution list, with the archive closed. Google's Team preset exposes the conversation archive to the entire organization, which spans every OU, so a contractor could read a team's history. Restricting `all-staff` posting prevents reply-all storms. |
| Group creation | Organization admins only (default: anyone in the organization) | Groups grant access and appear in the directory; user-created groups sprawl without owners or naming. At scale, a self-service path with a naming prefix and an owner requirement replaces the request queue. |
| Default conversation visibility for new groups | Group members (default: entire organization) | New groups start closed; a wider audience is a per-group decision written in the group description. |

## Authentication

| Setting | Value | Why |
|---|---|---|
| 2-Step Verification | Enforced at the root. New-user enrollment period one day, counted from the user's first sign-in. Any method except codes by text or voice call. Trusted devices allowed | Enforcement, not just permission, is the control. The shortest enrollment window keeps the unenrolled period small. SMS and voice are excluded because they are the phishable and SIM-swappable methods. |
| Super admin recovery | Allowed; backup codes generated for the sole super admin | With one super admin there is no peer to reset it. A production tenant has at least two super admins, neither used for daily work. |
| Password policy | Minimum 12 characters, strong-password enforcement on, no expiry, reuse prevention on, enforced at next sign-in | Length over rotation, per current NIST guidance; forced rotation produces predictable variations. Lab choice to revisit: a production tenant puts an identity provider with breached-password screening in front, and the Workspace password becomes a fallback. |
| Session length | Seven days at the root; twelve hours for `/Contractors` | The first OU override in the tenant. Contractors re-authenticate more often because their OU says so; nothing is configured per user. |

## Access control

| Setting | Value | Why |
|---|---|---|
| Third-party app access | Unconfigured apps may request basic profile information only; internal domain-owned apps trusted; any app needing more is allow-listed individually under API controls | OAuth consent governance: a user cannot grant a random app access to mail or Drive. Each approved app is a deliberate entry with a record of who allowed it and why. |
| SAML apps | One custom SAML app, `Fleet` (the Fleet console), ON for the `engineering` group only, OFF for everyone else; Name ID the primary email; no attribute mapping | Access to a third-party app is a group membership, granted and revoked by the lifecycle scripts; the app creates its account at first sign-in. `runbooks/sso-app-setup.md` |
| Context-Aware Access | Not available on Business Plus | The intended policy is described in `docs/design.md`. Until then, MDM enrollment, enforced 2-Step Verification, and session length are the controls that exist. |
| Mobile management | Custom: Android Advanced, iOS Basic, Google Sync Unmanaged | One device-level manager per platform. Jamf Now and Fleet own Apple devices, so Google stays at the account layer for iOS (inventory, screen-lock requirement, account wipe, no profile) rather than becoming a second Apple MDM with its own push certificate. Android has no other candidate, so Google would own it. Production posture for personal phones on both platforms is Google Advanced; see `docs/design.md`. |

## Mail and domain

| Setting | Value | Why |
|---|---|---|
| MX | Google's five-record set, priorities 1, 5, 5, 10, 10 | Written by Google's setup through a one-time Cloudflare authorization, which grants no standing access to the zone. |
| SPF | `v=spf1 include:_spf.google.com ~all` | One SPF record at the apex; soft fail while DMARC is in monitor mode. |
| DKIM | 2048-bit key, selector `google` | Signing started from the Gmail authentication page after the public key was in DNS. |
| DMARC | `p=none`, aggregate reports to the admin mailbox | Monitor first. Move to `quarantine`, then `reject`, once the reports show only legitimate senders. |
| DNSSEC | On, DS record published by the registrar | Resolvers can detect forged answers for the domain. Must be turned off before the zone could ever move to another DNS host. |

## Not available on this edition

Context-Aware Access, the security center (security dashboard, security health, investigation tool, log export), and dynamic groups by directory attribute are Enterprise-tier features. `docs/design.md` covers what each would change at scale.

## Verifying

Every setting above is visible in the Admin console under Directory, Security, or Apps, Google Workspace, Gmail. Per-user state (OU path, 2-Step Verification enrollment and enforcement, group membership) is exported with GAM; the commands and their output are in `docs/evidence/04-workspace-gam-directory-export.txt`. GAM runs on the admin OAuth client only: the Cloud organization Google creates for the domain disables service-account key upload by default, and that default was kept, so there is no service-account key and no domain-wide delegation.
