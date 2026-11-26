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

# The directory guard as a unit test of its CMake functions (../cmake/PluginDirGuard.cmake): it
# needs neither a compiler nor the applet's packages.
add_test(NAME notifications-plugin-dir-guard COMMAND "${CMAKE_COMMAND}"
    "-DGUARD_MODULE=${CMAKE_CURRENT_SOURCE_DIR}/../cmake/PluginDirGuard.cmake"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/guardtest.cmake")
set_tests_properties(notifications-plugin-dir-guard PROPERTIES TIMEOUT 60)

# The rules of the banner keyboard triage are a QML library; this test loads them through a holder.
find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Qml Quick)
add_executable(notificationstriagetest triagetest.cpp)
set_target_properties(notificationstriagetest PROPERTIES AUTOMOC ON)
target_compile_definitions(notificationstriagetest PRIVATE
    TRIAGE_HOLDER_QML="${CMAKE_CURRENT_SOURCE_DIR}/triage-holder.qml")
target_link_libraries(notificationstriagetest PRIVATE Qt6::Core Qt6::Test Qt6::Qml Qt6::Quick)
add_test(NAME notifications-triage-rules COMMAND notificationstriagetest)
set_tests_properties(notifications-triage-rules PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software" TIMEOUT 30)

# The version rule on its own: numbers in, a decision out.
add_executable(notificationsversiontest versiontest.cpp)
set_target_properties(notificationsversiontest PROPERTIES AUTOMOC ON)
target_compile_definitions(notificationsversiontest PRIVATE
    PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION="${PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION}")
target_link_libraries(notificationsversiontest PRIVATE Qt6::Core Qt6::Test)
add_test(NAME notifications-triage-version COMMAND notificationsversiontest)
set_tests_properties(notifications-triage-version PROPERTIES TIMEOUT 30)
