# Security policy

camwatch probes the networks it runs on and keeps camera passwords. A hole in
it can expose a home's cameras, so a report must reach the maintainer before it
reaches anyone else.

## Report a vulnerability

Use GitHub's private advisory form:
**[Report a vulnerability](https://github.com/mfozmen/camwatch/security/advisories/new)**.
It is private to you and the maintainer. Never open a public issue or pull
request for a security problem, and never put a real camera's address, name or
picture in a report.

Include what you can: the release version (`camwatch-X.Y.Z-…` in the file name,
or the version the app reports under **Check for updates**), the platform, the
steps, and what an attacker gains. A proof of concept against a fake camera on
127.0.0.1 is welcome; one against someone else's network is not.

## What to expect

- An acknowledgement within 7 days.
- A fix, or a reason there will be none, within 90 days of the report; sooner
  for anything that leaks a password or sends traffic off the local network.
- Credit in the release notes when the fix ships, unless you prefer none.
- The advisory is published once a fixed release is out.

## Scope

In scope:

- the app on every platform it ships for (Android and Windows), including how
  it stores passwords and what it sends on the network;
- the release files on the
  [releases page](https://github.com/mfozmen/camwatch/releases) and how they
  are built and signed;
- the workflows under `.github/`.

Out of scope: the cameras themselves, and findings camwatch reports about them
by design.

## Supported versions

Only the latest release is supported. A fix ships as a new release; there are
no backports.
