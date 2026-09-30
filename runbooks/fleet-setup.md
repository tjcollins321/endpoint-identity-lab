# Runbook: standing up the Fleet server (Docker Compose behind a Cloudflare Tunnel)

**When to use this:** the lab needs a Fleet server reachable by managed Macs over HTTPS at a
stable hostname, run on the admin workstation with no inbound port and no public address.

**When NOT to use this:** a production deployment, which needs an always-on host, a backed-up
database, and TLS terminated on infrastructure the organization controls; see `docs/design.md`.

Inputs, agreed before starting:

| Input | Where it comes from | Example |
|---|---|---|
| Hostname | A subdomain of the lab domain, in a Cloudflare zone | `fleet.<domain>` |
| Cloudflare account | The one holding the zone, with the Zero Trust Free plan activated | (payment method on file, not charged) |
| Secrets | Generated locally into `fleet/.env` from `fleet/.env.example` | `openssl rand -base64 32` |
| Fleet Premium key | Optional; empty runs Fleet Free | trial key |
| Docker | Docker Compose on the workstation | OrbStack |

The Compose file is `fleet/docker-compose.yml`; the comments there explain each service. Fleet's
image is amd64 only and runs under Rosetta on Apple Silicon, which is fine at this scale.

---

## 1. Secrets

Copy `.env.example` to `.env`, fill in two MySQL passwords and the server private key (32 bytes
or more; it encrypts MDM certificates at rest and can never change once MDM is on), and the
license key if any. Make the file owner-only:

```bash
chmod 600 fleet/.env
```

Leave the tunnel token empty until section 2.

## 2. Tunnel

Cloudflare One dashboard, Networking, Tunnels, Create a tunnel, Cloudflared. Name it, choose
Docker on the connector page, and copy only the token from the command shown into `.env` as
`TUNNEL_TOKEN`; the Compose file runs the connector, so the command itself is not used. On the
tunnel's Routes tab, Add route, Published application: the subdomain, the domain, and the service
URL `http://fleet:8080`, which is the Fleet container's name and port on the Compose network.
Saving the route creates the proxied DNS record.

Success looks like: the tunnel is listed with one route and no connector yet.

## 3. Start everything except the connector, and create the admin locally

Fleet's setup page is open to whoever reaches it first until an admin exists, so the connector
starts last.

```bash
cd fleet && docker compose up -d mysql redis fleet
```

`docker compose ps` shows mysql, redis, and fleet healthy and the prepare-db job exited 0. Open
`http://localhost:8080`, complete the setup wizard, and enter the public URL,
`https://fleet.<domain>`, as the Fleet web address, since every enrollment profile and the fleetd
package embed it.

Success looks like: an empty Hosts page, and Settings, Organization settings, shows the public
URL.

## 4. Start the connector and verify from outside

```bash
docker compose up -d cloudflared
```

The connector's log shows four registered connections and one ingress rule for the hostname.
Then, from any machine:

```bash
curl -sI https://fleet.<domain>/healthz
```

Success looks like: HTTP 200, `server: cloudflare`, and a valid certificate. The login page loads
at the hostname from a managed Mac.

## 5. Apple MDM

Apple devices do not poll their MDM server; Fleet asks Apple's push service to wake a device,
which then connects to Fleet for whatever is waiting. That needs a push certificate bound to
this server.

Settings, Integrations, Mobile device management, Apple, Turn on, Download CSR. The request is
already signed with Fleet's MDM vendor identity, which is why it comes from Fleet and not from
`openssl`. At the Apple Push Certificates Portal (identity.apple.com/pushcert), sign in with the
Apple Account that will own the certificate, Create a Certificate, upload the CSR, write the
server's name in the notes field, download the `.pem`, and upload it in Fleet.

Success looks like: the MDM page shows Apple MDM turned on with an expiry one year out. From
outside, the SCEP endpoint answers only once MDM is on:

```bash
curl -sI "https://fleet.<domain>/mdm/apple/scep?operation=GetCACert"
```

returns HTTP 200. Record the expiry. Renewal is yearly and must be done from the same Apple
Account: renewing keeps the push topic and every enrolled device; creating a new certificate
instead mints a new topic and every device must re-enroll. Several servers can hold certificates
under one account, each with its own topic, told apart by the notes field. The private key never
leaves Fleet and is encrypted with the server private key from `.env`, which is why that key can
never change once MDM is on.

## 6. fleetctl and the configuration-as-code layout

Everything Fleet applies to a Mac from here on is a file under `fleet/gitops/`, applied by
`fleetctl gitops`; `fleet/gitops/README.md` says what each file holds. So the CLI comes first.

**Install fleetctl.** It is versioned with the server and must match its release. Homebrew's
`fleet-cli` formula is Rancher's Kubernetes Fleet, a different product, so the binary comes from
Fleet's GitHub release and is verified twice: its SHA-256 against the release's `checksums.txt`,
and its Developer ID signature.

```bash
gh release download fleet-v4.92.1 -R fleetdm/fleet -p 'fleetctl_v4.92.1_macos.zip' -p checksums.txt
grep fleetctl_v4.92.1_macos.zip checksums.txt | shasum -a 256 -c -
unzip -q fleetctl_v4.92.1_macos.zip
codesign -dv --verbose=2 fleetctl_v4.92.1_macos/fleetctl 2>&1 | grep Authority
install -m 755 fleetctl_v4.92.1_macos/fleetctl ~/bin/fleetctl
```

