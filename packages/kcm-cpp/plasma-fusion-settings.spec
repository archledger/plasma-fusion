# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Built in the Fedora 44 container of tools/container (Plasma 6.7.5, KF 6.30, Qt 6.11.2) by
# packages/kcm-cpp/build-rpm.sh; the source tarball is made from this directory.

Name:           plasma-fusion-settings
Version:        1.0.0
Release:        4%{?dist}
Summary:        Plasma Fusion page for System Settings
License:        GPL-2.0-or-later AND CC-BY-SA-4.0
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  extra-cmake-modules
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  kf6-rpm-macros
BuildRequires:  cmake(Qt6Core)
BuildRequires:  cmake(Qt6Gui)
BuildRequires:  cmake(Qt6DBus)
BuildRequires:  cmake(Qt6Qml)
BuildRequires:  cmake(Qt6Quick)
BuildRequires:  cmake(KF6Config)
BuildRequires:  cmake(KF6CoreAddons)
BuildRequires:  cmake(KF6I18n)
BuildRequires:  cmake(KF6KCMUtils)

# The page runs inside System Settings and uses plasma-apply-lookandfeel and
# plasma-apply-colorscheme (plasma-workspace).
Requires:       plasma-systemsettings
Requires:       plasma-workspace
Requires:       kf6-kirigami
Requires:       kf6-kcmutils
Requires:       qt6-qtdeclarative
# Owns the hicolor icon directories the logo is installed into.
Requires:       hicolor-icon-theme

%description
The Appearance page of the Plasma Fusion desktop as a System Settings module
(Appearance & Style > Plasma Fusion): Light, Dark or Follow sunset style, the
accent color, the window-button layout of the Plasma Fusion window decoration,
dock magnification, the global menu in the top bar and the Overview hot corner;
snap layouts on hold or hover, the glass level, high contrast, reduced motion,
the top bar next to windows and on every screen, desktop icons, what dragging
files does, the battery saving at 10 %, tablet mode, and two ways to start over
(the previous desktop look, a fresh Plasma Fusion layout). Plasma Fusion itself
(Global Themes, dock, top bar, decoration) is installed separately.

%prep
%autosetup

%build
# rcc stamps every QML file of the page with SOURCE_DATE_EPOCH (the %%changelog date), and Qt's
# QML disk cache (~/.cache/systemsettings/qmlcache, ~/.cache/kcmshell6/qmlcache) reuses a
# compiled file whose source time stamp is unchanged. Two builds from the same day would share
# the stamp, and an update would keep showing the previous page. The stamp is derived from the
# sources instead: the same sources give the same stamp (the build stays reproducible), any
# change gives a new one.
export SOURCE_DATE_EPOCH=$(( 1700000000 + 0x$(cat CMakeLists.txt src/CMakeLists.txt src/*.h src/*.cpp src/*.json src/ui/*.qml common/*.qml | sha256sum | cut -c1-6) ))
export QT_RCC_SOURCE_DATE_OVERRIDE=$SOURCE_DATE_EPOCH
echo "QML time stamp: $SOURCE_DATE_EPOCH"
%cmake_kf6
%cmake_build

%install
%cmake_install

%files
%license LICENSES/GPL-2.0-or-later.txt LICENSES/CC-BY-SA-4.0.txt
%{_kf6_qtplugindir}/plasma/kcms/systemsettings/kcm_plasmafusion.so
%{_kf6_datadir}/applications/kcm_plasmafusion.desktop
%{_kf6_datadir}/icons/hicolor/scalable/apps/plasmafusion-logo.svg

%changelog
* Wed Sep 30 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 1.0.0-4
- Add snap layouts on hold or hover, the glass level (Full, Reduced, Solid),
  high contrast colors, reduce motion, the magnified dock icon size, a solid
  top bar next to windows, a top bar on every screen, desktop icons and their
  size, what dragging files does, lighter visuals at 10 % battery and a Tablet
  section
- Add "Restore my previous desktop" and "Reset Fusion layout", which gives the
  new widgets the keyboard shortcuts of the old ones
- Follow the user's font size with the shared Plasma Fusion metrics

* Tue Sep 29 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 1.0.0-3
- Keep a window-button choice applied just after Follow sunset when Plasma
  switches the Global Theme
- Keep a pending dock or top-bar switch change when the Plasma shell restarts,
  and drop one that could not be applied
- Keep other Overview screen edges when the hot corner is changed
- Move the keyboard focus with the arrow keys in the window-button control and
  show a focus ring around the chosen segment
- Make the From wallpaper pill as wide as on the board

* Tue Sep 29 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 1.0.0-2
- Show a new error after the previous error message was closed
- Show the settings in effect after an Apply that failed
- Space the switch rows 41 px apart as on the board
- Wrap the style cards and shrink the page in narrow windows
- Require hicolor-icon-theme
- Stamp the page's QML with a time derived from the sources, so an update is not
  hidden by Qt's QML disk cache

* Tue Sep 29 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 1.0.0-1
- First package
