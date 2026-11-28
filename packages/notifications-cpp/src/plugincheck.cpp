/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "plugincheck.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonObject>
#include <QPluginLoader>

#include <algorithm>

using namespace Qt::StringLiterals;

QString checkNotificationPlugin(const QString &absolutePath)
{
    const QFileInfo file(absolutePath);
    if (file.fileName() != "org.kde.plasma.notifications.so"_L1 || !file.isFile()) {
        return u"not a notification applet file: %1"_s.arg(absolutePath);
    }

    QPluginLoader loader(absolutePath);
    loader.setLoadHints(QLibrary::ResolveAllSymbolsHint | QLibrary::PreventUnloadHint);
    if (!loader.load()) {
        return loader.errorString();
    }

    const auto wrapper = loader.metaData();
    const auto metadata = wrapper.value("MetaData"_L1).toObject();
    const auto provides = metadata.value("X-Plasma-Provides"_L1).toArray();
    if (wrapper.value("IID"_L1).toString() != "org.kde.KPluginFactory"_L1 || metadata.value("X-Plasma-API-Minimum-Version"_L1).toString() != "6.0"_L1
        || metadata.value("KPlugin"_L1).toObject().value("Name"_L1).toString() != "Notifications"_L1
        || std::none_of(provides.begin(), provides.end(), [](const QJsonValue &entry) {
               return entry.toString() == "org.kde.plasma.notifications"_L1;
           })) {
        return u"plugin metadata does not identify the stock notification applet"_s;
    }

    const auto prefix = u":/qt/qml/plasma/applet/org/kde/plasma/notifications/"_s;
    for (const char *resource : {"main.qml",
                                 "NotificationPopup.qml",
                                 "CompactRepresentation.qml",
                                 "FullRepresentation.qml",
                                 "global/Globals.qml",
                                 "delegates/DelegatePopup.qml",
                                 "components/NotificationHeader.qml"}) {
        if (!QFile::exists(prefix + QLatin1StringView(resource))) {
            return u"missing QML resource: %1"_s.arg(QLatin1StringView(resource));
        }
    }
    return {};
}
