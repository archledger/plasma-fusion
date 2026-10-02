<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->
# plasma-workspace patches

Fedora's plasma-workspace, rebuilt with a fix Plasma Fusion needs before KDE ships it. The packages
replace Fedora's on the machines that install them; nothing else in Plasma Fusion depends on them.

| Patch | What | Upstream |
|---|---|---|
| `0001-appmenu-guard-search-results.patch` | The global menu's Search keeps the matching actions of the app's menu. When the app rebuilds a submenu (Google Chrome's History and Profiles do), the menu importer deletes them, and the next key typed in the field crashes plasmashell. The patch holds the results in `QPointer`s and skips deleted ones. | KDE [bug 526561](https://bugs.kde.org/show_bug.cgi?id=526561) (filed 2026-10-02 with the steps and the backtrace; the patch itself was not attached) |
| `0002-appmenu-mark-guarded-search.patch` | Plasma Fusion only: names the Search action `appmenu-guarded` instead of `appmenu`. The top bar hides the entry while it is named `appmenu` (the unfixed applet, docs/parts/shell-topbar.md `menuSearch`), so this build shows it again, and a Fedora update that replaces it hides it again. | Never |

## Build

```
packaging/patches/plasma-workspace/build.sh OUT_DIR [VERSION-RELEASE [FEDORA]]
```

In a `registry.fedoraproject.org/fedora:FEDORA` container (podman): Fedora's source RPM of
`VERSION-RELEASE` (default: the plasma-workspace installed on the machine), the patches added as
`Patch9001` and up after Fedora's own, `Release` suffixed `.pf1` with a changelog entry, `rpmbuild -ba`.
OUT_DIR gets every binary RPM, the source RPM, `rpmbuild.log` and `SHA256SUMS`.

Install the rebuilt subpackages that are installed now (the others need not come along), in one
transaction:

```
cd OUT_DIR && sha256sum -c SHA256SUMS
sudo dnf install $(for f in *.rpm; do case $f in *.src.rpm) continue ;; esac
    rpm -q "$(rpm -qp --qf '%{NAME}' "$f")" >/dev/null && echo "./$f"; done)
```

Then restart plasmashell (`systemctl --user restart plasma-plasmashell`) or log out and in.

`.pf1` sorts after Fedora's `1.fc44` and before its next release (`2.fc44`, or a new version), so
dnf replaces the rebuild with Fedora's next update without asking. That update brings the crash
back until it carries the fix, and the top bar hides Search again at the next start of plasmashell
(patch 0002). Rebuild for the new Fedora release with `build.sh` (patch 0001 must still apply; when
it does not, KDE has changed the code: check whether the fix is in).

## When to drop

When Fedora's plasma-workspace carries KDE's fix: delete both patches and this directory, and let
Fedora's update replace the rebuild. The top bar keeps Search hidden for the unpatched name until its
`menuSearch` check is changed to follow the fixed versions.
