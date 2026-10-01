// SPDX-FileCopyrightText: 2024 Luis Büchi <luis.buechi@server23.cc>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QAction>
#include <QElapsedTimer>
#include <effect/effect.h>
#include <effect/effecthandler.h>

namespace KWin
{

class FusionTouchBorderState : public QObject
{
    Q_OBJECT

public:
    FusionTouchBorderState(Effect *parent);

    bool inProgress() const;
    void setInProgress(bool inProgress);

    QAction *activateAction() const
    {
        return m_activateAction.get();
    }

Q_SIGNALS:
    void inProgressChanged();

private:
    bool m_inProgress = false;

    std::unique_ptr<QAction> m_activateAction;
};

class FusionTouchBorder : public QObject
{
    Q_OBJECT

public:
    FusionTouchBorder(FusionTouchBorderState *state);
    ~FusionTouchBorder();

    void setBorders(const QList<int> &borders);

    // Plasma Fusion gesture lock (TABLET2 G1): while locked, a swipe from the edge does nothing
    // unless it follows a blocked one within kUnlockWindow (iOS's deferred system gestures).
    void setLocked(bool locked);
    bool locked() const;

Q_SIGNALS:
    void touchPositionChanged(qreal primaryPosition, qreal orthogonalPosition);
    // A swipe was held back by the gesture lock.
    void gestureBlocked();

private:
    QList<ElectricBorder> m_touchBorderActivate;
    FusionTouchBorderState *m_state;
    bool m_locked = false;
    bool m_gestureActive = false;
    bool m_gestureBlocked = false;
    QElapsedTimer m_lastBlocked;
};

}
