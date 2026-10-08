# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion for Fedora, from one source tarball: the shared part (plasma-fusion: themes,
# widgets, icons, fonts, KWin scripts, setup tools) and the three compiled parts (-decoration,
# -settings, -navigation). Copr builds releases through Packit (.packit.yaml); packaging/build-rpm.sh
# builds snapshots of a working tree (rpmbuild --without compiled: the shared part only). Every
# package records nothing in a home directory: each user runs "plasma-fusion setup" in their Plasma
# session (docs/parts/system.md).
#
# The shared part holds no compiled code but is built for each architecture with the compiled parts
# (rpm builds noarch subpackages of an arched package, not the other way round).

%bcond compiled 1
# Without the compiled parts there is nothing to put in debug packages.
%if %{without compiled}
%global debug_package %{nil}
%endif

Name:           plasma-fusion
Version:        0.3.1
Release:        1%{?dist}
Summary:        Plasma Fusion desktop for KDE Plasma 6 (themes, widgets, icons, fonts)

# Code (QML, JavaScript, shell scripts, KWin scripts, C++): GPL-2.0-or-later.
# Artwork (Plasma style, icons, cursors, window decorations, wallpapers, backgrounds,
# previews): CC-BY-SA-4.0. Fonts (Manrope, Space Grotesk): OFL-1.1.
License:        GPL-2.0-or-later AND CC-BY-SA-4.0 AND OFL-1.1
URL:            https://github.com/archledger/plasma-fusion
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# tools/build.sh renders the artwork: Pillow for the wallpapers and the decoration,
# PySide6 (QtSvg, offscreen) for the wallpaper check and the cursors, NumPy for the boot splash.
BuildRequires:  bash
BuildRequires:  coreutils
BuildRequires:  findutils
BuildRequires:  python3
BuildRequires:  python3-numpy
BuildRequires:  python3-pillow
BuildRequires:  python3-pyside6
# %%check resolves the icon themes' links into Breeze against the installed Breeze.
BuildRequires:  breeze-icon-theme >= 6.30
%if %{with compiled}
BuildRequires:  cmake >= 3.22
BuildRequires:  extra-cmake-modules
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  kf6-rpm-macros
BuildRequires:  qt6-rpm-macros
BuildRequires:  cmake(KWin) >= 6.7
BuildRequires:  cmake(KDecoration3) >= 6.7
BuildRequires:  cmake(PlasmaActivities)
BuildRequires:  pkgconfig(epoxy)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(vulkan)
BuildRequires:  cmake(Qt6Core)
BuildRequires:  cmake(Qt6DBus)
BuildRequires:  cmake(Qt6Gui)
BuildRequires:  cmake(Qt6Qml)
BuildRequires:  cmake(Qt6Quick)
BuildRequires:  cmake(KF6ColorScheme)
BuildRequires:  cmake(KF6Config)
BuildRequires:  cmake(KF6ConfigWidgets)
BuildRequires:  cmake(KF6CoreAddons)
BuildRequires:  cmake(KF6GlobalAccel)
BuildRequires:  cmake(KF6I18n)
BuildRequires:  cmake(KF6KCMUtils)
BuildRequires:  cmake(KF6Package)
BuildRequires:  cmake(KF6WindowSystem)
%endif

