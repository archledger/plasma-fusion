# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Tests (ctest; the RPM build turns BUILD_TESTING off): quicklook-model (quicklooktest.cpp) checks
# what each kind of file is taken for and what is read from it, and the session's files;
# quicklook-viewers (run-viewers.sh) starts the application offscreen on sample files of every kind
# and checks what its viewers showed (--test-report), on a private session bus.

# The viewers test loads the QML modules and plugins the package requires (Fedora names; CI installs
# them from this line):
# viewers test needs: kf6-kirigami kf6-qqc2-desktop-style qt6-qtpdf qt6-qtmultimedia kf6-syntax-highlighting qt6-qtsvg kio-extras python3

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test)

add_executable(quicklooktest quicklooktest.cpp)
target_link_libraries(quicklooktest PRIVATE quicklookcore Qt6::Test)
add_test(NAME quicklook-model COMMAND quicklooktest)
set_tests_properties(quicklook-model PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen" TIMEOUT 120)

find_program(DBUS_RUN_SESSION dbus-run-session)
if(DBUS_RUN_SESSION)
    add_test(NAME quicklook-viewers
             COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/run-viewers.sh" $<TARGET_FILE:plasma-fusion-quicklook>
                     "${CMAKE_CURRENT_BINARY_DIR}/quicklook-viewers")
    set_tests_properties(quicklook-viewers PROPERTIES TIMEOUT 300)
endif()
