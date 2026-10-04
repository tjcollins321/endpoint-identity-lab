<!-- lifecycle/lifecycle-report.py, 2026-10-04, after the day's lifecycle runs: one table joining the Workspace accounts to the company devices they hold, read from GAM and the Fleet API. Read-only; the script prints no clock times. vm1-jamf is in IT custody (mapped to the administrator, no role label) and locked; the Chromebook is in IT custody. -->

| Account | Role | OU | State | Device | Management | Compliance |
|---|---|---|---|---|---|---|
| acontractor@tjcollins.dev | Contractor | /Contractors | active, 2SV off | none (own computer) | | |
| aengineer@tjcollins.dev | Engineer | /Staff | active, 2SV off | none | | |
| csalazar@tjcollins.dev | Sales | /Offboarded | suspended (ADMIN) | none | | |
| jmbeki@tjcollins.dev | Marketing | /Staff | active, 2SV off | Mac vm2-fleet.local (Z597CMKJ30) | Fleet, MDM On (manual), online, role-marketing, unlocked | 5/5 policies pass |
| mreyes@tjcollins.dev | Contractor | /Offboarded | suspended (ADMIN) | none (own computer) | | |
| praman@tjcollins.dev | Engineer | /Offboarded | suspended (ADMIN) | none | | |
| shaddad@tjcollins.dev | Marketing | /Offboarded | suspended (ADMIN) | none | | |
| tj@tjcollins.dev | none | / | active, 2SV on | Mac vm1-jamf.local (ZQGCYXVWFJ) | Fleet, MDM On (manual), offline, no role label, locked | 4/4 policies pass |
| tj@tjcollins.dev | none | / | active, 2SV on | Chromebook Flex-52:54:00:12:34:56 | Workspace, ACTIVE, OU /Devices | user policy follows the user's OU |
