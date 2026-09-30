# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Built by packages/decoration-cpp/tools/build-rpm.sh in the localhost/plasma-fusion-build:f44-6.7.5
# container (Fedora 44, KDecoration 6.7.5, Qt 6.11). The plugin carries its metadata (plasmafusion.json)
# inside the .so; KWin lists it as "Plasma Fusion" (plugin id org.plasmafusion.decoration).

Name:           plasma-fusion-decoration
Version:        1.0
Release:        3%{?dist}
Summary:        Plasma Fusion window decoration for KWin

License:        GPL-2.0-or-later
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake >= 3.22
BuildRequires:  extra-cmake-modules
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  cmake(KDecoration3) >= 6.7
BuildRequires:  cmake(Qt6Core)
BuildRequires:  cmake(Qt6Gui)
BuildRequires:  cmake(Qt6DBus)
BuildRequires:  cmake(KF6CoreAddons)
BuildRequires:  cmake(KF6Config)
BuildRequires:  cmake(KF6ColorScheme)
BuildRequires:  qt6-rpm-macros

# Built and tested against KDecoration 6.7. The plugin links only the public libkdecorations3.so.6
# (the soname dependency is generated), not the private library. Rebuild and re-test it after
# every Plasma feature release (6.8, ...).
Requires:       kdecoration%{?_isa} >= 6.7
Enhances:       kwin

%description
The Plasma Fusion window decoration: a 50 px title bar with the app icon and
a left-aligned title, 28 px round buttons (minimize, maximize, close, and
the other KWin buttons in the same style), 14 px rounded corners with the
window content clipped, a 1 px light edge and soft shadows. Square corners
and no shadow when maximized, square inner corners when tiled. In tablet
mode the title bar and its buttons grow to touch size (44 px hit areas);
screens under 800 px high get 40 px title bars. Button layouts and the
snap-layouts trigger on the maximize button (hold, or also hover) are read
from ~/.config/plasmafusionrc [Decoration].

%prep
%autosetup -n %{name}-%{version}

%build
%cmake -G Ninja -DBUILD_TESTING=OFF -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
%cmake_build

%install
%cmake_install

%files
%license LICENSES/GPL-2.0-or-later.txt
%{_qt6_plugindir}/org.kde.kdecoration3/org.plasmafusion.decoration.so

%changelog
* Wed Sep 30 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 1.0-3
- Snap layouts open on hold by default; SnapLayoutsOnHover=true adds hover
- Touch-sized title bars while KWin reports tablet mode, updated live
- 40 px title bars on screens under 800 px high
- Tooltip "Maximize · hold for snap layouts" on English desktops
- A press that slides off maximize no longer opens the snap layouts
- Tablet hit areas never overlap a neighbouring button
- The light window edge is one device pixel at 150 %, like the shell's hairlines

* Tue Sep 29 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 1.0-2
- Read the animation speed from the cascaded kdeglobals, as KWin does
- Source formatting (KDE clang-format); package description wrapped for rpmlint

* Tue Sep 29 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 1.0-1
- First release: C++ KDecoration3 decoration for Plasma 6.7
