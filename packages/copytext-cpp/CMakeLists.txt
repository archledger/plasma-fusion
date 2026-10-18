# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion copy text's own selection overlay (CopyText board; prototype, not packaged yet): a
# helper that stays running, so the overlay shows at once where Spectacle starts from scratch on
# every capture (about 2.5 s). It captures the screens through KWin's ScreenShot2 interface, which
# KWin allows to it by its desktop file, shows the still screen under a veil, takes the box as the
# drag ends and hands the area to plasma-fusion-copytext, which reads, copies and notifies.
cmake_minimum_required(VERSION 3.22)
project(plasma-fusion-copytext-overlay VERSION 0.1.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Concurrent DBus Gui Qml Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS I18n)
find_package(LayerShellQt REQUIRED)

# Next to plasma-fusion-copytext, in the helper directory the setup and quick settings look in
# (Fedora and Debian /usr/libexec/plasma-fusion; Arch passes /usr/lib/plasma-fusion).
set(PF_HELPER_DIR "${CMAKE_INSTALL_PREFIX}/libexec/plasma-fusion" CACHE PATH "Plasma Fusion's helper directory")

add_subdirectory(src)

# The capture's reading and arithmetic, the overlay offscreen and its capture on a private bus
# (ctest); KDECMakeSettings sets BUILD_TESTING on by default.
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

# KWin allows ScreenShot2 to a process whose executable is the first word of Exec= in a desktop
# file listing the interface (KWin 6.7.5 utils/serviceutils.h); hidden from menus, as plasmashell's.
configure_file(data/org.plasmafusion.copytextoverlay.desktop.in
               ${CMAKE_CURRENT_BINARY_DIR}/org.plasmafusion.copytextoverlay.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.plasmafusion.copytextoverlay.desktop DESTINATION ${KDE_INSTALL_APPDIR})

# Started by the session bus on the first copy text (plasma-fusion-copytext calls Start()), then
# waiting for the next: nothing to set up per user, nothing kept before the first use.
configure_file(data/org.plasmafusion.CopyTextOverlay.service.in
               ${CMAKE_CURRENT_BINARY_DIR}/org.plasmafusion.CopyTextOverlay.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.plasmafusion.CopyTextOverlay.service DESTINATION ${KDE_INSTALL_DBUSSERVICEDIR})

# The versions this build was made against, for plasma-fusion status.
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/built-against "kf=${KF6I18n_VERSION}\nqt=${Qt6_VERSION}\n")
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/built-against
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma-fusion/built-against RENAME copytext)

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
