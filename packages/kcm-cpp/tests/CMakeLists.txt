# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Tests (ctest; the RPM build turns BUILD_TESTING off): kcmctl (kcmctl/kcmctl.cpp, not installed)
# loads the built module the way System Settings does, and run-kcmctl.sh drives it without a window
# in a scratch HOME: load, read every property, defaults, read them again. Nothing is saved.
# fuzz-kcmctl.sh runs it with random configuration files and commands, saving included, still in a
# scratch HOME and with stand-ins for the programs the module starts.

add_executable(kcmctl kcmctl/kcmctl.cpp)
target_link_libraries(kcmctl PRIVATE Qt6::Core Qt6::Gui Qt6::Qml KF6::CoreAddons KF6::KCMUtilsQuick)
add_dependencies(kcmctl kcm_plasmafusion)

find_program(DBUS_RUN_SESSION dbus-run-session)
if(DBUS_RUN_SESSION)
    add_test(NAME kcmctl-load
             COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/run-kcmctl.sh" $<TARGET_FILE:kcmctl> "${CMAKE_BINARY_DIR}/bin"
                     "${CMAKE_CURRENT_BINARY_DIR}/kcmctl-load")
    set_tests_properties(kcmctl-load PROPERTIES TIMEOUT 120)
    # Random configuration files and command sequences (fuzz-kcmctl.sh); PF_FUZZ_COUNT and
    # PF_FUZZ_SEED in the environment of ctest change the number of rounds (default 25) and the seed.
    add_test(NAME kcmctl-fuzz
             COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/fuzz-kcmctl.sh" $<TARGET_FILE:kcmctl> "${CMAKE_BINARY_DIR}/bin"
                     "${CMAKE_CURRENT_BINARY_DIR}/kcmctl-fuzz")
    set_tests_properties(kcmctl-fuzz PROPERTIES TIMEOUT 1800)
endif()
