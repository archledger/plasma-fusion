# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Tests (ctest; the RPM build turns BUILD_TESTING off): copytext-core (coretest.cpp) reads KWin's raw
# pictures from a pipe and turns a box into native pixels; copytext-overlay (overlaytest.cpp) loads
# the overlay's QML offscreen and checks it against the CopyText board and its mouse and keys;
# copytext-capture (capturetest.cpp) takes a picture through a stand-in for KWin's ScreenShot2 on a
# private session bus; copytext-flow (flowtest.cpp) runs the overlay itself there, offscreen on two
# screens, with a stand-in for the helper.

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test)

add_executable(copytextcoretest coretest.cpp)
target_link_libraries(copytextcoretest PRIVATE copytextcore Qt6::Test)
add_test(NAME copytext-core COMMAND copytextcoretest)
set_tests_properties(copytext-core PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen" TIMEOUT 60)

add_executable(copytextoverlaytest overlaytest.cpp)
target_compile_definitions(copytextoverlaytest PRIVATE OVERLAY_QML="${CMAKE_CURRENT_SOURCE_DIR}/../src/qml/Overlay.qml"
                           TRANSLATION_DOMAIN="plasma-fusion-copytext-overlay")
target_link_libraries(copytextoverlaytest PRIVATE Qt6::Test Qt6::Quick Qt6::Qml KF6::I18n KF6::I18nQml)
add_test(NAME copytext-overlay COMMAND copytextoverlaytest)
set_tests_properties(copytext-overlay PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software" TIMEOUT 60)

find_program(DBUS_RUN_SESSION dbus-run-session)
if(DBUS_RUN_SESSION)
    add_executable(copytextcapturetest capturetest.cpp fakekwin.h)
    target_link_libraries(copytextcapturetest PRIVATE copytextcore Qt6::Test)
    add_test(NAME copytext-capture COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:copytextcapturetest>)
    set_tests_properties(copytext-capture PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen" TIMEOUT 60)

    # In a directory of its own with the stand-in helper, as the overlay looks for its helper beside
    # the program; the test sets the offscreen platform's two screens itself.
    add_executable(copytextflowtest flowtest.cpp fakekwin.h)
    target_link_libraries(copytextflowtest PRIVATE copytextoverlay Qt6::Test)
    set_target_properties(copytextflowtest PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/flow)
    configure_file(fake-helper.sh ${CMAKE_CURRENT_BINARY_DIR}/flow/plasma-fusion-copytext COPYONLY)
    add_test(NAME copytext-flow COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:copytextflowtest>)
    set_tests_properties(copytext-flow PROPERTIES ENVIRONMENT "QT_QUICK_BACKEND=software" TIMEOUT 120)
endif()
