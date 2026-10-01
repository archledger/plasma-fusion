// SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
// SPDX-FileCopyrightText: 2023 Devin Lin <devin@kde.org>
// SPDX-FileCopyrightText: 2024 Luis Büchi <luis.buechi@kdemail.net>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "fusionnavigation.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QKeyEvent>
#include <QMetaObject>
#include <QQuickItem>
#include <KSharedConfig>
#include <config-kwin.h>
#include <main.h>
#include <tabletmodemanager.h>
#include <core/output.h>
#include <window.h>
#include <workspace.h>

using namespace std::chrono_literals;

namespace KWin
{

FusionNavigationState::FusionNavigationState(QObject *parent)
    : QObject{parent}
    , m_doubleClickTimer{new QElapsedTimer{}}
    , m_shutdownTimer{new QTimer{this}}
{
    // Configure close timer
    m_shutdownTimer->setSingleShot(true);
    m_shutdownTimer->setInterval(300ms);
    connect(m_shutdownTimer, &QTimer::timeout, this, &FusionNavigationState::realDeactivate);
}

void FusionNavigationState::init(KWin::QuickSceneEffect *parent)
{
    // Plasma Fusion: the plugin uses KWin's internal classes, which keep no binary compatibility
    // between releases. Built for another KWin, it stays idle (no touch border, no key spy, no task
    // model); the login check switches the effect off after a KWin update before KWin starts.
    if (QCoreApplication::applicationVersion() != KWIN_VERSION_STRING) {
        qWarning("plasmafusion-navigation: built for KWin %s, running %s: the effect stays idle",
                 KWIN_VERSION_STRING.data(), qPrintable(QCoreApplication::applicationVersion()));
        return;
    }
    m_effectState = new FusionTouchBorderState(parent);
    m_border = new FusionTouchBorder{m_effectState};
    m_taskModel = new FusionTaskModel{parent};
    m_effect = parent;
    // Plasma Fusion: a hardware key hides the on-screen keyboard (TABLET2 P0 K1).
    m_keyboardSpy = std::make_unique<FusionKeyboardSpy>();

    // Plasma Fusion gesture lock (TABLET2 G1): plasmafusionrc [Tablet] GestureLock, followed live
    // (quick settings writes it with --notify). A held-back swipe shows Plasma's OSD.
    KSharedConfig::Ptr fusionConfig = KSharedConfig::openConfig(QStringLiteral("plasmafusionrc"));
    m_border->setLocked(fusionConfig->group(QStringLiteral("Tablet")).readEntry("GestureLock", false));
    m_configWatcher = KConfigWatcher::create(fusionConfig);
    connect(m_configWatcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group, const QByteArrayList &names) {
        if (group.name() == QLatin1String("Pen")) {
            KSharedConfig::openConfig(QStringLiteral("plasmafusionrc"))->reparseConfiguration();
            updatePen();
        }
        if (group.name() == QLatin1String("Tablet") && names.contains(QByteArrayLiteral("GestureLock"))) {
            m_border->setLocked(group.readEntry("GestureLock", false));
            qInfo("plasmafusion-navigation: gesture lock %s", m_border->locked() ? "on" : "off");
        }
    });
    connect(m_border, &FusionTouchBorder::gestureBlocked, this, []() {
        qInfo("plasmafusion-navigation: swipe held back by the gesture lock");
        QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"),
                                                              QStringLiteral("/org/kde/osdService"),
                                                              QStringLiteral("org.kde.osdService"),
                                                              QStringLiteral("showText"));
        message << QStringLiteral("object-locked")
                << i18nc("@info:osd the gesture lock held back a swipe from the bottom edge", "Gestures are locked: swipe again to go on");
        QDBusConnection::sessionBus().send(message);
    });

    // Connect signals
    connect(this, &FusionNavigationState::gestureEnabledChanged, this, &FusionNavigationState::refreshBorders);
    connect(m_border, &FusionTouchBorder::touchPositionChanged, this, &FusionNavigationState::processTouchPositionChanged);
    connect(this, &FusionNavigationState::gestureInProgressChanged, this, [this]() {
        if (gestureInProgress()) {
            invokeEffect();
        }
    });
    connect(m_effectState, &FusionTouchBorderState::inProgressChanged, this, &FusionNavigationState::gestureInProgressChanged);
    connect(effects, &EffectsHandler::screenAboutToLock, this, &FusionNavigationState::realDeactivate);

    // Plasma Fusion: the gestures follow KWin's tablet mode (laptop posture keeps the native edges).
    if (TabletModeManager *manager = kwinApp()->tabletModeManager()) {
        m_tabletMode = manager->effectiveTabletMode();
        // The QML binding read the default (false) before init(): tell it the real value.
        Q_EMIT tabletModeChanged();
        connect(manager, &TabletModeManager::tabletModeChanged, this, [this](bool tabletMode) {
            if (m_tabletMode != tabletMode) {
                m_tabletMode = tabletMode;
                Q_EMIT tabletModeChanged();
                updatePen();
            }
        });
    }

    // Plasma Fusion: the pen like a finger in tablet posture (TABLET2 PEN-2), and the test pen of
    // private test sessions (PLASMA_FUSION_TEST_PEN=1 only).
    m_penFilter = std::make_unique<FusionPenFilter>();
    updatePen();
    if (qEnvironmentVariableIsSet("PLASMA_FUSION_TEST_PEN")) {
        m_testPen = std::make_unique<FusionTestPen>();
    }

    refreshBorders();
}

