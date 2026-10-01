# Your company Mac

The Mac you were handed is enrolled in device management before you ever log in. This is what
that means for you, and the one thing to do yourself.

## What is already set up

- **Security settings** you cannot turn off: a passcode of at least eight characters with a short
  idle lock, the disk encrypted with FileVault (the recovery key is held by IT, so a forgotten
  password is recoverable without losing files), no guest account, and a few restrictions such as
  iCloud Desktop and Documents sync being off, so company files stay on company systems.
- **Apps** arrive on their own within about an hour of the Mac being assigned to you: Google Chrome
  and Slack on every Mac, plus the apps for your role (Visual Studio Code for engineers, Zoom for
  marketing). If one is missing after an hour, it is on its way; after a day, tell IT.
- **Chrome** signs in to the company's browser management when you sign in with your work account,
  which applies the company's browser settings.

## The one thing to do yourself

At your first login, open Terminal and run the setup script IT points you to:

```bash
./mac-onboard.sh <your role>
```

It asks for your password once. For engineers it installs Homebrew and the command-line developer
tools; for everyone it sets a few preferences (file extensions shown, the Finder path and status
bars, new documents saved locally rather than to iCloud). Running it again does nothing.

## What the company can see and do

Through the management agent the company can see the Mac's hardware, operating system version,
installed applications, and whether it meets its security checks; it can install or update apps,
run maintenance scripts, and, if the Mac is lost or when you leave, lock it with a PIN or erase it.
It does not read your files or your browsing. Lock and erase are only used for a lost device or a
departure.

## Help

If the Mac asks you to log out to turn on FileVault, do it; that is the encryption step. If you see
a locked screen with a PIN prompt and you did not expect it, contact IT. For anything else, ask
IT or your manager.
