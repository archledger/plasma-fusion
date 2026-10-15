# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

add_definitions(-DTRANSLATION_DOMAIN=\"plasma-fusion-quicklook\")

# The model (what each file is, its text, its thumbnail, the folder sizes) in a static library the
# application and the model test share; the QML viewers compiled in as resources.
add_library(quicklookcore STATIC quicklook.cpp quicklook.h thumbnails.cpp thumbnails.h)
target_include_directories(quicklookcore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(quicklookcore PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    KF6::CoreAddons
    KF6::I18n
    KF6::KIOCore
    KF6::KIOGui
    KF6::KIOWidgets
    KF6::Service
)

qt_add_executable(plasma-fusion-quicklook main.cpp)
# The QML module under :/qt/qml, on QML's import path (Qt 6.5's default for new modules).
qt_policy(SET QTP0001 NEW)
qt_add_qml_module(plasma-fusion-quicklook
    URI org.plasmafusion.quicklook
    VERSION 1.0
    NO_PLUGIN
    QML_FILES
        qml/Main.qml
        qml/ImageViewer.qml
        qml/PdfViewer.qml
        qml/TextViewer.qml
        qml/MediaViewer.qml
        qml/FolderViewer.qml
        qml/FileViewer.qml
)
target_link_libraries(plasma-fusion-quicklook PRIVATE
    quicklookcore
    Qt6::Widgets
    Qt6::Qml
    Qt6::QuickControls2
    KF6::DBusAddons
    KF6::I18nQml
    KF6::WindowSystem
)
install(TARGETS plasma-fusion-quicklook ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
