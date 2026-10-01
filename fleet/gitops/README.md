# Fleet configuration as code

What Fleet applies to the managed Macs, as files. `fleetctl gitops` reads them, validates them,
and makes the server match, so the repository is the source of truth and every change is a
commit. The layout is the one `fleetctl new` generates for Fleet 4.92, trimmed to what the lab
uses.

| Path | What it holds |
|---|---|
| `default.yml` | Settings for the whole server: organization name, URL, the global enroll secret, single sign-on with Google Workspace (metadata by variable), labels shared by every fleet |
| `fleets/workstations.yml` | The **Workstations** fleet (Fleet's name for a team): the employee baseline of configuration profiles, disk encryption, OS floor, scripts, policies, and software (Fleet-maintained apps: Slack for every Mac, VS Code and Zoom by role label, each installed by a policy automation when missing). The counterpart of the Jamf Now "Employee baseline" blueprint in `mdm/blueprints.md` |
| `labels/` | Labels, one file each. The `canary` label scopes a change to one host before it goes to all. The `role-*` labels scope role software to the Macs issued to that role; they are declared here without a `hosts:` key, because Fleet preserves a manual label's membership when the key is absent and clears it when the key is present, so which Macs hold a role label is set through the API by the lifecycle scripts (`lifecycle/README.md`), and an apply never touches it |
| `platforms/macos/configuration-profiles/` | `.mobileconfig` payloads delivered through MDM |
| `platforms/macos/policies/` | osquery checks that pass or fail per host, with a remediation script attached where one exists |
| `platforms/macos/scripts/` | Scripts Fleet can run on a host |
| `gitops.sh` | Dry run, then apply, from the admin workstation |

No secret appears here. A `$VARIABLE` in the YAML is substituted from `fleet/.env` by
`fleetctl gitops` on the workstation (enroll secrets); a `$FLEET_SECRET_NAME` inside a profile
is substituted by the server when the profile is delivered, from a variable stored in Fleet
(the Chrome enrollment token). Fleets, disk-encryption enforcement, OS-update enforcement,
policy automations, and software installers are Fleet Premium; on Fleet Free the same profiles and
policies move into `default.yml` and apply to every host, and an app is installed by a script
attached to its policy, the pattern `google-chrome-installed.yml` keeps for that reason. How to run it, and what success looks like, is in
`runbooks/fleet-setup.md`.
