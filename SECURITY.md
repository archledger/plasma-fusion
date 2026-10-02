# Security policy

Plasma Fusion installs parts that run with privileges or guard the session: the charge-limit
helper (`/usr/libexec/plasma-fusion/plasma-fusion-charge-limit`, run through pkexec with the
polkit action `org.plasmafusion.charge-limit`), the lock screen shell, the login check that switches
version-bound parts off after a Plasma update, the boot splash installer (run as root) and the
user services (power tiers, app icons). What users can and cannot expect from them, and why, is in
the security assurance case: [`docs/SECURITY-ASSURANCE.md`](docs/SECURITY-ASSURANCE.md).

## Reporting a vulnerability

Please report security problems privately: on GitHub, open the repository's **Security** tab and
choose **Report a vulnerability**. Include what you found, how to reproduce it (Fedora and Plasma
versions, `rpm -q plasma-fusion`, laptop or tablet posture) and its effect.

Do not open a public issue for a security problem. Reports are read by the maintainer, a single
person: expect an answer within a week. Fixes are made on `main`; there is no bounty.

## How a report is handled

1. **Acknowledge.** The maintainer answers in the private report within a week.
2. **Triage.** The maintainer reproduces the problem on the tested platform (Fedora 44, Plasma
   6.7.5) and decides whether it is a vulnerability in Plasma Fusion. A problem in KDE's or the
   distribution's code is passed on to them, with the reporter's agreement
   (https://kde.org/info/security/). The reporter hears the result and how severe it is judged.
3. **Fix.** The fix is prepared privately in the report's temporary fork, with a test that fails
   without it where one can be written, and goes to `main` through the usual checks. The maintainer
   tells the reporter when to expect it and agrees the publication date with them.
4. **Publish.** A GitHub security advisory describes the problem, the affected versions and the
   fix, with a CVE identifier where the problem affects users. Advisories are listed in the
   repository's **Security** tab.
5. **Credit.** The advisory names the reporter, and so does the text of the fix's commit message
   or pull request, unless the reporter asks to stay anonymous. (Commit messages carry no
   trailers besides `Signed-off-by`, so the credit is in the text.)

## Supported versions

Only the current `main` branch and the packages built from it. There are no releases yet; this
section will say which releases get fixes once there are some. Problems in KDE Plasma itself
belong to KDE: https://kde.org/info/security/
