# Security policy

Plasma Fusion installs parts that run with privileges or guard the session: the charge-limit
helper (`/usr/libexec/plasma-fusion/plasma-fusion-charge-limit`, run through pkexec with the
polkit action `org.plasmafusion.charge-limit`), the lock screen shell, the login check that switches
version-bound parts off after a Plasma update, the boot splash installer (run as root) and the
user services (power tiers, app icons).

## Reporting a vulnerability

Please report security problems privately: on GitHub, open the repository's **Security** tab and
choose **Report a vulnerability**. Include what you found, how to reproduce it (Fedora and Plasma
versions, `rpm -q plasma-fusion`, laptop or tablet posture) and its effect.

Do not open a public issue for a security problem. Reports are read by the maintainer, a single
person: expect an answer within a week. Fixes are made on `main`; there is no bounty.

## Supported versions

Only the current `main` branch and the packages built from it. Problems in KDE Plasma itself
belong to KDE: https://kde.org/info/security/
