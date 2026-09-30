# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed, not in the RPM): kcmctl loads the settings module's plugin the way
# System Settings does and drives it from commands on stdin (see kcmctl.cpp).
#   cmake -S packages/kcm-cpp/tests/kcmctl -B BUILD -G Ninja && ninja -C BUILD
cmake_minimum_required(VERSION 3.22)
project(kcmctl LANGUAGES CXX)
find_package(ECM 6.10 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml)
find_package(KF6 6.10 REQUIRED COMPONENTS CoreAddons KCMUtils)
add_executable(kcmctl kcmctl.cpp)
target_link_libraries(kcmctl PRIVATE Qt6::Core Qt6::Gui Qt6::Qml KF6::CoreAddons KF6::KCMUtilsQuick)