void FusionNavigationState::updatePen()
{
    if (!m_penFilter) {
        return;
    }
    const KConfigGroup pen = KSharedConfig::openConfig(QStringLiteral("plasmafusionrc"))->group(QStringLiteral("Pen"));
    const bool finger = pen.readEntry("TabletPen", QStringLiteral("finger")) != QLatin1String("pen");
    m_penFilter->setDrawingApps(pen.readEntry("DrawingApps", FusionPenFilter::defaultDrawingApps()));
    const bool active = m_tabletMode && finger;
    if (active != m_penFilter->isActive()) {
        m_penFilter->setActive(active);
        qInfo("plasmafusion-navigation: pen %s", active ? "like a finger (tablet posture)" : "like a mouse");
    }
}

bool FusionNavigationState::gestureEnabled() const
{
    return m_gestureEnabled;
}

bool FusionNavigationState::tabletMode() const
{
    return m_tabletMode;
}

void FusionNavigationState::setGestureEnabled(bool gestureEnabled)
{
    m_gestureEnabled = gestureEnabled;
    Q_EMIT gestureEnabledChanged();
}

void FusionNavigationState::refreshBorders()
{
    if (!m_border) {
        return;
    }
    if (m_gestureEnabled) {
        m_border->setBorders({ElectricBorder::ElectricBottom});
    } else {
        m_border->setBorders({});
    }
}

bool FusionNavigationState::gestureInProgress() const
{
    return m_effectState->inProgress();
}

void FusionNavigationState::setGestureInProgress(bool gestureInProgress)
{
    if (m_status == Status::Stopped) {
        return;
    }
    m_effectState->setInProgress(gestureInProgress);
}

bool FusionNavigationState::wasInActiveTask() const
{
    return m_wasInActiveTask;
}

void FusionNavigationState::setWasInActiveTask(bool wasInActiveTask)
{
    if (m_wasInActiveTask != wasInActiveTask) {
        m_wasInActiveTask = wasInActiveTask;
        Q_EMIT wasInActiveTaskChanged();
    }
}

void FusionNavigationState::updateWasInActiveTask(KWin::Window *window)
{
    bool newWasInActiveTask = false;
    if (window) {
        newWasInActiveTask = !window->isDesktop();
    }
    setWasInActiveTask(newWasInActiveTask);
}