# Plasma 6.7 packages the themes plug into (Global Theme, Plasma style, shells, KWin
# switcher/scripts, Aurorae v2 decoration).
Requires:       plasma-workspace >= 6.7
Requires:       plasma-desktop >= 6.7
Requires:       libplasma >= 6.7
Requires:       kwin >= 6.7
Requires:       aurorae >= 6.7
# The quick settings and the snap script run small commands through Plasma's "executable" source.
Requires:       plasma5support >= 6.7
# The icon themes inherit breeze/breeze-dark and link part of their names to Breeze's files.
Requires:       breeze-icon-theme >= 6.30
Requires:       fonts-filesystem
Requires:       kde-filesystem
# tools/device/*.sh and tools/system/*.sh
Requires:       python3
# pkexec for the charge-limit helper
Requires:       polkit
Requires:       /usr/bin/kreadconfig6
Requires:       /usr/bin/kwriteconfig6
Requires:       /usr/bin/busctl
Requires:       /usr/bin/setpriv
# plasma-fusion-app-icons draws each app's own icon on a Fusion tile: Pillow, and QtSvg (what Plasma
# draws icons with) through PySide6 when installed, else rsvg-convert.
Requires:       python3-pillow
Requires:       (librsvg2-tools or python3-pyside6)
Suggests:       python3-pyside6
# The compiled parts of the same build: the window decoration and the settings page by default,
# the tablet gestures for convertibles.
%if %{with compiled}
Recommends:     %{name}-decoration%{?_isa} = %{version}-%{release}
Recommends:     %{name}-settings%{?_isa} = %{version}-%{release}
Suggests:       %{name}-navigation%{?_isa} = %{version}-%{release}
%endif
# The design's Code and Notes apps, the terminal whose theme is included, the login screen
# styled by tools/system/greeter-apply.sh.
Suggests:       kate
Suggests:       marknote
Suggests:       konsole
Suggests:       plasma-login-manager
# The pen menu's note, whiteboard and mark-up tiles open Xournal++. Suggested only: as a weak
# dependency it brings its own (TeX Live, about 300 MB); plasma-fusion setup --pen installs it
# without them.
Suggests:       xournalpp

%description
Plasma Fusion is a desktop for KDE Plasma 6 built from the Plasma Fusion
design concept, in a dark and a light variant: Global Themes with the desktop
layout and splash screen, color schemes, Plasma styles, icon and cursor
themes, Aurorae window decorations, wallpapers, a top bar, launcher, dock and
quick-settings widgets, a window switcher and KWin scripts, a lock-screen
shell, Konsole and Kate/KWrite color themes and the Manrope and Space Grotesk
fonts.

The package installs these for every user. Each user then runs
"plasma-fusion setup" inside their Plasma session to apply the Global Theme
and the settings a Global Theme cannot carry, and "plasma-fusion update" after
later updates. As root, /usr/share/plasma-fusion/tools/system/greeter-apply.sh
styles the Plasma login greeter.

%if %{with compiled}
%package decoration
Summary:        Plasma Fusion window decoration for KWin
License:        GPL-2.0-or-later
Requires:       %{name}%{?_isa} = %{version}-%{release}
# Built and tested against KDecoration 6.7. The plugin links only the public libkdecorations3.so.6
# (the soname dependency is generated), not the private library.
Requires:       kdecoration%{?_isa} >= 6.7
Enhances:       kwin

%description decoration
The Plasma Fusion window decoration: a tall title bar with the app icon and
a left-aligned title, round buttons, rounded corners with the window content
clipped, a thin light edge and soft shadows. Square corners and no shadow when
maximized, square inner corners when tiled. In tablet mode the title bar and
its buttons grow to touch size. Button layouts and the snap-layouts trigger on
the maximize button are set on the Plasma Fusion page of System Settings.

%package settings
Summary:        Plasma Fusion settings page for System Settings
License:        GPL-2.0-or-later AND CC-BY-SA-4.0
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       plasma-systemsettings
Requires:       plasma-workspace
Requires:       kf6-kirigami
Requires:       kf6-kcmutils
Requires:       qt6-qtdeclarative
# Owns the hicolor icon directories the logo is installed into.
Requires:       hicolor-icon-theme

%description settings
The Appearance page of the Plasma Fusion desktop as a System Settings module
(Appearance & Style > Plasma Fusion): Light, Dark or Follow sunset style, the
accent color, the window-button layout of the Plasma Fusion window decoration,
dock magnification, the global menu in the top bar and the Overview hot corner;
snap layouts on hold or hover, the glass level, high contrast, reduced motion,
the top bar next to windows and on every screen, desktop icons, what dragging
files does, the battery saving at 10 %, tablet mode, and two ways to start over
(the previous desktop look, a fresh Plasma Fusion layout).

%package navigation
Summary:        Plasma Fusion tablet navigation gestures (KWin effect)
License:        GPL-2.0-or-later
Requires:       %{name}%{?_isa} = %{version}-%{release}
# Built against KWin's own (not stable) library API. The Plasma Fusion login check turns the
# effect off when the installed KWin differs from the tested version; Copr rebuilds it after every
# KWin update. No exact version pin, so Fedora updates are never blocked.
Requires:       kwin%{?_isa} >= 6.7
Enhances:       kwin

