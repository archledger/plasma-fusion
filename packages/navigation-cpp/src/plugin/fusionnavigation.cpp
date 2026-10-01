// SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
// SPDX-FileCopyrightText: 2023 Devin Lin <devin@kde.org>
// SPDX-FileCopyrightText: 2024 Luis Büchi <luis.buechi@kdemail.net>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "fusionnavigation.h"

#include <QKeyEvent>
#include <QMetaObject>
#include <QQuickItem>
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
    m_effectState = new FusionTouchBorderState(parent);
    m_border = new FusionTouchBorder{m_effectState};
    m_taskModel = new FusionTaskModel{parent};
    m_effect = parent;

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
            }
        });
    }

    refreshBorders();
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
    if (effects->isScreenLocked()) {
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
    setInitialTaskIndex(currentTaskIndex()); // TODO! this is only until the crashing bug is fixed and recency sorting is in
    m_effect->setRunning(true);
    setDBusState(true);
}
}
