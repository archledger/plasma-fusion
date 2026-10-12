/*
    Test tooling (not installed): a stand-in Plasma shell for the module tests. It owns
    org.kde.plasmashell on the (private) session bus and answers org.kde.PlasmaShell.evaluateScript
    by running the script in a QJSEngine against shell.js, a small model of the desktop scripting
    API (panels(), widgets(), addWidget(), the widgets' index and configuration, knownWidgetTypes,
    screenCount, print()). The layout comes from a JSON file; after every script the panels are
    written to the state file, one line per panel, so a test can check where the widgets went.

      fakeshell SHELL_JS LAYOUT_JSON STATE_FILE

    Prints "fakeshell: ready" once the name is registered.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QFile>
#include <QJSEngine>
#include <QStringList>
#include <QTextStream>
#include <QThread>

#include <cstdio>
#include <cstdlib>

namespace
{
QString readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(file.readAll());
}
} // namespace

// What the scripts print, collected per call (desktop scripting's print()).
class Host : public QObject
{
    Q_OBJECT
public:
    QStringList printed;
    Q_INVOKABLE void print(const QString &text)
    {
        printed << text;
    }
    // What plasmashell does on a read it cannot do (shell.js says when): it is gone at once,
    // without an answer.
    Q_INVOKABLE void crash(const QString &what)
    {
        std::fprintf(stderr, "fakeshell: crashed reading %s\n", qPrintable(what));
        std::fflush(stderr);
        std::_Exit(139);
    }
};

class Shell : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.PlasmaShell")
public:
    Shell(const QString &model, const QString &layout, const QString &statePath)
        : m_statePath(statePath)
    {
        m_engine.installExtensions(QJSEngine::ConsoleExtension);
        m_engine.globalObject().setProperty(QStringLiteral("host"), m_engine.newQObject(&m_host));
        const QJSValue loaded = m_engine.evaluate(model, QStringLiteral("shell.js"));
        if (loaded.isError()) {
            qFatal("shell.js: %s", qPrintable(loaded.toString()));
        }
        const QJSValue started = m_engine.globalObject().property(QStringLiteral("loadLayout")).call({QJSValue(layout)});
        if (started.isError()) {
            qFatal("layout: %s", qPrintable(started.toString()));
        }
        writeState();
    }

public Q_SLOTS:
    Q_SCRIPTABLE QString evaluateScript(const QString &script)
    {
        // A busy shell answers late and nothing else meanwhile, as plasmashell runs scripts on its
        // main thread.
        QThread::msleep(m_engine.globalObject().property(QStringLiteral("nextScriptDelay")).call().toInt());
        m_host.printed.clear();
        // Each script runs in its own function scope, as plasmashell gives each its own context.
        const QJSValue result = m_engine.evaluate(QStringLiteral("(function () {\n") + script + QStringLiteral("\n})();"), QStringLiteral("script.js"));
        if (result.isError()) {
            m_host.printed << QStringLiteral("Error: ") + result.toString();
        }
        writeState();
        return m_host.printed.join(u'\n');
    }

private:
    void writeState()
    {
        QFile file(m_statePath);
        if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            file.write(m_engine.globalObject().property(QStringLiteral("dumpLayout")).call().toString().toUtf8());
        }
    }

    QJSEngine m_engine;
    Host m_host;
    QString m_statePath;
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QStringList args = app.arguments();
    if (args.size() != 4) {
        std::fprintf(stderr, "usage: fakeshell SHELL_JS LAYOUT_JSON STATE_FILE\n");
        return 2;
    }
    Shell shell(readFile(args.at(1)), readFile(args.at(2)), args.at(3));
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(QStringLiteral("/PlasmaShell"), &shell, QDBusConnection::ExportScriptableSlots)
        || !bus.registerService(QStringLiteral("org.kde.plasmashell"))) {
        std::fprintf(stderr, "fakeshell: cannot register org.kde.plasmashell\n");
        return 1;
    }
    std::printf("fakeshell: ready\n");
    std::fflush(stdout);
    return app.exec();
}

#include "fakeshell.moc"
