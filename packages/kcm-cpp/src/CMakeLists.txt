# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

add_definitions(-DTRANSLATION_DOMAIN=\"kcm_plasmafusion\")

# Plugin in plasma/kcms/systemsettings, QML from ui/ compiled in as resources, and
# kcm_plasmafusion.desktop (Exec=systemsettings kcm_plasmafusion) generated from the JSON.
kcmutils_add_qml_kcm(kcm_plasmafusion SOURCES kcm.cpp kcm.h)

target_link_libraries(kcm_plasmafusion PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::DBus
    Qt6::Qml
    Qt6::Quick
    KF6::ConfigCore
    KF6::ConfigGui
    KF6::CoreAddons
    KF6::I18n
    KF6::KCMUtilsQuick
)
