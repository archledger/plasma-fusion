# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

# These contract tests can run without a KWin development installation or compositor.
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    cmake_minimum_required(VERSION 3.22)
    project(plasma-fusion-navigation-tests LANGUAGES CXX)
    enable_testing()
    set(QT_MIN_VERSION "6.8.0")
endif()

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Test)

add_executable(navigation_capability_test capabilities_test.cpp)
set_target_properties(navigation_capability_test PROPERTIES AUTOMOC ON)
target_include_directories(navigation_capability_test PRIVATE ../src/plugin)
target_link_libraries(navigation_capability_test PRIVATE Qt6::Core Qt6::Test)
add_test(NAME navigation-capability COMMAND navigation_capability_test)
set_tests_properties(navigation-capability PROPERTIES TIMEOUT 30)
