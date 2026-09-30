# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion window decoration (KDecoration3 plugin for KWin 6.7).
#
#   cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
#   ninja -C build
#
# BUILD_TESTING=ON (the default) also builds tests/pfdeco-preview, an offline renderer that loads the
# built plugin with a mock bridge (not installed).
cmake_minimum_required(VERSION 3.22)
project(plasma-fusion-decoration VERSION 1.0.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

# KDecoration3 6.7 headers use C++20 (defaulted comparison operators).
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui DBus)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons Config ColorScheme)
find_package(KDecoration3 6.7 REQUIRED)

if(NOT KDECORATION_PLUGIN_DIR)
    set(KDECORATION_PLUGIN_DIR "org.kde.kdecoration3")
endif()

add_subdirectory(src)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
