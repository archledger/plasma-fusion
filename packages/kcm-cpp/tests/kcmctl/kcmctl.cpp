/*
    Test tooling (not installed): loads kcm_plasmafusion as System Settings does (the plugin from
    QT_PLUGIN_PATH, no page shown) and runs commands read from stdin, one per line:

      waitshell            wait (max 10 s) until the module has read the Plasma shell
      wait MS              run the event loop for MS milliseconds
      load | save | defaults
      set PROPERTY VALUE   true/false, integers, or text
      call METHOD          an invokable without arguments (resetLayout, restorePreviousDesktop, ...)
      waitidle             wait (max 90 s) until the module is no longer busy
      get PROPERTY         prints PROPERTY=value
      dump                 prints every property of the module, one per line
      sh COMMAND           runs COMMAND with bash -c and waits for it
      # ...                comment

    Output lines start with "kcmctl: ". Exit status 0, or 2 when the plugin could not be loaded.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>

#include <QColor>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QGuiApplication>
#include <QMetaProperty>
#include <QProcess>
#include <QTextStream>
#include <QTimer>

#include <cstdio>

namespace
{
QTextStream out(stdout);

void spin(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

bool waitFor(QObject *module, const char *property, bool wanted, int maxMs)
{
    QElapsedTimer timer;
    timer.start();
    while (module->property(property).toBool() != wanted) {
        if (timer.elapsed() > maxMs) {
            return false;
        }
        spin(50);
    }
    return true;
}

QString valueText(const QVariant &value)
{
    if (value.metaType().id() == QMetaType::QColor) {
        return value.value<QColor>().name(QColor::HexArgb);
    }
    return value.toString();
}

void dump(QObject *module)
{
    const QMetaObject *meta = module->metaObject();
    for (int i = 0; i < meta->propertyCount(); ++i) {
        const QMetaProperty property = meta->property(i);
        const QString name = QString::fromLatin1(property.name());
        if (name == QLatin1String("objectName") || name == QLatin1String("mainUi") || name == QLatin1String("metaData")
            || name == QLatin1String("columnWidth") || name == QLatin1String("depth") || name == QLatin1String("currentIndex")) {
            continue;
        }
        const QVariant value = property.read(module);
        if (value.canConvert<QString>() || value.metaType().id() == QMetaType::QColor) {
            out << "kcmctl: " << name << '=' << valueText(value) << Qt::endl;
        }
    }
}
} // namespace

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    const KPluginMetaData metaData(QStringLiteral("plasma/kcms/systemsettings/kcm_plasmafusion"));
    auto result = KQuickConfigModuleLoader::loadModule(metaData, &app);
    if (!result) {
        out << "kcmctl: cannot load the module: " << result.errorString << Qt::endl;
        return 2;
    }
    KQuickConfigModule *module = result.plugin;
    QMetaObject::invokeMethod(module, "load");

    QTextStream in(stdin);
    QString line;
    while (in.readLineInto(&line)) {
        line = line.trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        const QString command = line.section(QLatin1Char(' '), 0, 0);
        const QString rest = line.section(QLatin1Char(' '), 1);
        out << "kcmctl: > " << line << Qt::endl;
        if (command == QLatin1String("waitshell")) {
            spin(100);
            if (!waitFor(module, "shellLoading", false, 10000)) {
                out << "kcmctl: timeout waiting for the shell state" << Qt::endl;
            }
        } else if (command == QLatin1String("wait")) {
            spin(rest.toInt());
        } else if (command == QLatin1String("load") || command == QLatin1String("save") || command == QLatin1String("defaults")) {
            QMetaObject::invokeMethod(module, command.toLatin1().constData());
            spin(200);
        } else if (command == QLatin1String("set")) {
            const QString name = rest.section(QLatin1Char(' '), 0, 0);
            const QString text = rest.section(QLatin1Char(' '), 1);
            QVariant value = text;
            if (text == QLatin1String("true") || text == QLatin1String("false")) {
                value = text == QLatin1String("true");
            } else {
                bool isNumber = false;
                const int number = text.toInt(&isNumber);
                if (isNumber) {
                    value = number;
                }
            }
            if (!module->setProperty(name.toLatin1().constData(), value)) {
                out << "kcmctl: cannot set " << name << Qt::endl;
            }
        } else if (command == QLatin1String("call")) {
            if (!QMetaObject::invokeMethod(module, rest.toLatin1().constData())) {
                out << "kcmctl: cannot call " << rest << Qt::endl;
            }
            spin(200);
        } else if (command == QLatin1String("waitidle")) {
            spin(200);
            if (!waitFor(module, "busy", false, 90000)) {
                out << "kcmctl: timeout waiting for the action" << Qt::endl;
            }
        } else if (command == QLatin1String("get")) {
            out << "kcmctl: " << rest << '=' << valueText(module->property(rest.toLatin1().constData())) << Qt::endl;
        } else if (command == QLatin1String("dump")) {
            dump(module);
        } else if (command == QLatin1String("sh")) {
            QProcess process;
            process.setProcessChannelMode(QProcess::ForwardedChannels);
            process.start(QStringLiteral("bash"), {QStringLiteral("-c"), rest});
            while (!process.waitForFinished(50)) {
                QCoreApplication::processEvents();
            }
        } else {
            out << "kcmctl: unknown command " << command << Qt::endl;
        }
    }
    delete module;
    return 0;
}
