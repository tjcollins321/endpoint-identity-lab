# Runbook: role change

**When to use this:** a transfer, a promotion, or a reorg moves a person to another role in the
catalog, or a rehire returns to one. One command converges the account to the new role: the OU if
it differs, the groups the role grants, the groups other roles grant removed, title and department,
and the company device moved between role labels or reclaimed when the entitlement changes class.

**When NOT to use this:** a title change inside the same role (`gam update user <user> organization
type work title "..." primary`), or a manager change alone (`gam update user <user> relation manager
<address>`).

Inputs: the username and the new role; optionally a title other than the role's default, the new
manager, and a newly issued device (`-d`).

---

## 1. Run the change

```bash
lifecycle/change-role.sh jmbeki engineer
```

What it does, reading before every write:

1. **OU.** Moved when the new role's OU differs; policy follows the OU, so a contractor becoming
   staff gains the seven-day session and loses the twelve-hour one by this step alone.
2. **Groups.** Three sets: the groups the new role grants are added; a membership of a group that
   another catalog role grants is removed, since it is the old role's access; a membership that no
   role grants is kept and reported as a one-off grant, because the catalog is a role model, not a
   complete access model, and stripping an exception on a transfer is how "I lost access when I
   moved teams" tickets are made. `-S` removes those too, for a start-clean transfer.
   `lifecycle/audit-access.sh` lists the kept exceptions for review at any time.
3. **Title and department** from the role (`-t` overrides the title); the manager with `-m`.
4. **Device.** Into a Mac role: a Mac the person already holds moves to the new role label (its apps
   follow), or a newly issued one is mapped with `-d`. Out of a Mac role: the Mac leaves its label
   and is mapped back to the admin, with "collect the Mac" on the checklist. Chromebooks the same
   way, by annotation. The Mac's role software changes with the label within the policy interval.
5. **Read-back,** then the checklist.

Success looks like (the Marketing hire becomes an engineer: the first leg of
`docs/evidence/19-lifecycle-role-change-round-trip.txt`, GAM's own output left out):

```
t+0:00  == role change for jmbeki@tjcollins.dev: marketing (department Marketing) -> Engineer (OU /Staff, groups: all-staff engineering, device: mac)
t+0:02  ok: in /Staff
t+0:04  ok: member of all-staff@tjcollins.dev (in the Engineer role)
t+0:06  changed: removed from marketing@tjcollins.dev
t+0:07  changed: added to engineering@tjcollins.dev
t+0:12  changed: title Software Engineer, department Engineering
t+0:14  changed: vm2-fleet.local removed from role-marketing
t+0:15  changed: vm2-fleet.local added to role-engineer
t+0:15  == verify jmbeki@tjcollins.dev
t+0:15    OU: /Staff (role: /Staff)
t+0:18    title: Software Engineer; department: Engineering; manager: aengineer@tjcollins.dev
t+0:20    group all-staff@tjcollins.dev: member
t+0:22    group engineering@tjcollins.dev: member
t+0:25    Fleet host Z597CMKJ30: labels role-engineer
t+0:26  == 0 failed
```

A one-off grant shows as `ok: kept <group> (not in the catalog: a one-off grant; review it, or
rerun with -S to remove it)`. A second run prints `ok:` on every line.

## 2. Verify

```bash
lifecycle/change-role.sh jmbeki engineer
lifecycle/audit-access.sh
```

The repeat changes nothing; the audit shows the account matching its new role. On the Mac,
`sudo scripts/mac-verify.sh engineer` judges the engineer's apps and tooling once the policy has run.
A transfer the other way, Engineer to Marketing, with the role's app arriving on the Mac and single
sign-on to the Fleet console refused afterwards, is section 4 of
`docs/evidence/17-lifecycle-one-hire-arc.txt` and the two images `18-one-hire-2-transferred.png`
and `18-one-hire-3-sso-follows-group.png` beside it.

## Related changes

- A rehire: `gam unsuspend user <user>`, then this runbook; `onboard.sh` refuses an offboarded account on purpose.
- A device change inside the same role: `lifecycle/onboard.sh -d <new device> <role> First Last` maps the new one; the old one is reclaimed by hand from the Fleet host page or with `gam update cros`.

## Problems hit

- **A role change does not reactivate.** An account suspended by an administrator stays suspended
  through a role change; the run says so. Reactivation is a separate, deliberate command.
- **The catalog decides what is removed.** The first design removed every group not in the new
  role; the exceptions rule replaced it after thinking through transfers in a tenant where one-off
  grants exist. The strict option keeps the other behavior available where a policy wants it.
- **One failed read became four findings.** A run of `lifecycle/audit-access.sh` reported an
  offboarded account as suspended outside `/Offboarded`, in the wrong OU, and missing both of its
  role's groups. Nothing had changed: one directory read had come back empty, and the script
  judged the empty OU as if it were the account's state. The run eight minutes earlier and the
  live directory both showed the account where it belonged. The audit now reads each account
  once, retries an empty read, and reports an account it cannot read as not read, without judging
  it; the run then exits non-zero. Tested with a wrapper that makes one read fail (recovers) and
  every read fail (one "not read" line, no findings).
