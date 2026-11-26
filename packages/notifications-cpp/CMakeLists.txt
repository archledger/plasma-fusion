# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion's copy of Plasma's notification applet (README.md): KDE's applets/notifications of
# plasma-workspace v6.8.3, built as the plugin org.kde.plasma.notifications and installed under a
# Fusion-owned directory, so that a version gate can put it in front of the stock plugin without
# ever replacing the stock plugin's file.
#
#   cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
#   ninja -C build
#   DESTDIR="$PWD/build/stage" ninja -C build install
cmake_minimum_required(VERSION 3.22)
# C as well as C++: Qt generates the applet's Wayland protocol code as C.
project(plasma-fusion-notifications VERSION 0.1.0 LANGUAGES C CXX)

# The floors of the stock source's own build (plasma-workspace v6.8.3, CMakeLists.txt): what a
# system needs to build it at all, not the versions it was tested with.
set(QT_MIN_VERSION "6.11.0")
set(KF_MIN_VERSION "6.30.0")
# The Plasma version src/ was taken from (README.md). The plugin compares the running Plasma with
# this version before it offers the banner keyboard triage, and the built-against record names it.
set(PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION "6.8.3")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)
include(ECMQtDeclareLoggingCategory)
include(FeatureSummary)

# plasma-workspace builds its C++ as C++ 23.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS DBus Quick Widgets WaylandClient)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS
    CoreAddons GlobalAccel I18n KIO Notifications Service WindowSystem)
find_package(Plasma 6.8 REQUIRED)
find_package(PlasmaQuick 6.8 REQUIRED)
find_package(LibNotificationManager 6.8 REQUIRED CONFIG)
find_package(PlasmaWaylandProtocols 1.23 REQUIRED)
find_package(Wayland REQUIRED COMPONENTS Client)

# plasma_add_applet installs into ${KDE_INSTALL_PLUGINDIR}/plasma/applets. The copy must never land
# on the stock plugin's path there: it goes under a directory Plasma Fusion owns, and the build
# stops unless that directory is an absolute path that, symbolic links resolved, is neither Qt's
# own plugin directory nor inside it (cmake/PluginDirGuard.cmake). KDEInstallDirs fills its
# variables at the end of the configuration, so Qt's plugin directory is taken from Qt and the
# copy's directory is a real path now, not a placeholder expanded later.
set(PF_QT_PLUGIN_DIR "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_PLUGINS}")
set(PF_NOTIFICATIONS_PLUGIN_DIR "${CMAKE_INSTALL_FULL_LIBEXECDIR}/plasma-fusion/qt6/plugins"
    CACHE PATH "Absolute directory the notification applet copy is installed under")
include(cmake/PluginDirGuard.cmake)
pf_check_plugin_dir("${PF_NOTIFICATIONS_PLUGIN_DIR}" "${PF_QT_PLUGIN_DIR}")
set(KDE_INSTALL_PLUGINDIR "${PF_NOTIFICATIONS_PLUGIN_DIR}")

add_subdirectory(src)

target_compile_definitions(org.kde.plasma.notifications PRIVATE
    PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION="${PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION}")

# The versions this build was made against, for plasma-fusion status (a copy built from another
# Plasma version than the running one must not be used).
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/built-against
    "plasma-workspace=${PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION}\nqt=${Qt6_VERSION}\n")
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/built-against
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma-fusion/built-against RENAME notifications)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
