<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Optional KWin backport

Fedora 44's KWin 6.7.5, rebuilt with a scripting property that KDE declined upstream: the merge
request was closed without merging on 2026-10-26. It is a downstream patch, maintained here for
Fedora 44's KWin 6.7.5 only. Stock KWin remains supported. These packages are separate from Plasma
Fusion and are never installed by its installer. Plasma Fusion does not publish them: they exist
only where someone builds them with the script below. The property exists only where this patch is
installed, so consumers must detect it at runtime.

| Patch | What it provides | Upstream | When to drop |
|---|---|---|---|
| `0001-window-expose-requested-geometry.patch` | Read-only `Window.requestedGeometry` and `requestedGeometryChanged`, so scripts can distinguish the committed frame from geometry KWin has requested. | KDE [MR !10225](https://invent.kde.org/plasma/kwin/-/merge_requests/10225), proposed commit `3fd6cdb85cc2b7d562fbb403c035709462c0068a`; [bug 527821](https://bugs.kde.org/show_bug.cgi?id=527821). Closed without merging on 2026-10-26: upstream KWin will not take this change. | When Fedora's KWin provides the same information through an API of its own (update the consumers with it), or when the patch no longer applies to Fedora 44's KWin. There is no upstream version to follow. |

This adds an observable property; it does not change how KWin configures or tiles windows. It does
not enable automatic tiling or solve its remaining lifecycle requirements. The placement-script
consumer and a patched CI lane belong to separate changes. No patched RPM repository is published
by this change.

## Backport scope

The patch carries the three integration tests from the proposed commit unchanged. KWin 6.7.5
handles xdg-shell commits in `XdgSurfaceWindow`, shared with picture-in-picture windows. The
backport emits the notification at the end of that shared handler instead of the newer per-role
handlers. It retains 6.7.5's existing geometry synchronization rules and documents that distinction.

The last-notified rectangle is kept outside `Window` and removed when the window is destroyed.
This avoids adding a member to an exported class that stock-built plugins access through inline
functions. The post-mapping notification checks that a synchronous callback has not destroyed or
deleted the window. Two additional tests cover mapping destruction and reentrant movement.

Notifications sent during a move or resize have the same limit as KWin's existing geometry signals
there: a native handler must not destroy the window synchronously. Stock 6.7.5 crashes the same way,
and earlier, when a `frameGeometryAboutToChange` handler does this during `Tile::manage`. Deferring
the destruction to a queued handler passes under Memcheck with both signals. The post-mapping
notification is the exception and has a guard: stock 6.7.5 ends that commit handler with the
mapping, so any access to the window after it would be new.

Read `requestedGeometry` by its `x`, `y`, `width` and `height`, not JavaScript object identity.
An empty size asks the client to choose its size. Equality with `frameGeometry` is useful for
settled xdg-shell windows; it is not a universal completion flag for every window type.

## Build

Requires Podman and access to Fedora 44's package repositories. The default source version is the
installed `kwin` package; specify it when building from another system:

```sh
packaging/patches/kwin/build.sh build/kwin-rpms 6.7.5-1.fc44
```

The output directory must be empty. Only `6.7.5-N.fc44` source packages are accepted; newer KWin
series need a reviewed backport rather than an automatic rebuild. Builds use a Fedora 44 container,
four CPUs and an 8 GiB memory limit. The builder:

1. Runs the offline packaging checks, then downloads Fedora's exact source RPM and retains it as
   `fedora-kwin-*.src.rpm`.
2. Adds `Patch9001`, preserving Fedora's existing patches and `%autosetup -p1`.
3. Appends `.pf1` to `Release`, adds a changelog entry, installs build dependencies inside the
   container and runs `rpmbuild -ba` without disabling Fedora's checks.
4. Copies the binary RPMs, rebuilt source RPM, prepared spec and logs to the output directory.
   `SHA256SUMS` covers every RPM, including the original source package.

Fedora's current spec has no `%check` section. A successful RPM build alone therefore does not
establish that the new native tests passed. Run those against the prepared source with
`BUILD_TESTING=ON` before distributing packages. Keep the test logs with the exact patch and source
RPM hashes.

## Installation and rollback

Building does not install anything. Try the packages in a disposable VM first. To install them,
check the hashes and install the rebuilt counterparts of the KWin subpackages installed now, in one
DNF transaction. The other subpackages need not come along, and neither source package belongs in
it:

```sh
cd OUT_DIR && sha256sum -c SHA256SUMS
sudo dnf install $(for f in *.rpm; do case $f in *.src.rpm) continue ;; esac
    rpm -q "$(rpm -qp --qf '%{NAME}' "$f")" >/dev/null && echo "./$f"; done)
```

The packages are not signed, so DNF reports that it skipped their OpenPGP checks. `SHA256SUMS`,
written by the build, is the integrity check. Log out and back in to start the new compositor; do
not replace a running desktop's KWin process for a test.

`6.7.5-1.fc44.pf1` sorts after `6.7.5-1.fc44` and before any later Fedora build (`6.7.5-2.fc44`,
`6.7.5-1.fc44.1` or a new version), so Fedora's next update replaces it normally and the property
disappears with it. To roll back earlier, return the installed subpackages of KWin's source package
to Fedora's build, review the transaction, and log out and back in:

```sh
sudo dnf distro-sync $(rpm -qa --qf '%{NAME} %{SOURCERPM}\n' | awk '$2 ~ /^kwin-[0-9]/ {print $1}')
```

Keep stock KWin's capabilities as the fallback; consumers must detect the property at runtime
rather than infer it from the package version.

## Checks

```sh
python3 -m unittest discover -s packaging/patches/kwin -v
shellcheck packaging/patches/kwin/*.sh
ruff check packaging/patches/kwin
```

The offline suite checks the spec transformation, preserved Fedora patches and changelog,
incompatible-spec rejection, supported version bounds and output-directory preservation. The
backported native tests cover delayed tile/untile commits, notification ordering on X11 and
settling to a client-selected size. Run `testTiles` and `testXdgShellWindow` on the built KWin;
also run the move/resize, quick-tiling, internal-window, maximize and placement suites.

Run `testRequestedGeometryAfterMappingDestroysWindow` under a memory checker as well. A normal
QtTest pass alone does not detect a read from the already-freed window when no signal is emitted.

For the same-version backport, compare debug builds of stock and patched KWin made with matching
architecture, configuration and dependencies. `check-abi.sh` requires GDB and checks the size and
member offsets of six window classes; it does not claim to check the whole KWin ABI:

```sh
packaging/patches/kwin/check-abi.sh STOCK_BUILD/bin/libkwin.so PATCHED_BUILD/bin/libkwin.so
```
