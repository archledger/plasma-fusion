# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion Quick Look: preview a file without opening it (Space in Dolphin, "Quick Look" in
# the context menus of Dolphin and the desktop). Built for Plasma 6.7, KDE Frameworks 6.30 and
# Qt 6.11 (Fedora 44); packaged by packaging/fedora/plasma-fusion.spec.
cmake_minimum_required(VERSION 3.22)
project(plasma-fusion-quicklook VERSION 1.0.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Widgets Qml Quick QuickControls2)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons DBusAddons I18n KIO Service WindowSystem)

add_subdirectory(src)

# The model test and the viewers test (ctest); KDECMakeSettings sets BUILD_TESTING on by default.
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

# The application's desktop file (its icon and name for the window; not in the menu) and the
# service menu that adds "Quick Look" to the context menus of Dolphin and the desktop. Dolphin 26.04
# and later list service-menu actions among its shortcuts (KIO 6.24), where the Plasma Fusion setup
# gives this one Space (tools/device/fusion-config.sh).
install(FILES data/org.plasmafusion.quicklook.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES data/plasma-fusion-quicklook.desktop DESTINATION ${KDE_INSTALL_DATADIR}/kio/servicemenus)

# The versions this build was made against, for plasma-fusion status.
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/built-against "kf=${KF6KIO_VERSION}\nqt=${Qt6_VERSION}\n")
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/built-against
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma-fusion/built-against RENAME quicklook)

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
