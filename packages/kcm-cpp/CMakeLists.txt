# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion settings module (System Settings > Appearance & Style > Plasma Fusion).
# Built for Plasma 6.7.5, KDE Frameworks 6.30 and Qt 6.11 (Fedora 44); see plasma-fusion-settings.spec.
cmake_minimum_required(VERSION 3.22)
project(plasma-fusion-settings VERSION 1.0.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui DBus Qml Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS Config CoreAddons I18n KCMUtils)

add_subdirectory(src)

# kcmctl and the module test (ctest); KDECMakeSettings sets BUILD_TESTING on by default.
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

install(FILES icons/plasmafusion-logo.svg DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

# The versions this build was made against, for plasma-fusion status (a package built against an
# older KWin or KDecoration than the running one is due for a rebuild).
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/built-against "kf=${KF6Config_VERSION}\nqt=${Qt6_VERSION}\n")
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/built-against
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma-fusion/built-against RENAME settings)

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
