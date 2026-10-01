# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion navigation: the tablet posture's bottom-edge gestures (home, app switcher, previous
# app) as a KWin 6.7 effect (TABLET2.md 3.1). Derived from Plasma Mobile's task switcher
# (plasma-mobile v6.7.5 kwin/mobiletaskswitcher, GPL-2.0-or-later); see README.md.
#
#   cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
#   ninja -C build
cmake_minimum_required(VERSION 3.22)
project(plasma-fusion-navigation VERSION 0.1.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)
include(FeatureSummary)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Quick Qml)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS ConfigWidgets GlobalAccel I18n CoreAddons WindowSystem Package)
find_package(KWin 6.7 REQUIRED COMPONENTS kwin)
find_package(PlasmaActivities REQUIRED)

add_definitions(-DTRANSLATION_DOMAIN=\"plasma_fusion_navigation\")

add_subdirectory(src)

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
