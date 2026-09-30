# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Built in the Fedora 44 container of tools/container (Plasma 6.7.5, KF 6.30, Qt 6.11.2) by
# packages/kcm-cpp/build-rpm.sh; the source tarball is made from this directory.

Name:           plasma-fusion-settings
Version:        1.0.0
Release:        2%{?dist}
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
dock magnification, the global menu in the top bar and the Overview hot corner.
Plasma Fusion itself (Global Themes, dock, top bar, decoration) is installed
separately.

%prep
%autosetup

%build
# rcc stamps every QML file of the page with SOURCE_DATE_EPOCH (the %%changelog date), and Qt's
# QML disk cache (~/.cache/systemsettings/qmlcache, ~/.cache/kcmshell6/qmlcache) reuses a
# compiled file whose source time stamp is unchanged. Two builds from the same day would share
# the stamp, and an update would keep showing the previous page. The stamp is derived from the
# sources instead: the same sources give the same stamp (the build stays reproducible), any
# change gives a new one.
export SOURCE_DATE_EPOCH=$(( 1700000000 + 0x$(cat CMakeLists.txt src/CMakeLists.txt src/*.h src/*.cpp src/*.json src/ui/*.qml | sha256sum | cut -c1-6) ))
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
