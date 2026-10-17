# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

add_definitions(-DTRANSLATION_DOMAIN=\"plasma-fusion-copytext-overlay\")

# KWin's picture and the box's arithmetic in a static library the program and the tests share.
add_library(copytextcore STATIC capture.cpp capture.h area.h)
target_include_directories(copytextcore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(copytextcore PUBLIC Qt6::Core Qt6::Concurrent Qt6::DBus Qt6::Gui)

# The overlay (Start(), its windows, the hand-over to the helper) with its QML compiled in as a
# module, in a static library the program and the flow test share.
add_library(copytextoverlay STATIC overlay.cpp overlay.h)
# The QML module under :/qt/qml, on QML's import path (Qt 6.5's default for new modules).
qt_policy(SET QTP0001 NEW)
qt_add_qml_module(copytextoverlay
    URI org.plasmafusion.copytextoverlay
    VERSION 1.0
    NO_PLUGIN
    QML_FILES qml/Overlay.qml
    OUTPUT_TARGETS copytextoverlay_resource_targets
)
# A static library's QML resources are object libraries of their own that take the library's
# include directories, AUTOMOC's among them: built before AUTOMOC has made that directory, they
# fail with KDE's -Wmissing-include-dirs (and -Werror) on a fresh build. They wait for it.
foreach(resource_target IN LISTS copytextoverlay_resource_targets)
    add_dependencies(${resource_target} copytextoverlay_autogen)
endforeach()
target_link_libraries(copytextoverlay PUBLIC
    copytextcore
    Qt6::Qml
    Qt6::Quick
    KF6::I18n
    KF6::I18nQml
    LayerShellQt::Interface
)

qt_add_executable(plasma-fusion-copytext-overlay main.cpp)
target_link_libraries(plasma-fusion-copytext-overlay PRIVATE copytextoverlay)
install(TARGETS plasma-fusion-copytext-overlay DESTINATION ${PF_HELPER_DIR})