Success looks like: `OK` from shasum, `Developer ID Application: Fleet Device Management Inc`
from codesign, and `fleetctl --version` printing the server's version. `spctl --assess` rejects
the file as "not an app", which is what it says of any bare command-line binary, not a failure.
`~/bin` is not on the PATH by default; add it, or call the binary by path.

**Log in.** From the administrator's own terminal, since it asks for the password:

```bash
fleetctl config set --address https://fleet.<domain>
fleetctl login
```

Success looks like: `Fleet login successful and context configured!`, and `~/.fleet/config`
holding the token with mode 0600. That is an administrator's token on a workstation, fine for a
lab; a pipeline uses an API-only user with the GitOps role instead (`docs/design.md`).

**Lay out the configuration.** Two properties of `fleetctl gitops` shape the files. It applies
the whole configuration, not a diff: a setting missing from the YAML is reset to Fleet's
default, and with `--delete-other-fleets` a fleet missing from the YAML is deleted and its hosts
become Unassigned. So `default.yml` starts from the live settings (`fleetctl get config --yaml`),
not from a blank page, and every run applies every file. And a `$VARIABLE` in the YAML is
substituted from the environment, so `fleet/.env` gains `FLEET_GLOBAL_ENROLL_SECRET` and
`FLEET_WORKSTATIONS_ENROLL_SECRET`, each from `openssl rand -base64 24`, and `gitops.sh` exports
that file before it runs.

**Turn off the enroll-secret exception.** A new Fleet server marks enroll secrets as an
exception to GitOps, to be managed in the UI, and the dry run refuses any `secrets:` key while
that is set (`"secrets" is excepted from GitOps management`). This lab keeps the secrets in code
by substitution, so in Settings, Integrations, Change management, untick the exception for
enroll secrets and save. The labels and software exceptions are off by default and stay so.

**Validate.**

```bash
fleet/gitops/gitops.sh --dry-run
```

Success looks like: `[!] gitops dry run succeeded`, and nothing has changed on the server. The
apply itself waits until the profiles, policies, scripts, and the canary label are in place
(section 7).

## 7. Apply, then build the package

**Apply.** The runner dry-runs and applies in one go:

```bash
fleet/gitops/gitops.sh
```

Success looks like: `[!] gitops dry run succeeded` followed by `[!] gitops succeeded`, and in the
UI, with the Workstations fleet selected: Controls, OS settings lists the profiles with custom
targets (the `canary` label), Disk encryption on, and OS updates at the floor with its deadline;
Controls, Scripts lists the remediation script; Controls, Variables lists the Chrome token, stored
without its `FLEET_SECRET_` prefix; Policies lists the three policies with the automation on the
Chrome one; Hosts, Labels shows `canary`. A second run is safe: it re-applies the same state, logs the label as
updated, and changes nothing in effect, which is the property that makes the repository the
source of truth.

**Build the package.** Once, after the server URL is final and the fleet exists, from a folder
outside the repository so it can be shared into a virtual machine on its own:

```bash
mkdir -p ~/fleet-pkg && cd ~/fleet-pkg
set -a; source <repo>/fleet/.env; set +a
fleetctl package --type=pkg --fleet-url=https://fleet.<domain> \
  --enroll-secret="$FLEET_WORKSTATIONS_ENROLL_SECRET" --fleet-desktop --enable-scripts
```

`--fleet-desktop` adds the menu-bar app that carries the Turn on MDM flow; `--enable-scripts`
is required, since a fleetd built without it refuses to run scripts. Success looks like
`Success! You generated fleetd at .../fleet-osquery.pkg`, about 57 MB. The package embeds the
server URL and the fleet's enroll secret, so it is treated as a secret and never enters the
repository (`*.pkg` is ignored). It is unsigned, because signing needs a Developer ID:
`pkgutil --check-signature` reports no signature, Gatekeeper refuses a double-click, and the
install is from the command line, which is a lab shortcut and is noted as such:

```bash
sudo installer -pkg fleet-osquery.pkg -target /
```

Provisioning a Mac with it, from clean install to the baseline applied, is
`mac-provisioning-fleet.md`; moving a Mac in from Jamf Now is `mdm-migration-jamf-to-fleet.md`.

## Problems hit

Sections 1 to 5: none on the first run. The stack came up healthy on the first `up`, the
connector registered within seconds of the route being saved, and the push certificate was
accepted on the first upload.

Section 6: `brew install fleetctl` finds no formula and suggests `fleet-cli`, which is Rancher's
Kubernetes Fleet; the release binary is the right route on macOS without npm. The first dry run
failed on the enroll-secret exception described above; one setting in the UI, then it passed. The Chrome
remediation script first checked the installed browser with `codesign --verify --deep --strict`,
which a Chrome that has updated itself in place fails even when healthy, so the script would
have reinstalled a working browser; the check is now a shallow `codesign --verify`, and the
script is exercised on a clean virtual machine, never on a machine in use.
