// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

// Plasma Fusion Quick Look: a window that shows what is in the files it is given (Space in
// Dolphin, "Quick Look" in the context menus), without opening them. Space or Esc closes it, the
// arrow keys go through the files, Enter opens the shown one in its application.

#include "quicklook.h"
#include "thumbnails.h"

#include <KAboutData>
#include <KDBusService>
#include <KLocalizedQmlContext>
#include <KLocalizedString>
#include <KWindowSystem>

#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>

namespace
{
void addOptions(QCommandLineParser &parser, const QList<QCommandLineOption> &options)
{
    parser.addPositionalArgument(QStringLiteral("files"), i18nc("@info:shell", "The files to preview"), QStringLiteral("[file...]"));
    parser.addOptions(options);
}
}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain("plasma-fusion-quicklook");
    KAboutData about(QStringLiteral("plasma-fusion-quicklook"),
                     i18nc("@title the application", "Quick Look"),
                     QStringLiteral("1.0"),
                     i18nc("@info", "Preview files without opening them"),
                     KAboutLicense::GPL_V2,
                     QStringLiteral("© 2026 Wisbendji Fimerlus"));
    about.setDesktopFileName(QStringLiteral("org.plasmafusion.quicklook"));
    KAboutData::setApplicationData(about);
    QApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("document-preview")));
    // The desktop style, so it looks like the other KDE applications (Plasma Fusion's colours).
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }

    // Tests: each file is shown in turn and what its viewer showed is written to FILE as JSON.
    QCommandLineOption reportOption(QStringLiteral("test-report"),
                                    QStringLiteral("Tests: write what the viewers showed to FILE, then quit."),
                                    QStringLiteral("file"));
    reportOption.setFlags(QCommandLineOption::HiddenFromHelp);
    // Tests: the viewer of this kind is taken as missing (its Qt module not installed).
    QCommandLineOption unavailableOption(QStringLiteral("test-unavailable"),
                                         QStringLiteral("Tests: take the viewer of KIND as missing."),
                                         QStringLiteral("kind"));
    unavailableOption.setFlags(QCommandLineOption::HiddenFromHelp);
    const QList<QCommandLineOption> options{reportOption, unavailableOption};
    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    addOptions(parser, options);
    parser.process(app);
    about.processCommandLine(&parser);
    const QString report = parser.value(reportOption);

    QuickLookSession session;
    session.setFiles(parser.positionalArguments(), QDir::currentPath());
    if (session.count() == 0) {
        qWarning("plasma-fusion-quicklook: no local file to preview");
        return 1;
    }

    // One preview at a time: a second start (Space again in Dolphin) hands its files to this one,
    // and the same files again close it, as Space does in macOS's Quick Look.
    KDBusService service(report.isEmpty() ? KDBusService::Unique : KDBusService::Multiple);

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    engine.addImageProvider(QStringLiteral("quicklook-thumbnail"), new ThumbnailProvider);
    engine.setInitialProperties({{QStringLiteral("session"), QVariant::fromValue(&session)},
                                 {QStringLiteral("testReport"), report},
                                 {QStringLiteral("testUnavailable"), parser.value(unavailableOption)}});
    engine.loadFromModule("org.plasmafusion.quicklook", "Main");
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    QObject::connect(&session, &QuickLookSession::closeRequested, &app, &QCoreApplication::quit);
    QObject::connect(&service, &KDBusService::activateRequested, &app, [&](const QStringList &arguments, const QString &workingDirectory) {
        QCommandLineParser second;
        addOptions(second, options);
        second.parse(arguments);
        if (!session.setFiles(second.positionalArguments(), workingDirectory)) {
            QCoreApplication::quit();
            return;
        }
        if (window) {
            // KDBusService gives the activation token of the second start for the time of this call.
            KWindowSystem::setCurrentXdgActivationToken(qEnvironmentVariable("XDG_ACTIVATION_TOKEN"));
            KWindowSystem::activateWindow(window);
        }
    });
    return app.exec();
}
