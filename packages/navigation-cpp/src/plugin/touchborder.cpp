// SPDX-FileCopyrightText: 2024 Luis Büchi <luis.buechi@server23.cc>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "touchborder.h"

namespace KWin
{

FusionTouchBorderState::FusionTouchBorderState(Effect *parent)
    : QObject(parent)
    , m_activateAction{std::make_unique<QAction>()}
{
    connect(m_activateAction.get(), &QAction::triggered, this, [this]() {
        if (m_inProgress) {
            setInProgress(false);
        }
    });
}

bool FusionTouchBorderState::inProgress() const
{
    return m_inProgress;
}

void FusionTouchBorderState::setInProgress(bool inProgress)
{
    if (!effects->hasActiveFullScreenEffect() || effects->activeFullScreenEffect() == parent()) {
        if (m_inProgress != inProgress) {
            m_inProgress = inProgress;
            Q_EMIT inProgressChanged();
        }
    }
}

FusionTouchBorder::FusionTouchBorder(FusionTouchBorderState *state)
    : QObject(state)
    , m_state(state)
{
    // The touch-up action ends every gesture (a release, or a cancel below the activation distance).
    connect(m_state->activateAction(), &QAction::triggered, this, [this]() {
        m_gestureActive = false;
        m_gestureBlocked = false;
    });
}

void FusionTouchBorder::setLocked(bool locked)
{
    m_locked = locked;
}

bool FusionTouchBorder::locked() const
{
    return m_locked;
}

FusionTouchBorder::~FusionTouchBorder()
{
    for (const ElectricBorder &border : std::as_const(m_touchBorderActivate)) {
        effects->unregisterTouchBorder(border, m_state->activateAction());
    }
}

void FusionTouchBorder::setBorders(const QList<int> &touchActivateBorders)
{
    for (const ElectricBorder &border : std::as_const(m_touchBorderActivate)) {
        effects->unregisterTouchBorder(border, m_state->activateAction());
    }
    m_touchBorderActivate.clear();

    for (const int &border : touchActivateBorders) {
        m_touchBorderActivate.append(ElectricBorder(border));
        effects->registerRealtimeTouchBorder(ElectricBorder(border),
                                             m_state->activateAction(),
                                             [this](ElectricBorder border, const QPointF &deltaProgress, const LogicalOutput *screen) {
                                                 Q_UNUSED(screen)
                                                 if (!m_gestureActive) {
                                                     // The first motion of a new swipe: let it through, or hold it
                                                     // back while locked unless one was held back just before.
                                                     m_gestureActive = true;
                                                     constexpr qint64 kUnlockWindow = 1500;
                                                     const bool second = m_lastBlocked.isValid() && m_lastBlocked.elapsed() < kUnlockWindow;
                                                     m_gestureBlocked = m_locked && !second;
                                                     if (m_gestureBlocked) {
                                                         m_lastBlocked.restart();
                                                         Q_EMIT gestureBlocked();
                                                     } else {
                                                         m_lastBlocked.invalidate();
                                                     }
                                                 }
                                                 if (m_gestureBlocked) {
                                                     return;
                                                 }
                                                 m_state->setInProgress(true);

                                                 if (border == ElectricTop || border == ElectricBottom) {
                                                     Q_EMIT touchPositionChanged(deltaProgress.y(), deltaProgress.x());
                                                 } else {
                                                     Q_EMIT touchPositionChanged(deltaProgress.x(), deltaProgress.y());
                                                 }
                                             });
    }
}

} // namespace KWin
