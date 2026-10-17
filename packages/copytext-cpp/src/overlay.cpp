// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "overlay.h"
#include "area.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlComponent>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QScreen>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTimer>

#include <KLocalizedQmlContext>
#include <LayerShellQt/Window>

#ifdef __GLIBC__
#include <malloc.h>
#endif

using namespace Qt::StringLiterals;

// The still pictures for the overlay's Image items ("image://capture/SCREEN/SERIAL"; the serial
// keeps Qt Quick from showing a picture of an earlier capture).
class CaptureImages : public QQuickImageProvider
{
public:
    CaptureImages()
        : QQuickImageProvider(QQuickImageProvider::Image)
    {
    }
    QImage requestImage(const QString &id, QSize *size, const QSize &) override
    {
        const QImage image = pictures.value(id.section(u'/', 0, 0));
        if (size) {
            *size = image.size();
        }
        return image;
    }
    QHash<QString, QImage> pictures;
};

Overlay::Overlay(QObject *parent)
    : QObject(parent)
{
    m_images = new CaptureImages; // the engine owns it
    m_engine.addImageProvider(u"capture"_s, m_images);
    KLocalization::setupLocalizedContext(&m_engine);
    // Compiled once, now: a capture then only makes its windows.
    m_component = new QQmlComponent(&m_engine, this);
    m_component->loadFromModule("org.plasmafusion.copytextoverlay", "Overlay", QQmlComponent::PreferSynchronous);
    if (m_component->isError()) {
        qWarning().noquote() << "copytext-overlay:" << m_component->errorString();
    }
    connect(&m_capture, &ScreenCapture::captured, this, [this](const QString &screenName, const QImage &image) {
        m_pictures.insert(screenName, image);
        if (--m_waiting == 0 && m_active) {
            showAll();
        }
    });
    connect(&m_capture, &ScreenCapture::failed, this, [this](const QString &screenName, const QString &reason) {
        qWarning().noquote() << "copytext-overlay: no picture of" << screenName << "-" << reason;
        if (m_active) {
            closeAll();
            fallBack();
        }
    });
}

QString Overlay::helper() const
{
    return QCoreApplication::applicationDirPath() + u"/plasma-fusion-copytext"_s;
}

void Overlay::Start()
{
    // A second press while the box is being chosen does nothing (as the helper's lock).
    if (m_active) {
        return;
    }
    m_active = true;
    m_clock.start();
    m_pictures.clear();
    const auto screens = QGuiApplication::screens();
    m_waiting = screens.size();
    for (QScreen *screen : screens) {
        m_capture.capture(screen->name());
    }
}

void Overlay::showAll()
{
    qInfo().noquote() << "copytext-overlay: pictures in" << m_clock.elapsed() << "ms";
    if (!m_component->isReady()) {
        closeAll();
        fallBack();
        return;
    }
    ++m_serial;
    m_images->pictures = m_pictures;
    const auto screens = QGuiApplication::screens();
    for (QScreen *screen : screens) {
        if (!m_pictures.contains(screen->name())) {
            continue;
        }
        const QVariantMap properties{
            {u"screenName"_s, screen->name()},
            {u"picture"_s, QUrl(u"image://capture/%1/%2"_s.arg(screen->name()).arg(m_serial))},
        };
        QObject *object = m_component->createWithInitialProperties(properties);
        auto *window = qobject_cast<QQuickWindow *>(object);
        if (!window) {
            delete object;
            continue;
        }
        window->setScreen(screen);
        window->setGeometry(screen->geometry());
        // Above everything, the panels too, over the whole screen, with the keyboard (Esc).
        if (auto *layer = LayerShellQt::Window::get(window)) {
            layer->setLayer(LayerShellQt::Window::LayerOverlay);
            layer->setAnchors(
                {LayerShellQt::Window::AnchorTop, LayerShellQt::Window::AnchorBottom, LayerShellQt::Window::AnchorLeft, LayerShellQt::Window::AnchorRight});
            layer->setExclusiveZone(-1);
            layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
            layer->setScope(u"plasma-fusion-copytext"_s);
            layer->setWantsToBeOnActiveScreen(false);
            layer->setScreen(screen);
        }
        connect(window, SIGNAL(chosen(QString, QRectF)), this, SLOT(chosen(QString, QRectF)));
        connect(window, SIGNAL(cancelled()), this, SLOT(cancelled()));
        m_windows.append(window);
        window->show();
    }
    qInfo().noquote() << "copytext-overlay: shown in" << m_clock.elapsed() << "ms at" << QDateTime::currentMSecsSinceEpoch();
}

void Overlay::closeAll()
{
    for (QQuickWindow *window : std::as_const(m_windows)) {
        window->close();
        window->deleteLater();
    }
    m_windows.clear();
    m_images->pictures.clear();
    if (m_active) {
        qInfo().noquote() << "copytext-overlay: closed";
        // It waits for the next capture, maybe for hours: the pictures and the windows' memory go
        // back to the system once the windows are gone (glibc keeps freed memory otherwise).
        QTimer::singleShot(1000, this, [] {
#ifdef __GLIBC__
            malloc_trim(0);
#endif
            QFile status(u"/proc/self/status"_s);
            if (status.open(QIODevice::ReadOnly)) {
                for (const QByteArray &line : status.readAll().split('\n')) {
                    if (line.startsWith("VmRSS:")) {
                        qInfo().noquote() << "copytext-overlay: waiting," << line.mid(6).trimmed();
                    }
                }
            }
        });
    }
    m_active = false;
}

void Overlay::chosen(const QString &screenName, const QRectF &area)
{
    const QImage picture = m_pictures.value(screenName);
    m_pictures.clear();
    closeAll();
    if (picture.isNull()) {
        return;
    }
    // The box is in the window's logical pixels; the picture is native (Tesseract reads more).
    const QRect native = nativeArea(area, picture.devicePixelRatio(), picture.rect());
    if (native.isEmpty()) {
        return;
    }
    QImage crop = picture.copy(native);
    crop.setDevicePixelRatio(1.0);
    read(crop);
}

void Overlay::cancelled()
{
    m_pictures.clear();
    closeAll();
}

void Overlay::read(const QImage &area)
{
    // A private directory in the runtime directory, removed once the helper is done with it.
    auto *dir = new QTemporaryDir(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + u"/plasma-fusion-copytext-overlay.XXXXXX"_s);
    const QString file = dir->filePath(u"region.png"_s);
    if (!dir->isValid() || !area.save(file, "PNG")) {
        qWarning().noquote() << "copytext-overlay: the area could not be saved";
        delete dir;
        return;
    }
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [process, dir] {
        process->deleteLater();
        delete dir;
    });
    connect(process, &QProcess::errorOccurred, this, [process, dir](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            qWarning().noquote() << "copytext-overlay: plasma-fusion-copytext did not start";
            process->deleteLater();
            delete dir;
        }
    });
    process->start(helper(), {u"--image"_s, file});
}

void Overlay::fallBack()
{
    // KWin refused the pictures (no desktop file allowing ScreenShot2, an older KWin): the helper's
    // own way, Spectacle's selection.
    QProcess process;
    process.setProgram(helper());
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(u"PLASMA_FUSION_COPYTEXT_NO_OVERLAY"_s, u"1"_s);
    process.setProcessEnvironment(environment);
    process.startDetached();
}
