# Evidence index

Each file here backs a specific statement in the top-level README or `docs/design.md`. Files that back no statement are not kept. Screenshots are redacted before they land here; the unredacted capture stays in `raw/`, which is ignored by git. Text transcripts are captured with only public sources (registries, authoritative nameservers, public resolvers) so they need no redaction.

| File | What it shows | Statement it supports |
|---|---|---|
| `01-tjcollins-dev-dns-checks.txt` | `dig` and RDAP transcript: the registry delegates `tjcollins.dev` to Cloudflare, the nameservers answer authoritatively, a test record is added and removed, and DNSSEC validates at a public resolver | The lab domain's DNS zone is hosted at Cloudflare, active and DNSSEC-signed, before any tenant or MDM depended on it |
| `02-workspace-admin-audit-directory.png` | Admin log events filtered to user creation, OU change, group creation, and group membership: the two test users created, moved into `/Staff` and `/Contractors`, and added to their groups, each with actor and timestamp | Users are placed by OU and granted access by group, and every directory change is attributable in the audit log |
| `03-workspace-admin-audit-security.png` | Four admin log entries stacked: 2-Step Verification enforcement turned on at the root, session length set to seven days at the root and twelve hours for `/Contractors`, and the minimum password length set to 12. Cropped below the actor row, which removes the IP address and internal resource IDs | The tenant's authentication and session policy is enforced, and the `/Contractors` override shows a setting applied by OU |
