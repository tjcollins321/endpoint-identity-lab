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

## Problems hit

None on the first run. The stack came up healthy on the first `up`, the connector registered
within seconds of the route being saved, and the push certificate was accepted on the first
upload.
