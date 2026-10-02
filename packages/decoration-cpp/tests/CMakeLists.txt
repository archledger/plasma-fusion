# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Offline test tool, not installed: loads the built plugin with a mock KDecoration3 bridge, renders
# scenes to PNG and checks the snap-layouts trigger (see docs/parts/decoration-cpp.md).

add_executable(pfdeco-preview preview.cpp)
target_link_libraries(pfdeco-preview
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::DBus
        KF6::CoreAddons
        KF6::ConfigCore
        KF6::ColorScheme
        KDecoration3::KDecoration
        KDecoration3::KDecoration3Private
)
target_compile_definitions(pfdeco-preview PRIVATE PFDECO_PLUGIN="$<TARGET_FILE:plasmafusiondecoration>")
add_dependencies(pfdeco-preview plasmafusiondecoration)

# The preview's checks as tests (ctest), dark and light, through run-checks.sh. They need the colour
# schemes of the repository (packages/color-schemes) and dbus-run-session; without them (a source
# tarball, a system without D-Bus) the tests are left out.
set(PF_SCHEMES "${CMAKE_CURRENT_SOURCE_DIR}/../../color-schemes")
find_program(DBUS_RUN_SESSION dbus-run-session)
if(EXISTS "${PF_SCHEMES}/PlasmaFusionDark.colors" AND EXISTS "${PF_SCHEMES}/PlasmaFusionLight.colors" AND DBUS_RUN_SESSION)
    foreach(scheme Dark Light)
        if(scheme STREQUAL "Dark")
            set(other Light)
        else()
            set(other Dark)
        endif()
        string(TOLOWER "${scheme}" name)
        add_test(NAME pfdeco-preview-${name}
                 COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/run-checks.sh"
                         $<TARGET_FILE:pfdeco-preview> $<TARGET_FILE:plasmafusiondecoration>
                         "${CMAKE_CURRENT_BINARY_DIR}/preview-${name}" ${name}
                         "${PF_SCHEMES}/PlasmaFusion${scheme}.colors" "${PF_SCHEMES}/PlasmaFusion${other}.colors"
                         "${CMAKE_CURRENT_SOURCE_DIR}/../../../fonts/manrope/static")
        set_tests_properties(pfdeco-preview-${name} PROPERTIES TIMEOUT 600)
    endforeach()
endif()
