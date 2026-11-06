<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# NT01 baseline

## Source and runtime

| Input | Exact identity |
|---|---|
| Upstream KWin 6.7.5 | `ab7df7ccb7c6af20f4b279cd6220f7cd3d2267d7` |
| Requested-geometry patch SHA-256 | `6af9baf2bdbf1370fffd1b45bbe3c066c4379c90ef80ba96ea92642f8cc4060b` |
| Offscreen-opacity patch SHA-256 | `c97b376be0d5267d6cd48e0aa99be41df1560488182988480632ab91b1ec7bcf` |
| Combined Git tree | `4200ddd1810a285dfc26d8dfa21296a11df180d4` |
| Installed `.pf2` source RPM SHA-256 | `e17005f70492e6041bce0bdeb2abc35ace9b6a6e5b212c4c178635dfc403ed9f` |
| Installed executable SHA-256 | `a20eadeffc5448f1a0ea8a40194bdc447c797ac1655c9757a6459db61e7a67ee` |
| Installed library SHA-256 | `0ae605f5743b88b418d82c7332d318f4fe6cf19c02b136faa1bb12468baafe9a` |
| Builder image | `8e21595bc487be7fec1bed0acaf240e20846b44c213cf0256e11cea8d8d78eae` |

The ThinkPad worktree is `~/Projects/plasma-fusion-kwin-issue115/source`, branch
`native/issue115-ownership-20261102`. At capture its HEAD was upstream with the two patches staged;
the same baseline was then sealed as signed commit `19216d29517ac8fb8a1e30891083d22d63e2570c`.
All 3,248 tracked baseline files match the source used to build the installed `.pf2` RPM.
Later implementation commits are recorded in `todo.md`; compare against this sealed baseline,
not an assumed current HEAD. The older private ownership experiments are not in this baseline.

The active desktop remains the installed `.pf2` build. Neither this source worktree nor the
new `build/` directory replaces its files or attaches to its session bus.

## Build profile

The separate native build directory is `~/Projects/plasma-fusion-kwin-issue115/build`.
Its configuration uses the pinned image, Ninja, the existing `.pf2` C/C++ and linker flags,
`CMAKE_BUILD_TYPE=release`, `/usr` as the container install prefix, and tests, X11 and KCMs enabled.
The copied package-note linker spec also requires the original `RPM_ARCH`, `RPM_PACKAGE_NAME`,
`RPM_PACKAGE_VERSION` and `RPM_PACKAGE_RELEASE` environment. Omitting those caused the first
configuration attempt to fail; supplying the recorded RPM context fixed configuration without
changing compiler flags. Scratch storage is disk-backed.

Configuration passes; CTest registers 166 tests, including all 11 selected baseline suites.
No fresh native compilation or native-suite run is claimed for this new build directory. The
already completed `.pf2` run passed 448 QtTest results in those 11 suites using the packaged
library. Exact source equivalence makes those receipts applicable as the starting baseline;
changed native candidates require new tests.

The reproducible configure arguments, environment, full source hash map and test registration
are retained under `~/Projects/plasma-fusion-kwin-issue115/evidence/` and the shared NT01 evidence.

## Persistence boundary experiment

`nt01-persistence-probe.sh` runs the real Plasma `ConfigFile` API on an isolated bus and HOME.
In the writable case, `writeEntry()` returns `true` and a fresh file read finds A. In the
read-only case, the same call still returns `true`, but the file retains P. This demonstrates
that the write reply alone cannot acknowledge a persisted floating snapshot.

The first attempt stopped before the experiment because a guessed package name was absent.
The corrected recipe queries ownership of the actual KConfig library. The corrected run has
driver/probe/shutdown status zero and no remaining session processes. It is a persistence-boundary
test, not an automatic-tiling or power-loss durability test.

Source grounding: Plasma Workspace v6.7.5 `shell/scripting/configgroup.cpp`,
`shell/scripting/scriptengine_v1.cpp` and `shell/shellcorona.cpp`; KConfig v6.31.0
`src/core/kconfig.cpp`. The configuration wrapper does not return the underlying sync result.
The proposed admission contract therefore requires an independent readback and idle writer,
in addition to the ordinary write reply.
