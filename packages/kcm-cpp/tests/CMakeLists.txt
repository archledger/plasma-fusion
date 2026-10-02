# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Tests (ctest; the RPM build turns BUILD_TESTING off): kcmctl (kcmctl/kcmctl.cpp, not installed)
# loads the built module the way System Settings does, and run-kcmctl.sh drives it without a window
# in a scratch HOME: load, read every property, defaults, read them again. Nothing is saved.

add_executable(kcmctl kcmctl/kcmctl.cpp)
target_link_libraries(kcmctl PRIVATE Qt6::Core Qt6::Gui Qt6::Qml KF6::CoreAddons KF6::KCMUtilsQuick)
add_dependencies(kcmctl kcm_plasmafusion)

find_program(DBUS_RUN_SESSION dbus-run-session)
if(DBUS_RUN_SESSION)
    add_test(NAME kcmctl-load
             COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/run-kcmctl.sh" $<TARGET_FILE:kcmctl> "${CMAKE_BINARY_DIR}/bin"
                     "${CMAKE_CURRENT_BINARY_DIR}/kcmctl-load")
    set_tests_properties(kcmctl-load PROPERTIES TIMEOUT 120)
endif()
