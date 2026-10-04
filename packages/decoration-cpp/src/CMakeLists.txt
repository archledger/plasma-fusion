# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

# The plugin metadata (embedded by K_PLUGIN_FACTORY_WITH_JSON, found through the build directory).
# Without styles it is the same file as before KDecoration 6.8, byte for byte.
if(PFDECO_HAVE_STYLES)
    string(CONCAT PFDECO_STYLES_JSON ",\n"
                  "        \"styles\": [\n"
                  "            \"titled\",\n"
                  "            \"shadow\"\n"
                  "        ]")
else()
    set(PFDECO_STYLES_JSON "")
endif()
configure_file(plasmafusion.json.in ${CMAKE_CURRENT_BINARY_DIR}/plasmafusion.json @ONLY)

add_library(plasmafusiondecoration MODULE
    button.cpp
    colors.cpp
    decoration.cpp
    fusionconfig.cpp
    glyphs.cpp
    shadow.cpp
    tabletmode.cpp
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