%description navigation
Plasma Fusion's tablet navigation: in tablet posture, swipe up from the bottom
edge to go home, swipe up a little to show the dock, swipe up and hold for the
app switcher (one card per app or split pair, swipe a card up to close it),
or swipe along the bottom edge for the previous app. The app follows the
finger. A key press on a hardware keyboard hides the on-screen keyboard.
Laptop posture keeps KWin's own edges. Derived from Plasma Mobile's task
switcher.
%endif

%prep
%autosetup -n %{name}-%{version}

%build
# No display: the generators render offscreen and must not start anything in a session.
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export QT_QPA_PLATFORM=offscreen
export STAGE="$PWD/_stage"
rm -rf "$STAGE"
bash tools/build.sh
# The Plymouth theme (boot splash and disk unlock) is system-wide only, so it is not in the HOME
# stage. It is shipped as a source for tools/system/plymouth-install.sh, not installed into
# /usr/share/plymouth/themes: installing this package never changes the boot splash.
bash generators/plymouth/build.sh "$PWD/_plymouth/plasma-fusion"

%if %{with compiled}
for part in decoration navigation; do
  %cmake -S packages/$part-cpp -B _build/$part -G Ninja -DBUILD_TESTING=OFF -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
  %__cmake --build _build/$part %{?_smp_mflags} --verbose
