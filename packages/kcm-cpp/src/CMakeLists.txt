# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

add_definitions(-DTRANSLATION_DOMAIN=\"kcm_plasmafusion\")

# Plugin in plasma/kcms/systemsettings, QML from ui/ compiled in as resources, and
# kcm_plasmafusion.desktop (Exec=systemsettings kcm_plasmafusion) generated from the JSON.
kcmutils_add_qml_kcm(kcm_plasmafusion SOURCES kcm.cpp kcm.h kcm_p.h shell.cpp)

# The shared Plasma Fusion QML the page uses (FusionMetrics), next to the page's own files in the
# module's resources. Its source is packages/common in the repository (../common from here);
# build-remote.sh sends a copy as common/.
foreach(dir "${CMAKE_SOURCE_DIR}/common" "${CMAKE_SOURCE_DIR}/../common")
    if(NOT PF_COMMON_DIR AND EXISTS "${dir}/FusionMetrics.qml")
        get_filename_component(PF_COMMON_DIR "${dir}" ABSOLUTE)
    endif()
endforeach()
if(NOT PF_COMMON_DIR)
    message(FATAL_ERROR "FusionMetrics.qml not found (packages/common, or common/ in the source tarball)")
endif()
set(PF_COMMON_QRC "${CMAKE_CURRENT_BINARY_DIR}/kcm_plasmafusion_common.qrc")
file(WRITE "${PF_COMMON_QRC}" "<RCC>\n<qresource prefix=\"/kcm/kcm_plasmafusion\">\n<file alias=\"FusionMetrics.qml\">${PF_COMMON_DIR}/FusionMetrics.qml</file>\n</qresource>\n</RCC>\n")
qt_add_resources(PF_COMMON_RCC "${PF_COMMON_QRC}")
target_sources(kcm_plasmafusion PRIVATE ${PF_COMMON_RCC})

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
