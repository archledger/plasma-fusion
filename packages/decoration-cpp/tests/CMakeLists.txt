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
