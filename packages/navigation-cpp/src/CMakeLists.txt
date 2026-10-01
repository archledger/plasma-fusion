# SPDX-FileCopyrightText: 2025 Devin Lin <devin@kde.org>
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

# The QML effect package (KWin loads it as the declarative effect "plasmafusion_navigation").
kpackage_install_package(package plasmafusion_navigation effects kwin)

ecm_add_qml_module(fusionnavigationplugin
    URI org.plasmafusion.navigation.plugin
    GENERATE_PLUGIN_SOURCE
    DEPENDENCIES QtCore
)

target_sources(fusionnavigationplugin PRIVATE
    plugin/fusionnavigation.cpp
    plugin/keyboardspy.cpp
    plugin/touchborder.cpp
    plugin/taskfiltermodel.cpp
    plugin/taskmodel.cpp)

# The generated QML type registration includes the class headers by name.
target_include_directories(fusionnavigationplugin PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/plugin)

target_link_libraries(fusionnavigationplugin PRIVATE
    KF6::ConfigGui
    KF6::GlobalAccel
    KF6::I18n
    KF6::CoreAddons
    KF6::WindowSystem

    Qt::Quick
    Qt::Core
    Qt::DBus

    KWin::kwin
    Plasma::Activities
)

ecm_finalize_qml_module(fusionnavigationplugin)