void FusionNavigationState::showDock()
{
    if (!m_effect) {
        return;
    }
    // The bottom touch border belongs to this effect in tablet posture, so KWin's own auto-hide edge
    // of the dock no longer sees short swipes: show the dock the same way it would, after the return
    // animation (the app is activated at its end).
    const auto delay = m_effect ? m_effect->animationTime(450ms) : 450ms;
    QTimer::singleShot(delay, this, &FusionNavigationState::revealDock);
}

void FusionNavigationState::revealDock()
{
    const auto windows = workspace()->windows();
    int docks = 0;
    int shown = 0;
    for (Window *window : windows) {
        if (!window->isDock()) {
            continue;
        }
        ++docks;
        if (!window->isHidden()) {
            continue;
        }
        const LogicalOutput *output = window->output();
        if (!output || window->frameGeometry().center().y() < output->geometry().center().y()) {
            continue;
        }
        window->showOnScreenEdge();
        ++shown;
    }
    qInfo("plasmafusion-navigation: showDock: %d dock window(s), %d shown", docks, shown);
}

qreal FusionNavigationState::touchXPosition() const
{
    return m_touchXPosition;
}

qreal FusionNavigationState::touchYPosition() const
{
    return m_touchYPosition;
}

qreal FusionNavigationState::xVelocity() const
{
    return m_xVelocity;
}

qreal FusionNavigationState::yVelocity() const
{
    return m_yVelocity;
}

qreal FusionNavigationState::totalSquaredVelocity() const
{
    return m_totalSquaredVelocity;
}

qreal FusionNavigationState::flickVelocityThreshold() const
{
    return m_flickVelocityThreshold;
}

void FusionNavigationState::setFlickVelocityThreshold(qreal flickVelocityThreshold)
{
    if (m_flickVelocityThreshold != flickVelocityThreshold) {
        m_flickVelocityThreshold = flickVelocityThreshold;
        Q_EMIT flickVelocityThresholdChanged();
    }
}

qreal FusionNavigationState::xPosition() const
{
    return m_xPosition;
}

void FusionNavigationState::setXPosition(qreal xPosition)
{
    if (m_xPosition != xPosition) {
        m_xPosition = xPosition;
        Q_EMIT xPositionChanged();
    }
}

qreal FusionNavigationState::yPosition() const
{
    return m_yPosition;
}

void FusionNavigationState::setYPosition(qreal yPosition)
{
    if (m_yPosition != yPosition) {
        m_yPosition = yPosition;
        Q_EMIT yPositionChanged();
    }
}

FusionNavigationState::Status FusionNavigationState::status() const
{
    return m_status;
}

void FusionNavigationState::setStatus(Status status)
{
    if (m_status != status) {
        if (status == Status::Inactive) {
            setYPosition(0);
        }
        m_status = status;
        Q_EMIT statusChanged();
    }
}

int FusionNavigationState::currentTaskIndex() const
{
    return m_currentTaskIndex;
}

void FusionNavigationState::setCurrentTaskIndex(int newTaskIndex)
{
    if (m_currentTaskIndex != newTaskIndex) {
        m_currentTaskIndex = newTaskIndex;
        Q_EMIT currentTaskIndexChanged();
    }
}

int FusionNavigationState::initialTaskIndex() const
{
    return m_initialTaskIndex;
}

void FusionNavigationState::setInitialTaskIndex(int newTaskIndex)
{
    if (m_initialTaskIndex != newTaskIndex) {
        m_initialTaskIndex = newTaskIndex;
        Q_EMIT initialTaskIndexChanged();
    }
}

FusionTaskModel *FusionNavigationState::taskModel() const
{
    return m_taskModel;
}

void FusionNavigationState::restartDoubleClickTimer()
{
    m_doubleClickTimer->restart();
}

