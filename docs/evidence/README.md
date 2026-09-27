# Evidence index

Each file here backs a specific statement in the top-level README or `docs/design.md`. Files that back no statement are not kept. Screenshots are redacted before they land here; the unredacted capture stays in `raw/`, which is ignored by git. Text transcripts are captured with only public sources (registries, authoritative nameservers, public resolvers) so they need no redaction.

| File | What it shows | Statement it supports |
|---|---|---|
| `01-tjcollins-dev-dns-checks.txt` | `dig` and RDAP transcript: the registry delegates `tjcollins.dev` to Cloudflare, the nameservers answer authoritatively, a test record is added and removed, and DNSSEC validates at a public resolver | The lab domain's DNS zone is hosted at Cloudflare, active and DNSSEC-signed, before any tenant or MDM depended on it |
