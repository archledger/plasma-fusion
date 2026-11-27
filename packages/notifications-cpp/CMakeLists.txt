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
# The Plasma version src/ was taken from (README.md). The built-against record names it, beside
# the Plasma version the build found.
set(PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION "6.8.3")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

# plasma-workspace builds its C++ as C++ 23 and sets the standard before it includes
# KDECompilerSettings (its CMakeLists.txt, lines 17 to 25): set afterwards, the standard would be a
# strict one, without the GNU extensions upstream compiles with.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)
include(ECMQtDeclareLoggingCategory)
include(ECMDeprecationSettings)
include(FeatureSummary)
# As upstream (its CMakeLists.txt, ecm_set_disabled_deprecation_versions).
ecm_set_disabled_deprecation_versions(QT 5.15.2 KF 5.98.0)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS DBus Quick Widgets WaylandClient)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS
    CoreAddons GlobalAccel I18n KIO Notifications Service WindowSystem)
find_package(Plasma 6.8 REQUIRED)
find_package(PlasmaQuick 6.8 REQUIRED)
find_package(LibNotificationManager 6.8 REQUIRED CONFIG)
find_package(PlasmaWaylandProtocols 1.23 REQUIRED)
find_package(Wayland REQUIRED COMPONENTS Client)

add_executable(plasma-fusion-notifications-check src/checkmain.cpp src/plugincheck.cpp)
target_link_libraries(plasma-fusion-notifications-check PRIVATE Qt6::Core)
install(TARGETS plasma-fusion-notifications-check DESTINATION "${KDE_INSTALL_LIBEXECDIR}/plasma-fusion")

# plasma_add_applet installs into ${KDE_INSTALL_PLUGINDIR}/plasma/applets. The copy must never land
# on the stock plugin's path there: it goes under a directory Plasma Fusion owns, and the build
# stops unless that directory is an absolute path that, symbolic links resolved, is neither Qt's
# own plugin directory nor inside it, nor KDE's own when that is another directory (cmake/
# PluginDirGuard.cmake). KDEInstallDirs sets its full paths when it is included, so both are known
# here. The guard gives back the directory as it resolved it, and that is what the install rule
# uses: the string checked is the string installed.
set(PF_QT_PLUGIN_DIR "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_PLUGINS}")
set(PF_NOTIFICATIONS_PLUGIN_DIR "${CMAKE_INSTALL_FULL_LIBEXECDIR}/plasma-fusion/qt6/plugins"
    CACHE PATH "Absolute directory the notification applet copy is installed under")
include(cmake/PluginDirGuard.cmake)
pf_check_plugin_dir("${PF_NOTIFICATIONS_PLUGIN_DIR}" "${PF_QT_PLUGIN_DIR}" _pf_plugin_dir
                    "${KDE_INSTALL_FULL_PLUGINDIR}")
set(KDE_INSTALL_PLUGINDIR "${_pf_plugin_dir}")

set(_gate_dir "${CMAKE_CURRENT_BINARY_DIR}/notifications-gate")
configure_file(gate/common.sh.in "${_gate_dir}/plasma-fusion-notifications-common.sh" @ONLY)
configure_file(gate/plasma-fusion-notifications-select.in "${_gate_dir}/plasma-fusion-notifications-select"
    @ONLY FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
install(FILES "${_gate_dir}/plasma-fusion-notifications-common.sh" DESTINATION "${KDE_INSTALL_LIBEXECDIR}/plasma-fusion")
install(PROGRAMS "${_gate_dir}/plasma-fusion-notifications-select" DESTINATION "${KDE_INSTALL_LIBEXECDIR}/plasma-fusion")

add_subdirectory(src)

target_compile_definitions(org.kde.plasma.notifications PRIVATE
    PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION="${PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION}")

# What this build was made against, for plasma-fusion status: the Plasma version the source was
# taken from, the Plasma version the build found, and Qt's. Both Plasma versions matter: a copy of
# one version's source compiled against another version's libraries must not be put in front on a
# machine that runs the source version.
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/built-against
    "source-plasma-workspace=${PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION}\nplasma-workspace=${LibNotificationManager_VERSION}\nqt=${Qt6_VERSION}\n")
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/built-against
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma-fusion/built-against RENAME notifications)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
