# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
cmake_minimum_required(VERSION 3.22)
project(ThumbnailConnectionProbe LANGUAGES CXX)
set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
find_package(Qt6 REQUIRED COMPONENTS Core Qml Quick)
add_library(thumbnailprobe MODULE probe.cpp)
target_link_libraries(thumbnailprobe PRIVATE Qt6::Core Qt6::Qml Qt6::Quick)
