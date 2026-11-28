# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.22)

function(expect_exit expected description)
    execute_process(COMMAND "${CHECKER}" ${ARGN}
                    RESULT_VARIABLE result ERROR_VARIABLE error TIMEOUT 5)
    if(NOT "${result}" STREQUAL "${expected}")
        message(FATAL_ERROR "${description}: expected ${expected}, got ${result}: ${error}")
    endif()
endfunction()

file(MAKE_DIRECTORY "${TEST_DIR}")
file(WRITE "${TEST_DIR}/org.kde.plasma.notifications.so" "This is not a shared library.")
file(COPY_FILE "${PLUGIN}" "${TEST_DIR}/renamed.so")

expect_exit(0 "valid applet" "${PLUGIN}")
expect_exit(1 "missing applet" "${TEST_DIR}/missing/org.kde.plasma.notifications.so")
expect_exit(1 "unloadable applet" "${TEST_DIR}/org.kde.plasma.notifications.so")
expect_exit(1 "real applet under the wrong name" "${TEST_DIR}/renamed.so")
expect_exit(2 "no argument")
expect_exit(2 "relative filename" "org.kde.plasma.notifications.so")
expect_exit(2 "extra argument" "${PLUGIN}" "--extra")
