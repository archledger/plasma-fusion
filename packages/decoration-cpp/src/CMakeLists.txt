# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

add_library(plasmafusiondecoration MODULE
    button.cpp
    colors.cpp
    decoration.cpp
    fusionconfig.cpp
    glyphs.cpp
    shadow.cpp
)

# KWin finds decoration plugins by file name / plugin id: org.plasmafusion.decoration
set_target_properties(plasmafusiondecoration PROPERTIES
    OUTPUT_NAME org.plasmafusion.decoration
    PREFIX ""
)

target_link_libraries(plasmafusiondecoration
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::DBus
        KF6::CoreAddons
        KF6::ConfigCore
        KF6::ColorScheme
        KDecoration3::KDecoration
)

install(TARGETS plasmafusiondecoration DESTINATION ${KDE_INSTALL_PLUGINDIR}/${KDECORATION_PLUGIN_DIR})
