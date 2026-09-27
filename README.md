# Endpoint & Identity Lab

**A personal lab that reproduces an employee lifecycle across Google Workspace, Apple MDM, and
ChromeOS on my own devices, documented as runbooks and decision notes.**

An account is created in Google Workspace; organizational unit and group membership grant
access; the user signs in to a third-party app through SSO; a Mac or iPad is enrolled in MDM and
brought to a baseline of configuration profiles; offboarding reverses every step (suspend, revoke
sessions, unenroll or wipe, transfer data). The devices are a MacBook Pro and an iPad enrolled
in Jamf Now, two macOS virtual machines on the MacBook managed by self-hosted Fleet with
configuration shipped as code, and a ChromeOS Flex virtual machine enrolled to the Workspace
tenant. Every managed Mac other than the MacBook is a VM, stated here so the scale is not
misread. Runbooks and decisions sit at the repository root; design, demo script, and
redacted evidence are under `docs/`. Shell convention: macOS scripts are zsh; GAM scripts are
bash 3.2-compatible and shellcheck-clean.

> **Build status (updated as the repository grows):** repository scaffold only. No tenant,
> MDM, or device is enrolled yet. Nothing here claims more than the tree contains at the time
> of the commit you are reading.
