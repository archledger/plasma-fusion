# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Tests (ctest; the RPM build turns BUILD_TESTING off): kcmctl (kcmctl/kcmctl.cpp, not installed)
# loads the built module the way System Settings does, and run-kcmctl.sh drives it without a window
# in a scratch HOME: load, read every property, defaults, read them again. Nothing is saved.
# fuzz-kcmctl.sh runs it with random configuration files and commands, saving included, still in a
# scratch HOME and with stand-ins for the programs the module starts. meters-switch.sh turns the
# system meters switch on and off against fakeshell, a stand-in Plasma shell, and shell-panels.sh
# changes the panels against it; run-power-tier.sh runs the module with the power service against
# a stand-in plasmashell, run-reset-layout.sh its layout reset.

add_executable(kcmctl kcmctl/kcmctl.cpp)
# A stand-in Plasma shell for the switches that change panels (meters-switch.sh).
add_executable(fakeshell fakeshell/fakeshell.cpp)
target_link_libraries(fakeshell PRIVATE Qt6::Core Qt6::DBus Qt6::Qml)
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
    # The system meters switch against the stand-in shell: where the meters go, the errors, and
    # that Apply does not wait for the shell (meters-switch.sh).
    add_test(NAME kcmctl-meters
             COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/meters-switch.sh" $<TARGET_FILE:kcmctl> $<TARGET_FILE:fakeshell>
                     "${CMAKE_BINARY_DIR}/bin" "${CMAKE_CURRENT_BINARY_DIR}/kcmctl-meters")
    set_tests_properties(kcmctl-meters PROPERTIES TIMEOUT 300)
    # The panel changes against the stand-in shell (shell-panels.sh): a top bar without a screen.
    add_test(NAME kcmctl-panels
             COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/shell-panels.sh" $<TARGET_FILE:kcmctl> $<TARGET_FILE:fakeshell>
                     "${CMAKE_BINARY_DIR}/bin" "${CMAKE_CURRENT_BINARY_DIR}/kcmctl-panels")
    set_tests_properties(kcmctl-panels PROPERTIES TIMEOUT 300)
    # The module with the power service at a held tier (run-power-tier.sh): a stand-in plasmashell
    # and KWin from packages/powerfx/tests, which need node and python3's GObject bindings.
    find_program(NODE_EXECUTABLE node)
    find_package(Python3 COMPONENTS Interpreter)
    if(NODE_EXECUTABLE AND Python3_Interpreter_FOUND)
        execute_process(COMMAND ${Python3_EXECUTABLE} -c "import gi" RESULT_VARIABLE PF_NO_GI OUTPUT_QUIET ERROR_QUIET)
        if(PF_NO_GI EQUAL 0)
            add_test(NAME kcmctl-power
                     COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/run-power-tier.sh" $<TARGET_FILE:kcmctl> "${CMAKE_BINARY_DIR}/bin"
                             "${CMAKE_CURRENT_BINARY_DIR}/kcmctl-power")
            set_tests_properties(kcmctl-power PROPERTIES TIMEOUT 180)
            # "Reset Fusion layout" and the shortcuts it gives (run-reset-layout.sh).
            add_test(NAME kcmctl-reset
                     COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/run-reset-layout.sh" $<TARGET_FILE:kcmctl> "${CMAKE_BINARY_DIR}/bin"
                             "${CMAKE_CURRENT_BINARY_DIR}/kcmctl-reset")
            set_tests_properties(kcmctl-reset PROPERTIES TIMEOUT 180)
        endif()
    endif()
endif()
