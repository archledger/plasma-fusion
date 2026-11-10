// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include <QDebug>
#include <QLoggingCategory>
#include <QObject>
#include <QQmlExtensionPlugin>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSet>
#include <QVariant>
#include <qqml.h>

class Probe : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE void dump(QObject *object, QObject *switcher, const QString &label)
    {
        qInfo().noquote() << "PFTHUMB BEGIN" << label;
        if (object) {
            auto *category = QLoggingCategory::defaultCategory();
            const bool debugEnabled = category->isDebugEnabled();
            category->setEnabled(QtDebugMsg, true);
            object->dumpObjectInfo();
            category->setEnabled(QtDebugMsg, debugEnabled);
        } else {
            qInfo() << "PFTHUMB MISSING";
        }
        QSet<QObject *> seen;
        QList<QObject *> pending{switcher};
        int assigned = 0;
        while (!pending.isEmpty()) {
            QObject *item = pending.takeLast();
            if (!item || seen.contains(item)) {
                continue;
            }
            seen.insert(item);
            if (item->metaObject()->indexOfProperty("wId") >= 0 && item->metaObject()->indexOfProperty("client") >= 0
                && item->property("client").value<QObject *>() == object) {
                ++assigned;
            }
            pending.append(item->children());
            if (auto *window = qobject_cast<QQuickWindow *>(item)) {
                pending.append(window->contentItem());
            }
            if (auto *quickItem = qobject_cast<QQuickItem *>(item)) {
                for (QQuickItem *child : quickItem->childItems()) {
                    pending.append(child);
                }
            }
        }
        qInfo() << "PFTHUMB CLIENTS" << assigned;
        qInfo().noquote() << "PFTHUMB END" << label;
    }
};

class Plugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterType<Probe>(uri, 1, 0, "Probe");
    }
};

#include "probe.moc"
