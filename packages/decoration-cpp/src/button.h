/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include "glyphs.h"

#include <KDecoration3/DecorationButton>

#include <QPointer>
#include <QVariant>

class QTimer;
class QVariantAnimation;

namespace PlasmaFusion
{

class Decoration;

class Button : public KDecoration3::DecorationButton
{
    Q_OBJECT

public:
    Button(KDecoration3::DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent = nullptr);
    // Plugin-factory form (the Window Decorations settings page creates its button previews this way).
    explicit Button(QObject *parent, const QVariantList &args);
    ~Button() override;

    void paint(QPainter *painter, const QRectF &repaintArea) override;

    // Where the circle (or the app icon) is drawn; geometry() is the larger hit area around it.
    void setVisualRect(const QRectF &rect);
    QRectF visualRect() const
    {
        return m_visual;
    }

    // Snap-layouts trigger delay (TabsSnap / Windows boards: "hold for snap layouts").
    static constexpr int SnapDelay = 600;

protected:
    void mousePressEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;

private:
    void init();
    Decoration *fusionDecoration() const;
    Glyph glyph() const;
    void onHoveredChanged(bool hovered);
    void onSnapTimeout();
    void invokeSnapLayouts();
    void animateTo(QVariantAnimation *animation, qreal current, qreal target, int baseDuration);
    void paintIcon(QPainter *painter) const;
    void paintCircle(QPainter *painter) const;
    void paintDot(QPainter *painter) const;

    QRectF m_visual;
    QVariantAnimation *m_hoverAnimation = nullptr;
    qreal m_hover = 0;
    QVariantAnimation *m_pressAnimation = nullptr;
    qreal m_press = 0;
    QTimer *m_snapTimer = nullptr;
    enum class SnapMode {
        None,
        Hover,
        Hold,
    } m_snapMode = SnapMode::None;
    bool m_snapFiredOnHold = false;
};

} // namespace PlasmaFusion
