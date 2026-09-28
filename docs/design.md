# Design

The lab reproduces an employee lifecycle across Google Workspace, Apple MDM, and ChromeOS on a handful of devices. This document holds the design, the decisions behind it, and what would change at a few hundred users. Per-platform settings are in `workspace/tenant-settings.md`, `mdm/blueprints.md`, and `chromeos/policies.md`; procedures are in `runbooks/`; the reasoning behind each larger choice is in `decisions/`.

## Lifecycle flow

(to be written)

## Identity and access

**Context-Aware Access, intended policy.** Context-Aware Access is not available on the Business Plus edition this tenant runs, so the policy is designed here and not enforced. The intent: access to Gmail, Drive, and the Admin console is conditioned on device state as reported by endpoint verification or MDM, not only on who is signing in. Staff reach Gmail and Drive only from a device that is MDM-enrolled, encrypted, and on a current OS; contractors reach Drive from any device but cannot download or sync unless the device is managed; the Admin console is reachable only from a managed device. Each rule is an access level bound to an OU, which is why the OU structure separates staff from contractors: the policy attaches to the tree, not to people. What exists today instead is the combination of enforced 2-Step Verification, MDM enrollment, and a shorter session length for contractors. The same idea is built outside Google in a later phase with Cloudflare Access in front of the Fleet console, where a device-posture rule gates an internal application.

## Device management: two layers, one owner per platform

Every device that holds a Workspace account sits under Google's account layer: the device appears in the inventory, a screen lock can be required, and the account and its data can be wiped, all without a profile or an agent. That is Google's Basic mobile management, and it applies regardless of what else manages the device. The device layer, enrollment, configuration profiles, restrictions, encryption, apps, and a full wipe, has exactly one owner per device, and choosing that owner is the design decision. Setting Google's mobile management to Advanced for a platform makes Google that owner for it.

The lab splits by ownership class, which is how most Workspace shops split. Company-owned Apple hardware is managed by an Apple MDM: Jamf Now for the MacBook and the iPad, Fleet for the virtual machines. Google stays Basic on iOS so that it never competes with Jamf Now for the iPad, and Advanced on Android, where nothing else in the lab could own the platform. The production posture the lab does not build is the other half of the common shop: personal phones on both platforms under Google Advanced, a work profile on Android and Google's MDM profile on iOS through an Apple push certificate held in the Workspace console, with the Apple MDM reserved for company-owned hardware. A cross-platform product such as Workspace ONE or Intune is the alternative, one console for every ownership class and platform, with Google left at the account layer; it is the default in Microsoft-licensed environments and the exception in Google ones. An optional late step moves the iPad from Jamf Now to Google Advanced management as a user-owned device to show that migration; if it happens, the runbook and the inventory evidence say so.

## What changes at 500 users

(to be written)
