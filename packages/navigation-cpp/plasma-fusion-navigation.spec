# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Built by packages/navigation-cpp/tools/build-rpm.sh in the localhost/plasma-fusion-build:f44-6.7.5
# container (Fedora 44, KWin 6.7.5, Qt 6.11). Derived from Plasma Mobile's task switcher effect
# (plasma-mobile v6.7.5, GPL-2.0-or-later); see README.md.

Name:           plasma-fusion-navigation
Version:        0.1
Release:        6%{?dist}
Summary:        Plasma Fusion tablet navigation gestures for KWin

License:        GPL-2.0-or-later
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake >= 3.22
BuildRequires:  extra-cmake-modules
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  cmake(KWin) >= 6.7
# KWinConfig.cmake looks for epoxy, libdrm and Vulkan, which kwin-devel does not pull in.
BuildRequires:  pkgconfig(epoxy)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(vulkan)
BuildRequires:  cmake(PlasmaActivities)
BuildRequires:  cmake(Qt6Core)
BuildRequires:  cmake(Qt6DBus)
BuildRequires:  cmake(Qt6Gui)
BuildRequires:  cmake(Qt6Quick)
BuildRequires:  cmake(Qt6Qml)
BuildRequires:  cmake(KF6ConfigWidgets)
BuildRequires:  cmake(KF6GlobalAccel)
BuildRequires:  cmake(KF6I18n)
BuildRequires:  cmake(KF6CoreAddons)
BuildRequires:  cmake(KF6WindowSystem)
BuildRequires:  cmake(KF6Package)
BuildRequires:  qt6-rpm-macros

# Built against KWin 6.7.5's own (not stable) library API. The Plasma Fusion login check turns the
# effect off when the installed KWin differs from the tested version; rebuild and re-test after
# every KWin update. No exact version pin, so Fedora updates are never blocked.
Requires:       kwin%{?_isa} >= 6.7
Enhances:       kwin

%description
Plasma Fusion's tablet navigation: in tablet posture, swipe up from the bottom
edge to go home, swipe up a little to show the dock, swipe up and hold for the
app switcher (one card per app, swipe a card up to close it), or swipe along
the bottom edge for the previous app. The app follows the finger. A key press
on a hardware keyboard hides the on-screen keyboard. Laptop posture keeps
KWin's own edges. Derived from Plasma Mobile's task switcher.

%prep
%autosetup -n %{name}-%{version}

%build
%cmake -G Ninja -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
%cmake_build

%install
%cmake_install
# Qt's QML disk cache (~/.cache/kwin/qmlcache) reuses a compiled file while the source's time stamp
# is unchanged, and rpm clamps every time stamp to the %%changelog date: two releases built on one
# day ship equal times, and KWin kept running the previous release's effect QML after an update
# (TaskSwitcherHelpers.qml of an earlier release still ran under 0.1-4 on 2026-10-02). Each QML/JS file gets
# a time derived from its content instead, before the clamp date so rpm keeps it: the same file
# gives the same time (reproducible), any change a new one.
find %{buildroot}%{_datadir}/kwin/effects/plasmafusion_navigation %{buildroot}%{_qt6_qmldir}/org/plasmafusion/navigation \
  -type f \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' -o -name qmldir \) -print0 |
  while IFS= read -r -d '' f; do
    touch -h -d "@$(( ${SOURCE_DATE_EPOCH:-1700000000} - 1 - 0x$(sha256sum "$f" | cut -c1-6) ))" "$f"
  done

%files
%license LICENSES/GPL-2.0-or-later.txt
%doc README.md
%{_datadir}/kwin/effects/plasmafusion_navigation/
%{_qt6_qmldir}/org/plasmafusion/navigation/

%changelog
* Fri Oct 02 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 0.1-6
- An app picked in the task switcher keeps its half of a split, and the app in
  the other half comes up with it

* Fri Oct 02 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 0.1-5
- Give each QML file a time stamp from its content, so an update replaces the
  effect code that KWin's QML cache kept from an earlier release of the same day

* Thu Oct 01 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 0.1-4
- The home gesture closes an open shell sheet (launcher, Notification Centre)
- No error and no stray app activation for a gesture with no app open

* Thu Oct 01 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 0.1-3
- A dock revealed over an app hides again on the next touch outside it or once an
  app opened from it is active

* Thu Oct 01 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 0.1-2
- Take Plasma Mobile 6.8's gesture velocity fix (the filter starts again with
  every gesture)
- A pen press and hold over the shell opens the shell's own menus
- A quick pen tap on the home handle shows the dock

* Thu Oct 01 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 0.1-1
- First build: Plasma Mobile 6.7.5 task switcher renamed and ported to Plasma Fusion,
  with the dock on a short swipe, retuned gesture distances, a hardware-key rule for
  the on-screen keyboard, the Plasma Fusion card look and a KWin version guard;
  a gesture lock; the pen acts like a finger in tablet posture, with press and
  hold for a right click