done
# rcc stamps every QML file of the settings page with SOURCE_DATE_EPOCH, and Qt's QML disk cache
# (~/.cache/systemsettings/qmlcache, ~/.cache/kcmshell6/qmlcache) reuses a compiled file whose
# source time stamp is unchanged: two builds from the same day would share the stamp, and an update
# would keep showing the previous page. The stamp is derived from the sources instead: the same
# sources give the same stamp (the build stays reproducible), any change gives a new one.
(
  cd packages/kcm-cpp
  SOURCE_DATE_EPOCH=$(( 1700000000 + 0x$(cat CMakeLists.txt src/CMakeLists.txt src/*.h src/*.cpp src/*.json src/ui/*.qml ../common/*.qml | sha256sum | cut -c1-6) ))
  export SOURCE_DATE_EPOCH QT_RCC_SOURCE_DATE_OVERRIDE=$SOURCE_DATE_EPOCH
  echo "settings page QML time stamp: $SOURCE_DATE_EPOCH"
  %cmake_kf6 -S . -B ../../_build/settings -G Ninja -DBUILD_TESTING=OFF
  %__cmake --build ../../_build/settings %{?_smp_mflags} --verbose
)
%endif

%install
bash packaging/install-tree.sh --stage _stage --plymouth _plymouth/plasma-fusion \
  --destdir %{buildroot} --prefix %{_prefix} --libexecdir %{_libexecdir}
mkdir -p %{buildroot}%{_datadir}/plasma-fusion/built-against
%if %{with compiled}
for part in decoration settings navigation; do
  DESTDIR=%{buildroot} %__cmake --install _build/$part
done
# Qt's QML disk cache (~/.cache/kwin/qmlcache) reuses a compiled file while the source's time stamp
# is unchanged, and rpm clamps every time stamp to the %%changelog date: two releases built on one
# day ship equal times, and KWin kept running the previous release's effect QML after an update.
# Each QML/JS file gets a time derived from its content instead, before the clamp date so rpm keeps
# it: the same file gives the same time (reproducible), any change a new one.
find %{buildroot}%{_datadir}/kwin/effects/plasmafusion_navigation %{buildroot}%{_qt6_qmldir}/org/plasmafusion/navigation \
  -type f \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' -o -name qmldir \) -print0 |
  while IFS= read -r -d '' f; do
    touch -h -d "@$(( ${SOURCE_DATE_EPOCH:-1700000000} - 1 - 0x$(sha256sum "$f" | cut -c1-6) ))" "$f"
  done
%endif

%check
# Every symbolic link must resolve, inside the package or (the Breeze hand-back links) in
# breeze-icon-theme, a requirement that is installed on the build host too: look at the
# buildroot with Breeze's two themes linked in for the moment. The links into hicolor and into
# Flatpak's exported icons name the icons of apps that need not be installed (they resolve once the
# app is); the Flatpak ones stay absolute (/var/lib/flatpak is outside the package's tree).
ln -s /usr/share/icons/breeze %{buildroot}%{_datadir}/icons/breeze
ln -s /usr/share/icons/breeze-dark %{buildroot}%{_datadir}/icons/breeze-dark
find %{buildroot} -xtype l -not -path '%{buildroot}%{_datadir}/icons/PlasmaFusion*/hicolor/*' \
  -not -path '%{buildroot}%{_datadir}/icons/PlasmaFusion*/flatpak/*' >broken-links.txt
rm %{buildroot}%{_datadir}/icons/breeze %{buildroot}%{_datadir}/icons/breeze-dark
find %{buildroot} -type l -lname '/*' -not -lname '/var/lib/flatpak/exports/share/icons/hicolor/*' >absolute-links.txt
if [ -s absolute-links.txt ] || [ -s broken-links.txt ]; then
  cat absolute-links.txt broken-links.txt >&2
  exit 1
fi
# The naming table's packages are all there.
for p in plasma/look-and-feel/org.plasmafusion.dark.desktop plasma/look-and-feel/org.plasmafusion.light.desktop \
         plasma/desktoptheme/plasma-fusion-dark plasma/desktoptheme/plasma-fusion-light \
         plasma/plasmoids/org.plasmafusion.appname plasma/plasmoids/org.plasmafusion.clockpill \
         plasma/plasmoids/org.plasmafusion.quicksettings plasma/plasmoids/org.plasmafusion.launcher \
         plasma/plasmoids/org.plasmafusion.dock plasma/plasmoids/org.plasmafusion.pen \
         plasma/plasmoids/org.plasmafusion.desktop \
         plasma/plasmoids/org.plasmafusion.calendarcard plasma/plasmoids/org.plasmafusion.weathercard \
         plasma/plasmoids/org.plasmafusion.systemcard plasma/shells/org.plasmafusion.lockshell \
         plasma/layout-templates/org.plasmafusion.panel.topbar plasma/layout-templates/org.plasmafusion.panel.dock \
         kwin/tabbox/org.plasmafusion.switcher kwin/scripts/plasmafusion-snap kwin/scripts/plasmafusion-attach \
         kwin/scripts/plasmafusion-tablet; do
  test -s "%{buildroot}%{_datadir}/$p/metadata.json"
done
for t in PlasmaFusion PlasmaFusion-Dark PlasmaFusion-cursors PlasmaFusion-Light-cursors; do
  test -s "%{buildroot}%{_datadir}/icons/$t/index.theme"
done
test -s %{buildroot}%{_datadir}/plasma-fusion/backgrounds/dusk-ridge-dark-login.png
# What the per-user step takes from the package: the power-tiers unit and program, the pen
# templates, the login check, the top-bar script of the Global Themes, the font fallback.
test -s %{buildroot}%{_datadir}/plasma-fusion/powerfx/plasma-fusion-powerfx.service
test -s %{buildroot}%{_datadir}/plasma-fusion/appicons/plasma-fusion-app-icons.service
for h in powerfx libreoffice charge-limit keyboard-keys app-icons; do
  test -x %{buildroot}%{_libexecdir}/plasma-fusion/plasma-fusion-$h
done
grep -qF '%{_libexecdir}/plasma-fusion/plasma-fusion-charge-limit</annotate>' \
  %{buildroot}%{_datadir}/polkit-1/actions/org.plasmafusion.charge-limit.policy
test -s %{buildroot}%{_datadir}/plasma-fusion/pen/templates/Note.xopp
test -x %{buildroot}%{_datadir}/plasma-fusion/tools/device/gate/plasma-fusion-gate.sh
test -x %{buildroot}%{_datadir}/plasma-fusion/tools/pen/pen-defaults.sh
test -s %{buildroot}%{_datadir}/plasma-fusion/tools/device/previous-theme.py
for t in dark light; do
  test -s %{buildroot}%{_datadir}/plasma/look-and-feel/org.plasmafusion.$t.desktop/contents/layouts/ensure-topbars.js
done
test -s %{buildroot}%{_datadir}/plasma-fusion/config/fontconfig/conf.d/60-plasma-fusion-fallback.conf
test -s %{buildroot}%{_datadir}/plasma-fusion/config/systemd/user/plasma-fusion-powerfx.service
test -s %{buildroot}%{_datadir}/kwin/tabbox/org.plasmafusion.switcher/contents/ui/shaders/thumbnail.frag.qsb
test -s %{buildroot}%{_datadir}/kwin/scripts/plasmafusion-snap/contents/ui/ensureTopBars.js
# The command and the version files it reads.
test "$(%{buildroot}%{_bindir}/plasma-fusion version)" = "$(cat VERSION)"
test -s %{buildroot}%{_datadir}/plasma-fusion/tested-plasma.txt
test -s %{buildroot}%{_datadir}/plasma-fusion/items.txt
%if %{with compiled}
for part in decoration settings navigation; do
  test -s %{buildroot}%{_datadir}/plasma-fusion/built-against/$part
done
%endif

%files
%license packaging/LICENSES/GPL-2.0-or-later.txt
%license packaging/LICENSES/CC-BY-SA-4.0.txt
%{_bindir}/plasma-fusion
# Colour schemes (the directory has no owner in Fedora 44)
%dir %{_datadir}/color-schemes
%{_datadir}/color-schemes/PlasmaFusionDark.colors
%{_datadir}/color-schemes/PlasmaFusionLight.colors
%{_datadir}/color-schemes/PlasmaFusionHighContrast.colors
# Global Themes, Plasma styles, widgets, lock-screen shell
%{_datadir}/plasma/look-and-feel/org.plasmafusion.dark.desktop/
%{_datadir}/plasma/look-and-feel/org.plasmafusion.light.desktop/
%{_datadir}/plasma/desktoptheme/plasma-fusion-dark/
%{_datadir}/plasma/desktoptheme/plasma-fusion-light/
# every Plasma Fusion widget (top bar, launcher, dock, quick settings, desktop cards...); the
# check section makes sure the naming table's ones are there
%{_datadir}/plasma/plasmoids/org.plasmafusion.*/
%{_datadir}/plasma/shells/org.plasmafusion.lockshell/
# "Add Panel" entries for the top bar and the dock (the directory belongs to plasma-desktop)
%{_datadir}/plasma/layout-templates/org.plasmafusion.panel.topbar/
%{_datadir}/plasma/layout-templates/org.plasmafusion.panel.dock/
# Icon and cursor themes
%{_datadir}/icons/PlasmaFusion/
%{_datadir}/icons/PlasmaFusion-Dark/
%{_datadir}/icons/PlasmaFusion-cursors/
%{_datadir}/icons/PlasmaFusion-Light-cursors/
# Window decorations (Aurorae v2 reads aurorae/themes in the data directories)
%dir %{_datadir}/aurorae
%dir %{_datadir}/aurorae/themes
%{_datadir}/aurorae/themes/PlasmaFusionDark/
%{_datadir}/aurorae/themes/PlasmaFusionDark-Left/
%{_datadir}/aurorae/themes/PlasmaFusionLight/
%{_datadir}/aurorae/themes/PlasmaFusionLight-Left/
# Wallpapers
%{_datadir}/wallpapers/PlasmaFusion/
%{_datadir}/wallpapers/PlasmaFusion-*/
# KWin window switcher and scripts (KWin 6.7 reads kwin-wayland/ and kwin/; kpackagetool6
# installs into kwin/)
%dir %{_datadir}/kwin
%dir %{_datadir}/kwin/tabbox
%dir %{_datadir}/kwin/scripts
%{_datadir}/kwin/tabbox/org.plasmafusion.switcher/
%{_datadir}/kwin/scripts/plasmafusion-attach/
%{_datadir}/kwin/scripts/plasmafusion-snap/
%{_datadir}/kwin/scripts/plasmafusion-tablet/
# Konsole colour schemes and profile, Kate/KWrite colour themes
%dir %{_datadir}/konsole
%{_datadir}/konsole/PlasmaFusionDark.colorscheme
%{_datadir}/konsole/PlasmaFusionLight.colorscheme
"%{_datadir}/konsole/Plasma Fusion.profile"
%dir %{_datadir}/org.kde.syntax-highlighting
%dir %{_datadir}/org.kde.syntax-highlighting/themes
"%{_datadir}/org.kde.syntax-highlighting/themes/Plasma Fusion Dark.theme"
"%{_datadir}/org.kde.syntax-highlighting/themes/Plasma Fusion Light.theme"
# Fonts: one static file per weight (fontconfig's file trigger refreshes its cache)
%dir %{_datadir}/fonts/plasma-fusion
%{_datadir}/fonts/plasma-fusion/*.ttf
%license %{_datadir}/fonts/plasma-fusion/OFL-Manrope.txt
%license %{_datadir}/fonts/plasma-fusion/OFL-SpaceGrotesk.txt
# Backgrounds, per-user templates, scripts, version files and documentation
%dir %{_datadir}/plasma-fusion
%dir %{_datadir}/plasma-fusion/built-against
%{_datadir}/plasma-fusion/backgrounds/
%{_datadir}/plasma-fusion/pen/
%{_datadir}/plasma-fusion/powerfx/
%{_datadir}/plasma-fusion/appicons/
%{_datadir}/plasma-fusion/compat/
%{_datadir}/plasma-fusion/config/
%{_datadir}/plasma-fusion/plymouth/
%{_datadir}/plasma-fusion/tools/
%{_datadir}/plasma-fusion/version
%{_datadir}/plasma-fusion/tested-plasma.txt
%{_datadir}/plasma-fusion/items.txt
%doc %{_datadir}/plasma-fusion/docs/
# The helpers: power tiers (started per user by plasma-fusion setup; nothing is enabled by the
# package), the battery charge limit of the quick settings (pkexec, polkit action
# org.plasmafusion.charge-limit), Esc/Tab/arrows on the on-screen keyboard, the familiar app icons,
# the LibreOffice scale guard
%dir %{_libexecdir}/plasma-fusion
%{_libexecdir}/plasma-fusion/plasma-fusion-powerfx
%{_libexecdir}/plasma-fusion/plasma-fusion-libreoffice
%{_libexecdir}/plasma-fusion/plasma-fusion-charge-limit
%{_libexecdir}/plasma-fusion/plasma-fusion-keyboard-keys
%{_libexecdir}/plasma-fusion/plasma-fusion-app-icons
%{_datadir}/polkit-1/actions/org.plasmafusion.charge-limit.policy

%if %{with compiled}
%files decoration
%license LICENSES/GPL-2.0-or-later.txt
%{_qt6_plugindir}/org.kde.kdecoration3/org.plasmafusion.decoration.so
%{_datadir}/plasma-fusion/built-against/decoration

%files settings
%license LICENSES/GPL-2.0-or-later.txt LICENSES/CC-BY-SA-4.0.txt
%{_kf6_qtplugindir}/plasma/kcms/systemsettings/kcm_plasmafusion.so
%{_kf6_datadir}/applications/kcm_plasmafusion.desktop
%{_kf6_datadir}/icons/hicolor/scalable/apps/plasmafusion-logo.svg
%{_datadir}/plasma-fusion/built-against/settings

%files navigation
%license LICENSES/GPL-2.0-or-later.txt
%doc packages/navigation-cpp/README.md
%{_datadir}/kwin/effects/plasmafusion_navigation/
%{_qt6_qmldir}/org/plasmafusion/navigation/
%{_datadir}/plasma-fusion/built-against/navigation
%endif

%changelog
* Tue Oct 06 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 0.3.1-1
- Calendar tiles keep the live date correct after suspend

* Tue Oct 06 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 0.3.0-1
- Settings module sections for icons and lock/login, greeter wallpaper
  treatment, Calendar tile and dock fixes, Plasma 6.8 support

* Fri Oct 02 2026 Wisbendji Fimerlus <archledger236@gmail.com> - 0.2.0-1
- First release: one package set for Fedora from one source (the shared part
  and the window decoration, settings page and tablet navigation)
