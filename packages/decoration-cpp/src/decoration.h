/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include "colors.h"
#include "fusionconfig.h"

#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButton>

#include <QList>
#include <QPointer>
#include <QVariant>

class QVariantAnimation;

namespace PlasmaFusion
{

class Button;

// Title-bar geometry for the current window state (logical px, snapped to the device grid).
struct Metrics {
    qreal titleHeight = 50; // Windows.dc.html spec 7: 50, 40 maximized, 32 tool windows
    qreal centerY = 24.5; // button / icon / caption centre (the board's 49 px row above its 1 px line)
    qreal circle = 28; // spec 3: 28 px circles
    qreal gap = 6; // 6 px apart
    qreal sideMargin = 10; // 10 px from the right (and left) edge
    qreal iconSize = 26; // spec 1: 26 px app icon
    qreal iconMargin = 16; // 16 px from the left edge
    qreal titleGap = 10; // title 10 px after the icon
    qreal glyph = 13; // 13 px glyphs, stroke 1.8 in the 24 grid
    // Left layout (Windows.dc.html:116-125): 13 px circles 7 px apart, the first 12 px from the left.
    qreal dot = 13;
    qreal dotGap = 7;
    qreal dotMargin = 12;
    qreal dotGlyph = 9;
    qreal radius = 13; // frame corner radius; the 1 px outline makes it 14 outside (spec 4)
    qreal outline = 1;
};

class Decoration : public KDecoration3::Decoration
{
    Q_OBJECT

public:
    explicit Decoration(QObject *parent = nullptr, const QVariantList &args = QVariantList());
    ~Decoration() override;

    bool init() override;
    void paint(QPainter *painter, const QRectF &repaintArea) override;

    const Colors &colors() const
    {
        return m_colors;
    }
    const Metrics &metrics() const
    {
        return m_metrics;
    }
    ButtonStyle buttonStyle() const
    {
        return m_style;
    }
    qreal activeProgress() const
    {
        return m_activeProgress;
    }
    qreal buttonsOpacity() const
    {
        return m_buttonsOpacity;
    }
    qreal groupHoverProgress() const
    {
        return m_groupHover;
    }
    int animationDuration(int base) const;
    bool isToolWindow() const;
    bool snapTriggerAllowed() const;
    qreal snap(qreal value) const; // round to the device pixel grid of the next scale
    qreal devicePixel() const;

    void buttonHoverChanged();
    // The hover trigger fires once per visit of the pointer to the decoration: the flyout's
    // shortcut toggles, so a second hover would close the flyout the first one opened.
    bool snapHoverFired() const
    {
        return m_snapHoverFired;
    }
    void setSnapHoverFired()
    {
        m_snapHoverFired = true;
    }

protected:
    void hoverEnterEvent(QHoverEvent *event) override;
    void hoverMoveEvent(QHoverEvent *event) override;
    void hoverLeaveEvent(QHoverEvent *event) override;

private Q_SLOTS:
    void reconfigure();
    void updateColors();
    void updateState();
    void updateButtonsLater();
    void createButtons();
    void layoutButtons();
    void updateShadow();
    void onActiveChanged();

private:
    bool isMaximizedFully() const;
    bool tiledEdges(Qt::Edges *edges) const; // tiled or maximized in one direction; edges on the screen border
    void cornerFlags(bool &tl, bool &tr, bool &br, bool &bl) const;
    void computeMetrics();
    void setPointerOverTitle(bool over);
    QVariant windowProperty(const char *name) const;
    void paintCaption(QPainter *painter) const;

    Colors m_colors;
    Metrics m_metrics;
    ButtonStyle m_style = ButtonStyle::RightGlyphs;
    QList<QPointer<Button>> m_left;
    QList<QPointer<Button>> m_right;
    bool m_layoutPending = false;

    QVariantAnimation *m_activeAnimation = nullptr;
    qreal m_activeProgress = 1;
    QVariantAnimation *m_buttonsAnimation = nullptr; // ShowOnHover
    qreal m_buttonsOpacity = 1;
    bool m_pointerOverTitle = false;
    QVariantAnimation *m_groupAnimation = nullptr; // LeftCircles group hover
    qreal m_groupHover = 0;
    bool m_groupHovered = false;
    bool m_snapHoverFired = false;
    qreal m_captionLeft = 0;
    qreal m_captionRight = 0;
};

} // namespace PlasmaFusion
