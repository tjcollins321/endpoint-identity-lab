# Runbook: SAML single sign-on to a third-party app, Google Workspace as the identity provider

**When to use this:** an application that speaks SAML should accept Google Workspace sign-ins,
with access decided by group membership in the directory. Here the application is the Fleet
console, and accounts in it are created just in time at the first sign-in.

**When NOT to use this:** an app that Google lists in its catalog, where the pre-built entry
fills in the service-provider details; sign-in to devices at MDM enrollment, which is Fleet's
separate End users setting; a proxy in front of an app that has no SSO of its own, which is the
identity-aware-proxy pattern and not this runbook.

Inputs, agreed before starting:

| Input | Where it comes from | Example |
|---|---|---|
| The app's ACS URL and entity ID | The app's SSO documentation | `https://fleet.<domain>/api/v1/fleet/sso/callback`, `https://fleet.<domain>` |
| The group that grants access | The directory; created by the onboarding runbook | `engineering` |
| A test user in that group | The directory | `aengineer@` |
| An administrator in the app that does not use SSO | The app; created before SSO is turned on | the first Fleet admin |

In Windows terms: the custom SAML app in Google is an enterprise application in Entra ID, the
ACS URL is its reply URL, the entity ID its identifier, the Name ID its user claim, and "ON for
a group" is assignment required plus an assigned group. The identity provider's metadata file is
the federation metadata XML. The analogy breaks at provisioning: Entra pairs SAML with SCIM,
which also removes accounts; just-in-time provisioning only creates them (section 6).

---

## 1. Keep one administrator out of SSO

Before turning SSO on, confirm the app has an administrator that signs in with a password and
will keep doing so. It is the account that recovers the app when the identity provider is down
or misconfigured, and here it is also the account `fleetctl` runs as. It is never signed in
through SSO: an attempt is refused (section 5), and nothing changes, but there is no reason to
try.

## 2. Create the SAML app in Google Workspace

Admin console, Apps, Web and mobile apps, Add app, Add custom SAML app.

1. Name: `Fleet`.
2. Google Identity Provider details: Download metadata. Keep the file outside the repository.
3. Service provider details: ACS URL and Entity ID from the inputs; Start URL blank; Signed
   response unchecked; Name ID format `EMAIL`; Name ID `Basic Information > Primary email`.
4. Attribute mapping: none. The app then uses the email as the display name.
5. User access: leave OFF for everyone, then Groups, the access group, Service status ON, Save.

Success looks like: the app page reads "ON for 1 group" with the group's name, and the service
provider details show the ACS URL and entity ID. Google says access changes can take up to 24
hours; here they took effect within minutes.

## 3. Turn on SSO in the app, then test twice

Fleet, Settings, Integrations, Authentication (SSO), Fleet users (End users is device
enrollment; leave it alone). Enable single sign-on; Identity provider name `Google Workspace`;
Entity ID exactly as in Google, no trailing slash; Metadata URL blank, since Google publishes
none; Metadata, the contents of the downloaded file; "Allow SSO login initiated by identity
provider" off; "Create user and sync permissions on login" off for the first test. Save.

**Test 1, JIT off.** In a browser with no Google session (a Safari Private window), open the
app and click Sign in with SSO. The email field is not used; the identity comes from Google.
Sign in as the test user. Expected: Google accepts, and the app refuses because it has no
account for that email. Fleet shows nothing for this case: the login page simply reloads, and
the reason is in the server log. The lesson of this test is the division of labor: Google
authenticates, the app authorizes.

**Test 2, JIT on.** Turn on "Create user and sync permissions on login", Save, and sign in again.
Expected: the user lands in the app with the default role, global observer in Fleet, and
Settings, Users lists the account with SSO as its authentication.

Success looks like, on the server side: the activity log shows `created_user`,
`changed_user_global_role` (observer), `user_added_by_sso`, and `user_logged_in` within the same
second, and the users list has the new account with SSO on.

## 4. Pin it in the repository

`fleetctl gitops` resets every setting the files do not hold, so SSO set in the UI lasts until
the next run unless `org_settings.sso_settings` is in `fleet/gitops/default.yml`. The metadata
goes in by variable, as Fleet's own example does: it is not a secret, but it names the tenant.

1. The XML on one line, single-quoted because it holds double quotes, appended to `fleet/.env`
   (`>>`, never `>`, which would replace the file):

   ```bash
   printf "FLEET_SSO_METADATA='%s'\n" "$(tr -d '\n\r' < ~/Downloads/GoogleIDPMetadata.xml)" >> fleet/.env
   ```

2. The name with an empty value in `fleet/.env.example`.
3. In `default.yml`, under `org_settings`, the `sso_settings` block with the same values as the
   UI: `enable_sso`, `idp_name`, `entity_id`, `metadata: '$FLEET_SSO_METADATA'`,
   `enable_jit_provisioning`, `enable_sso_idp_login`.
4. `fleet/gitops/gitops.sh --dry-run`, then `fleet/gitops/gitops.sh`.

Success looks like: `[!] gitops succeeded`, the SSO settings read back from the API unchanged
field by field (the dry-run output does not say; it lists what it sends, not what differs),
and the test user can sign out and in again.

## 5. Verify

- Fleet, Settings, Users: the test user, SSO, observer. The break-glass administrator, password,
  admin.
- Google Admin console, Reporting, Audit and investigation, SAML log events, filtered to the
  app: a successful login for the test user, with the failed attempts before it.
- The server log, one line per callback: `user not configured to use sso` for the password
  administrator, `was not found in the datastore` for an unknown user with JIT off, and a plain
  success with JIT on. `docs/evidence/13-fleet-sso-google-readback.txt` is the read-back.

## 6. What it means for the lifecycle

- **Onboarding:** adding the user to the access group is the whole grant. The app account
  appears at the first sign-in, read-only. Roles above that are a directory attribute mapped
  into the SAML response (`FLEET_JIT_USER_ROLE_GLOBAL`), not built here.
- **Offboarding:** suspending the Google account ends sign-in at once, and the offboarding
  script also revokes its sessions. The app account remains, because JIT never deletes; the
  offboarding runbook removes it.
- **When the identity provider is down:** the password administrator signs in and turns SSO
  off or fixes it.
- **Fleet Free:** SSO stays; JIT is Fleet Premium. Without it, accounts are created ahead of
  time in Settings, Users, with SSO as their authentication.

## Problems hit

- **The first attempt signed in as the wrong person.** The browser held a Google session as the
  Workspace administrator, who owns the access group and so has the app; Google answered the
  SAML request with that account in under a second, no chooser shown, and Fleet refused it as
  a password account with the message "Single sign-on is not enabled on your account", which
  read as a configuration fault. A Private window, with no Google session, showed the sign-in
  page.
- **Two refusals, two behaviours.** A password account arriving by SSO gets that message; an
  unknown user (JIT off) gets nothing, the login page reloads as if the button had done
  nothing. Only the server log states the reason in both cases: `user not configured to use
  sso` and `User with email=... was not found in the datastore`.
- **The 2-Step Verification window counts from the first sign-in.** The tenant enforces 2-Step
  Verification with a one-day enrollment period; a test user created three days earlier was
  still offered a grace period at its first sign-in, so no backup code was needed. The
  directory export had shown the user as enforced and not enrolled, which had read as locked
  out; it is not, until the user has signed in and the period has run.
- **The dry run is not a diff.** `fleetctl gitops --dry-run` reports what it would send per
  section ("would've updated 1 label"), the same lines on a run with no changes; whether a
  change took effect is read back from the server afterward.
