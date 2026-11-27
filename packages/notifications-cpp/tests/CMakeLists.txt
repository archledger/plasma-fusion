# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Tests of the notification applet copy. They are configured with the package (BUILD_TESTING=ON)
# and need the applet's own build requirements.

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Test)

add_executable(notificationsplugintest plugintest.cpp)
set_target_properties(notificationsplugintest PROPERTIES AUTOMOC ON)
target_compile_definitions(notificationsplugintest PRIVATE
    PLUGIN_PATH="$<TARGET_FILE:org.kde.plasma.notifications>")
target_link_libraries(notificationsplugintest PRIVATE Qt6::Core Qt6::Test)
add_test(NAME notifications-plugin COMMAND notificationsplugintest)
set_tests_properties(notifications-plugin PROPERTIES TIMEOUT 30)

# The directory guard as a unit test of its CMake functions (../cmake/PluginDirGuard.cmake), on a
# tree of directories and symbolic links and behind the wrapper's own lines, which it configures
# fifteen times in a small project without a compiler: it needs no compiler and no packages.
add_test(NAME notifications-plugin-dir-guard COMMAND "${CMAKE_COMMAND}"
    "-DGUARD_MODULE=${CMAKE_CURRENT_SOURCE_DIR}/../cmake/PluginDirGuard.cmake"
    "-DWRAPPER=${CMAKE_CURRENT_SOURCE_DIR}/../CMakeLists.txt"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/guardtest.cmake")
set_tests_properties(notifications-plugin-dir-guard PROPERTIES TIMEOUT 600)
