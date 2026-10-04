# Runbook: GAM on the admin workstation

**When to use this:** setting up a workstation to run the scripts in `workspace/gam/` against
the tenant, or re-authorizing after the admin's password or second factor changes.

**When NOT to use this:** giving GAM access to user data (mail contents, Drive files, calendars)
on a user's behalf. That is domain-wide delegation for a service account, which this lab does
not use; step 2 says why, `decisions/no-domain-wide-delegation.md` records the decision and its
cost, and `docs/design.md` covers what changes at scale.

Everything here runs as the tenant's super admin through an OAuth client in a Cloud project
the tenant owns. Nothing produced by it goes in the repository: see the file table at the end.

---

## 1. Install

```bash
bash <(curl -s -S -L https://raw.githubusercontent.com/GAM-team/GAM/main/src/gam-install.sh) -u admin@example.com
```

The GAM quick start uses the address `https://gam-shortn.appspot.com/gam-install`; it is the
GAM team's own shortener and answers a 301 to the file above. The installer picks the build for
the machine's macOS version and architecture, extracts to `~/bin/gam7`, and appends an alias
line to the shell startup files, creating them if absent. It then asks:

| Prompt | Answer |
|---|---|
| Can you run a full browser on this machine? | `y` |
| Are you ready to set up a Google API project for GAM? | `yes` (step 2) |
| Are you ready to authorize GAM to perform Google Workspace management operations as your admin account? | `yes` (step 3) |
| Are you ready to authorize GAM to manage Google Workspace user data and settings? | `no` (domain-wide delegation; not used) |

## 2. Create the Cloud project

The wizard opens a browser: sign in as the super admin, approve. It then creates a project named
GAM Project with a random `gam-project-` ID, enables 23 APIs, sets the OAuth consent screen,
creates the OAuth client, and pauses with numbered steps to mark the new app as Trusted in the
Admin console (Security, Access and data control, API controls, Manage third-party app access).
Do those, press Enter, and it creates a service account and tries to upload a key for it.

On a tenant whose Cloud organization is new, that upload is refused by an organization policy
and the wizard reports the project as failed. It is not: the OAuth client is on disk and the
service account simply has no key. Answer `no` to the retry and continue with step 3. The
reasoning is in Problems hit.

Success: `~/.gam/client_secrets.json` exists and names the project.

## 3. Authorize the admin client

```bash
gam oauth create admin@example.com
```

A scope menu appears; type `c` to continue with the defaults. The browser opens again: pick the
admin, Allow. Because the app belongs to the tenant's own Cloud project it is an internal app,
so there is no unverified-app warning.

Success: `Client OAuth2 File: /Users/<you>/.gam/oauth2.txt, Created`.

## 4. Configure

```bash
gam info domain
```

Success: the customer ID, the primary domain, and `Primary Domain Verified: True`. Then save the
customer ID, the domain, and the local timezone so commands can omit them:

```bash
gam config customer_id C0xxxxxxx domain example.com timezone local save verify
```

The scripts in `workspace/gam/` read the domain from this file, so bare usernames work.

## 5. Verify

```bash
gam print users fields primaryemail,ou,suspended,isenrolledin2sv,isenforcedin2sv
```

Success: one row per account with its OU path and 2-Step Verification flags, as in
`docs/evidence/04-workspace-gam-directory-export.txt`.

## Files on the workstation

| File in `~/.gam` | What it is | Handling |
|---|---|---|
| `gam.cfg` | Settings | Not secret; stays local |
| `client_secrets.json` | OAuth client ID and secret for the project | Secret; never leaves the workstation |
| `oauth2.txt` | The admin's authorization token | Secret; revoke with `gam oauth delete` when the workstation is retired |
| `oauth2service.json` | Service account identity, with no private key on this setup | Contains nothing usable; still not committed |

All four names are in `.gitignore` in case one is ever copied into the tree.

## Problems hit

- **Service-account key upload refused.** The wizard failed with
  `constraints/iam.disableServiceAccountKeyUpload violated`. Google applies secure-by-default
  organization policies to a new Cloud organization, and one of them forbids uploading keys to
  service accounts. GAM's documented fix is to grant yourself Organization Policy Administrator
  and override the constraint on the project, then `gam upload sakey`. Not done: the same page
  opens with Google's advice to avoid service-account keys, nothing in the lifecycle scripts
  needs one (users, groups, suspension, and the Drive ownership transfer all run through the
  admin client), and GAM reads the service-account file only on the code paths that need it.
  If per-user data access is ever needed, the choices are keyless Workload Identity Federation
  or that project-level override, with the reason written down.
- **`gam info domain` can take a minute or more on a new tenant.** After the domain summary it
  looks for the latest customer usage report and walks back a day at a time until it finds one;
  a tenant a day old has none. The scripts therefore read the domain from `gam.cfg` instead.
- **The wizard no longer matches the wiki.** Current builds create the OAuth client themselves
  and pause for the Trusted-app steps; the wiki still describes creating the client by hand and
  pasting its ID and secret. The prompts in the table above are what the installer asks.
- **`gam info domain` prints the admin's secondary (recovery) email address.** Never paste its
  output into a document; use `gam print users` or `gam print domains` for evidence.