void FusionNavigationState::calculateFilteredVelocity(qreal primaryDelta, qreal orthogonalDelta)
{
    static qreal prevPrimaryDelta = 0;
    static qreal prevOrthogonalDelta = 0;

    qint64 frameTime = 0;
    if (!m_frameTimer.isValid()) {
        prevPrimaryDelta = 0;
        prevOrthogonalDelta = 0;
        m_frameTimer.start();
        return;
    }
    frameTime = m_frameTimer.restart();
    if (frameTime == 0) {
        // Skip because otherwise we get NaN later on. Not sure why this triggers as often as it does
        return;
    }

    qreal framePrimaryDelta = primaryDelta - prevPrimaryDelta;
    qreal frameOrthogonalDelta = orthogonalDelta - prevOrthogonalDelta;
    prevPrimaryDelta = primaryDelta;
    prevOrthogonalDelta = orthogonalDelta;

    // Implements an exponentially weighted moving average (EWMA) filter (= exponential smoothing)
    // Smoothing factor is approximated each event to achieve a chosen filter time constant
    qreal smoothingFactor = std::min(frameTime / (1000 * m_filterTimeConstant), 0.8);
    m_yVelocity = m_yVelocity + smoothingFactor * (framePrimaryDelta / frameTime - m_yVelocity);
    m_xVelocity = m_xVelocity + smoothingFactor * (frameOrthogonalDelta / frameTime - m_xVelocity);
    m_totalSquaredVelocity = m_yVelocity * m_yVelocity + m_xVelocity * m_xVelocity;
    Q_EMIT velocityChanged();
}

void FusionNavigationState::processTouchPositionChanged(qreal primaryDelta, qreal orthogonalDelta)
{
    calculateFilteredVelocity(primaryDelta, orthogonalDelta);
    m_touchXPosition = orthogonalDelta;
    m_touchYPosition = primaryDelta;
    Q_EMIT touchPositionChanged();
}

qint64 FusionNavigationState::getElapsedTimeSinceStart()
{
    if (m_doubleClickTimer->isValid()) {
        return m_doubleClickTimer->elapsed();
    }
    return -1;
}

void FusionNavigationState::toggle()
{
    if (!m_effect) {
        return;
    }

    if (!m_effect->isRunning()) {
        restartDoubleClickTimer();
        activate();
    } else {
        deactivate(false);
    }
}

void FusionNavigationState::activate()
{
    if (!m_effect || effects->isScreenLocked()) {
        return;
    }

    m_effectState->setInProgress(false);
    invokeEffect();
}

void FusionNavigationState::deactivate(bool deactivateInstantly)
{
    if (!m_effect) {
        return;
    }

    const auto screens = effects->screens();
    for (const auto screen : screens) {
        if (QuickSceneView *view = m_effect->viewForScreen(screen)) {
            QMetaObject::invokeMethod(view->rootItem(), "hideAnimation");
        }
    }
    m_shutdownTimer->start(m_effect->animationTime(deactivateInstantly ? 0ms : 200ms));
}

void FusionNavigationState::realDeactivate()
{
    if (!m_effect || !m_effectState) {
        return;
    }

    m_effectState->setInProgress(false);
    setStatus(FusionNavigationState::Status::Inactive);
    m_effect->setRunning(false);
    setDBusState(false);
}

void FusionNavigationState::quickDeactivate()
{
    m_shutdownTimer->start(0);
}

void FusionNavigationState::setDBusState(bool active)
{
    // Plasma Mobile told its shell (org.kde.plasmashell /Mobile) here; Plasma Fusion has no such
    // interface yet.
    Q_UNUSED(active)
}

void FusionNavigationState::invokeEffect()
{
    if (!m_effect) {
        return;
    }
    setInitialTaskIndex(currentTaskIndex()); // TODO! this is only until the crashing bug is fixed and recency sorting is in
    m_effect->setRunning(true);
    setDBusState(true);
}
}
