/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    pfdeco-preview: offline test tool for the Plasma Fusion decoration (not installed).

    Loads the built plugin through its plugin factory with a mock KDecoration3 bridge (the same
    private interface KWin and the Window Decorations settings page implement), drives it through
    window states, hover and press events, and composites what KWin would show (shadow nine-patch,
    client area clipped with the border radius, decoration image, outline) into PNG files at the
    given scales. It also checks the snap-layouts trigger against a fake kglobalaccel D-Bus service
    when a session bus is available (run it under dbus-run-session).

      pfdeco-preview --out DIR --scheme FILE.colors --name dark [--fonts DIR] [--backdrop PNG]
                     [--frame X,Y,W,H] [--scales 1,1.3333333]

    The caller sets XDG_CONFIG_HOME to a scratch directory; the tool writes plasmafusionrc and
    kwinrc there for each scene (kdeglobals should be the colour scheme, for the accent ring).
*/

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButton>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/DecorationShadow>
#include <KDecoration3/Private/DecoratedWindowPrivate>
#include <KDecoration3/Private/DecorationBridge>
#include <KDecoration3/Private/DecorationSettingsPrivate>

#include <KColorScheme>
#include <KConfig>
#include <KConfigGroup>
#include <KPluginFactory>
#include <KPluginMetaData>
#include <KSharedConfig>

#include <QCommandLineParser>
#include <QDBusConnection>
#include <QDir>
#include <QEventLoop>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QHoverEvent>
#include <QIcon>
#include <QImage>
#include <QJsonObject>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPluginLoader>
#include <QTextStream>
#include <QTimer>

#include <cmath>
#include <functional>
#include <memory>

using namespace KDecoration3;

namespace
{

QTextStream &out()
{
    static QTextStream s(stdout);
    return s;
}

void wait(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

struct WindowState {
    bool active = true;
    QString caption = QStringLiteral("Appearance");
    bool maximized = false;
    bool maximizedH = false;
    bool maximizedV = false;
    qreal width = 650;
    qreal height = 504;
    Qt::Edges edges;
    qreal scale = 1;
    bool shaded = false;
    bool keepAbove = false;
    bool keepBelow = false;
    bool onAllDesktops = false;
    bool maximizeable = true;
    bool closeable = true;
    bool minimizeable = true;
    bool contextHelp = false;
    bool shadeable = false;
    bool moveable = true;
    bool resizeable = true;
    bool modal = false;
    QIcon icon;
    KSharedConfig::Ptr scheme;
    // what the decoration requested
    int toggleMaximize = 0;
    int close = 0;
    int minimize = 0;
    int menu = 0;
};

class MockWindow : public DecoratedWindowPrivateV4
{
public:
    MockWindow(DecoratedWindow *client, Decoration *decoration, WindowState *state)
        : DecoratedWindowPrivateV4(client, decoration)
        , st(state)
    {
    }

    WindowState *st;

    DecoratedWindow *w()
    {
        return window();
    }

    bool isActive() const override
    {
        return st->active;
    }
    QString caption() const override
    {
        return st->caption;
    }
    bool isOnAllDesktops() const override
    {
        return st->onAllDesktops;
    }
    bool isShaded() const override
    {
        return st->shaded;
    }
    QIcon icon() const override
    {
        return st->icon;
    }
    bool isMaximized() const override
    {
        return st->maximized;
    }
    bool isMaximizedHorizontally() const override
    {
        return st->maximized || st->maximizedH;
    }
    bool isMaximizedVertically() const override
    {
        return st->maximized || st->maximizedV;
    }
    bool isKeepAbove() const override
    {
        return st->keepAbove;
    }
    bool isKeepBelow() const override
    {
        return st->keepBelow;
    }
    bool isCloseable() const override
    {
        return st->closeable;
    }
    bool isMaximizeable() const override
    {
        return st->maximizeable;
    }
    bool isMinimizeable() const override
    {
        return st->minimizeable;
    }
    bool providesContextHelp() const override
    {
        return st->contextHelp;
    }
    bool isModal() const override
    {
        return st->modal;
    }
    bool isShadeable() const override
    {
        return st->shadeable;
    }
    bool isMoveable() const override
    {
        return st->moveable;
    }
    bool isResizeable() const override
    {
        return st->resizeable;
    }
    qreal width() const override
    {
        return st->width;
    }
    qreal height() const override
    {
        return st->shaded ? 0 : st->height;
    }
    QSizeF size() const override
    {
        return QSizeF(width(), height());
    }
    QPalette palette() const override
    {
        return KColorScheme::createApplicationPalette(st->scheme);
    }
    Qt::Edges adjacentScreenEdges() const override
    {
        return st->edges;
    }
    qreal scale() const override
    {
        return st->scale;
    }
    qreal nextScale() const override
    {
        return st->scale;
    }
    void requestShowToolTip(const QString &) override
    {
    }
    void requestHideToolTip() override
    {
    }
    void requestClose() override
    {
        ++st->close;
    }
    void requestToggleMaximization(Qt::MouseButtons) override
    {
        ++st->toggleMaximize;
    }
    void requestMinimize() override
    {
        ++st->minimize;
    }
    void requestContextHelp() override
    {
    }
    void requestToggleOnAllDesktops() override
    {
    }
    void requestToggleShade() override
    {
    }
    void requestToggleKeepAbove() override
    {
    }
    void requestToggleKeepBelow() override
    {
    }
    void requestShowWindowMenu(const QRect &) override
    {
        ++st->menu;
    }
    QString windowClass() const override
    {
        return QStringLiteral("pfdeco-preview");
    }
    bool hasApplicationMenu() const override
    {
        return false;
    }
    bool isApplicationMenuActive() const override
    {
        return false;
    }
    void showApplicationMenu(int) override
    {
    }
    void requestShowApplicationMenu(const QRect &, int) override
    {
    }
    QString applicationMenuServiceName() const override
    {
        return QString();
    }
    QString applicationMenuObjectPath() const override
    {
        return QString();
    }
    void popup(const Positioner &, QMenu *) override
    {
    }
    bool isExcludedFromCapture() const override
    {
        return false;
    }
    void requestToggleExcludeFromCapture() override
    {
    }

    QColor color(ColorGroup group, ColorRole role) const override
    {
        // as KWin's DecorationPalette: the Header colour set
        const KColorScheme header(group == ColorGroup::Active ? QPalette::Active : QPalette::Inactive, KColorScheme::Header, st->scheme);
        switch (role) {
        case ColorRole::Frame:
        case ColorRole::TitleBar:
            return header.background().color();
        case ColorRole::Foreground:
            return header.foreground().color();
        }
        return QColor();
    }
};

QList<DecorationButtonType> s_left{DecorationButtonType::Menu};
QList<DecorationButtonType> s_right{DecorationButtonType::Minimize, DecorationButtonType::Maximize, DecorationButtonType::Close};
QFont s_font;

class MockSettings : public DecorationSettingsPrivateV2
{
public:
    explicit MockSettings(DecorationSettings *parent)
        : DecorationSettingsPrivateV2(parent)
    {
    }
    bool isOnAllDesktopsAvailable() const override
    {
        return true;
    }
    bool isAlphaChannelSupported() const override
    {
        return true;
    }
    bool isCloseOnDoubleClickOnMenu() const override
    {
        return false;
    }
    QList<DecorationButtonType> decorationButtonsLeft() const override
    {
        return s_left;
    }
    QList<DecorationButtonType> decorationButtonsRight() const override
    {
        return s_right;
    }
    BorderSize borderSize() const override
    {
        return BorderSize::None;
    }
    QFont font() const override
    {
        return s_font;
    }
    QFontMetricsF fontMetrics() const override
    {
        return QFontMetricsF(s_font);
    }
    bool isAlwaysShowExcludeFromCapture() const override
    {
        return false;
    }
};

class MockBridge : public DecorationBridge
{
public:
    WindowState *next = nullptr;
    MockWindow *last = nullptr;

    std::unique_ptr<DecoratedWindowPrivate> createClient(DecoratedWindow *client, Decoration *decoration) override
    {
        auto window = std::make_unique<MockWindow>(client, decoration, next);
        last = window.get();
        return window;
    }
    std::unique_ptr<DecorationSettingsPrivate> settings(DecorationSettings *parent) override
    {
        return std::make_unique<MockSettings>(parent);
    }
};

} // namespace

// kglobalaccel stand-in: counts invokeShortcut calls on /component/kwin.
class FakeAccel : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kglobalaccel.Component")
public:
    int count = 0;
    QStringList names;
public Q_SLOTS:
    Q_SCRIPTABLE void invokeShortcut(const QString &name)
    {
        ++count;
        names << name;
    }
};

namespace
{

QIcon makeAppIcon()
{
    // A stand-in for the board's AppIcon "settings" tile (blue rounded square with a light disc).
    QIcon icon;
    for (int size : {16, 22, 26, 32, 35, 48, 64}) {
        QImage img(size, size, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing);
        QLinearGradient g(0, 0, 0, size);
        g.setColorAt(0, QColor(96, 110, 140));
        g.setColorAt(1, QColor(58, 66, 90));
        p.setPen(Qt::NoPen);
        p.setBrush(g);
        p.drawRoundedRect(QRectF(0, 0, size, size), size * 0.25, size * 0.25);
        p.setBrush(QColor(236, 239, 246));
        p.drawEllipse(QRectF(size * 0.3, size * 0.3, size * 0.4, size * 0.4));
        p.end();
        icon.addPixmap(QPixmap::fromImage(img));
    }
    return icon;
}

QPainterPath roundedPath(const QRectF &r, const BorderRadius &radius)
{
    QPainterPath p;
    const qreal tl = radius.topLeft(), tr = radius.topRight(), br = radius.bottomRight(), bl = radius.bottomLeft();
    p.moveTo(r.left() + tl, r.top());
    p.lineTo(r.right() - tr, r.top());
    if (tr > 0) {
        p.arcTo(QRectF(r.right() - 2 * tr, r.top(), 2 * tr, 2 * tr), 90, -90);
    }
    p.lineTo(r.right(), r.bottom() - br);
    if (br > 0) {
        p.arcTo(QRectF(r.right() - 2 * br, r.bottom() - 2 * br, 2 * br, 2 * br), 0, -90);
    }
    p.lineTo(r.left() + bl, r.bottom());
    if (bl > 0) {
        p.arcTo(QRectF(r.left(), r.bottom() - 2 * bl, 2 * bl, 2 * bl), 270, -90);
    }
    p.lineTo(r.left(), r.top() + tl);
    if (tl > 0) {
        p.arcTo(QRectF(r.left(), r.top(), 2 * tl, 2 * tl), 180, -90);
    }
    p.closeSubpath();
    return p;
}

// What KWin draws for one window: shadow tiles, client (clipped), decoration, outline.
void composite(QPainter &p, Decoration *deco, const QPointF &pos, const QColor &clientColor)
{
    const QRectF frame(pos, deco->size());
    // shadow nine-patch (the centre is not drawn, as in KWin)
    if (const auto shadow = deco->shadow()) {
        const QImage img = shadow->shadow();
        const QMarginsF pad = shadow->padding();
        const QRectF outer = frame.marginsAdded(pad);
        const QRectF tl = shadow->topLeftGeometry(), t = shadow->topGeometry(), tr = shadow->topRightGeometry();
        const QRectF r = shadow->rightGeometry(), br = shadow->bottomRightGeometry(), b = shadow->bottomGeometry();
        const QRectF bl = shadow->bottomLeftGeometry(), l = shadow->leftGeometry();
        p.drawImage(QRectF(outer.topLeft(), tl.size()), img, tl);
        p.drawImage(QRectF(QPointF(outer.right() - tr.width(), outer.top()), tr.size()), img, tr);
        p.drawImage(QRectF(QPointF(outer.right() - br.width(), outer.bottom() - br.height()), br.size()), img, br);
        p.drawImage(QRectF(QPointF(outer.left(), outer.bottom() - bl.height()), bl.size()), img, bl);
        p.drawImage(QRectF(outer.left() + tl.width(), outer.top(), outer.width() - tl.width() - tr.width(), t.height()), img, t);
        p.drawImage(QRectF(outer.left() + bl.width(), outer.bottom() - b.height(), outer.width() - bl.width() - br.width(), b.height()), img, b);
        p.drawImage(QRectF(outer.left(), outer.top() + tl.height(), l.width(), outer.height() - tl.height() - bl.height()), img, l);
        p.drawImage(QRectF(outer.right() - r.width(), outer.top() + tr.height(), r.width(), outer.height() - tr.height() - br.height()), img, r);
    }
    const qreal dpr = p.device()->devicePixelRatioF();
    // decoration image
    QImage decoImage((deco->size() * dpr).toSize(), QImage::Format_ARGB32_Premultiplied);
    decoImage.setDevicePixelRatio(dpr);
    decoImage.fill(Qt::transparent);
    {
        QPainter dp(&decoImage);
        deco->paint(&dp, QRectF(QPointF(0, 0), deco->size()));
    }
    p.save();
    p.setRenderHint(QPainter::Antialiasing);
    p.setClipPath(roundedPath(frame, deco->borderRadius()));
    p.fillRect(QRectF(frame.left(), frame.top() + deco->borderTop(), frame.width(), frame.height() - deco->borderTop()), clientColor);
    p.drawImage(frame.topLeft(), decoImage);
    p.restore();
    const BorderOutline outline = deco->borderOutline();
    if (!outline.isNull()) {
        const qreal t = outline.thickness();
        const BorderRadius ri = outline.radius();
        const BorderRadius ro(ri.topLeft() > 0 ? ri.topLeft() + t : 0,
                              ri.topRight() > 0 ? ri.topRight() + t : 0,
                              ri.bottomRight() > 0 ? ri.bottomRight() + t : 0,
                              ri.bottomLeft() > 0 ? ri.bottomLeft() + t : 0);
        QPainterPath ring = roundedPath(frame.adjusted(-t, -t, t, t), ro);
        ring.addPath(roundedPath(frame, ri));
        ring.setFillRule(Qt::OddEvenFill);
        p.save();
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(Qt::NoPen);
        p.setBrush(outline.color());
        p.drawPath(ring);
        p.restore();
    }
}

void writeConfig(const QString &style, bool snapOnHover, bool snapScript)
{
    KConfig fusion(QStringLiteral("plasmafusionrc"), KConfig::NoGlobals);
    KConfigGroup deco(&fusion, QStringLiteral("Decoration"));
    deco.writeEntry("ButtonStyle", style);
    deco.writeEntry("SnapLayoutsOnHover", snapOnHover);
    fusion.sync();
    KConfig kwin(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    KConfigGroup plugins(&kwin, QStringLiteral("Plugins"));
    plugins.writeEntry("plasmafusion-snapEnabled", snapScript);
    kwin.sync();
}

struct Harness {
    KPluginFactory *factory = nullptr;
    MockBridge bridge;
    std::shared_ptr<DecorationSettings> settings;
    KSharedConfig::Ptr scheme;
    KSharedConfig::Ptr otherScheme; // for the palette-change check
    QString outDir;
    QString name;
    QImage backdrop;
    QRectF frame;
    QColor clientColor;
    int failures = 0;

    struct Instance {
        std::unique_ptr<QObject> owner;
        Decoration *deco = nullptr;
        MockWindow *window = nullptr;
        std::unique_ptr<WindowState> state;
    };

    Instance create(std::unique_ptr<WindowState> state, bool tool = false, const QRectF &tile = QRectF())
    {
        Instance in;
        in.state = std::move(state);
        in.state->scheme = scheme;
        if (in.state->icon.isNull()) {
            in.state->icon = makeAppIcon();
        }
        in.owner = std::make_unique<QObject>();
        in.owner->setProperty("utility", tool);
        in.owner->setProperty("toolbar", false);
        in.owner->setProperty("normalWindow", !tool);
        in.owner->setProperty("specialWindow", false);
        if (tile.isValid()) {
            // KWin's window.tile (a KWin::Tile with relativeGeometry), for tiles with padding
            auto *t = new QObject(in.owner.get());
            t->setProperty("relativeGeometry", tile);
            in.owner->setProperty("tile", QVariant::fromValue<QObject *>(t));
        }
        bridge.next = in.state.get();
        const QVariantMap args{{QStringLiteral("bridge"), QVariant::fromValue(static_cast<DecorationBridge *>(&bridge))}};
        in.deco = factory->create<Decoration>(in.owner.get(), QVariantList{args});
        if (!in.deco) {
            out() << "FAIL cannot create the decoration\n";
            ++failures;
            return in;
        }
        in.window = bridge.last;
        in.deco->setSettings(settings);
        in.deco->create();
        QObject::connect(in.deco, &Decoration::nextStateChanged, in.deco, [deco = in.deco](auto state) {
            deco->apply(state->clone());
        });
        in.deco->init();
        in.deco->apply(in.deco->nextState()->clone());
        return in;
    }

    void destroy(Instance &in)
    {
        // the decoration is a child of the owner
        in.owner.reset();
        in.deco = nullptr;
        in.window = nullptr;
    }

    void hover(Decoration *deco, const QPointF &pos)
    {
        QHoverEvent enter(QEvent::HoverEnter, pos, pos, QPointF(-1, -1));
        QCoreApplication::sendEvent(deco, &enter);
        QHoverEvent move(QEvent::HoverMove, pos, pos, pos);
        QCoreApplication::sendEvent(deco, &move);
    }
    void leave(Decoration *deco)
    {
        QHoverEvent e(QEvent::HoverLeave, QPointF(-1, -1), QPointF(-1, -1), QPointF(-1, -1));
        QCoreApplication::sendEvent(deco, &e);
    }
    void press(Decoration *deco, const QPointF &pos, Qt::MouseButton button = Qt::LeftButton)
    {
        QMouseEvent e(QEvent::MouseButtonPress, pos, pos, button, button, Qt::NoModifier);
        QCoreApplication::sendEvent(deco, &e);
    }
    void release(Decoration *deco, const QPointF &pos, Qt::MouseButton button = Qt::LeftButton)
    {
        QMouseEvent e(QEvent::MouseButtonRelease, pos, pos, button, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(deco, &e);
    }

    QPointF buttonCenter(Decoration *deco, DecorationButtonType type)
    {
        const auto buttons = deco->findChildren<DecorationButton *>();
        for (auto *b : buttons) {
            if (b->type() == type && b->isVisible()) {
                return b->geometry().center();
            }
        }
        return QPointF(-100, -100);
    }

    void render(Decoration *deco, const QString &scene, qreal scale, const QRectF &where)
    {
        const QSize logical = backdrop.isNull() ? QSize(1440, 900) : backdrop.size();
        QImage canvas((QSizeF(logical) * scale).toSize(), QImage::Format_ARGB32_Premultiplied);
        canvas.setDevicePixelRatio(scale);
        QPainter p(&canvas);
        p.setRenderHint(QPainter::SmoothPixmapTransform);
        if (!backdrop.isNull()) {
            p.drawImage(QRectF(QPointF(0, 0), QSizeF(logical)), backdrop);
        } else {
            p.fillRect(QRectF(QPointF(0, 0), QSizeF(logical)), QColor(16, 20, 42));
        }
        composite(p, deco, where.topLeft(), clientColor);
        p.end();
        const QString file = QStringLiteral("%1/%2-%3-s%4.png").arg(outDir, name, scene, scale == 1 ? QStringLiteral("1") : QStringLiteral("4-3"));
        canvas.save(file);
    }

    void check(bool ok, const QString &what)
    {
        out() << (ok ? "PASS " : "FAIL ") << name << ": " << what << "\n";
        out().flush();
        if (!ok) {
            ++failures;
        }
    }
};

} // namespace

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addOption({QStringLiteral("out"), QStringLiteral("output directory"), QStringLiteral("dir")});
    parser.addOption({QStringLiteral("scheme"), QStringLiteral("colour scheme file"), QStringLiteral("file")});
    parser.addOption({QStringLiteral("other-scheme"), QStringLiteral("second colour scheme (palette-change check)"), QStringLiteral("file")});
    parser.addOption({QStringLiteral("name"), QStringLiteral("file name prefix"), QStringLiteral("name"), QStringLiteral("dark")});
    parser.addOption({QStringLiteral("fonts"), QStringLiteral("directory with .ttf files to load"), QStringLiteral("dir")});
    parser.addOption({QStringLiteral("backdrop"), QStringLiteral("1440x900 background image"), QStringLiteral("png")});
    parser.addOption({QStringLiteral("frame"), QStringLiteral("window frame X,Y,W,H"), QStringLiteral("rect"), QStringLiteral("549,263,650,504")});
    parser.addOption({QStringLiteral("client"), QStringLiteral("client colour"), QStringLiteral("color"), QStringLiteral("#1b2031")});
    parser.addOption({QStringLiteral("scales"), QStringLiteral("comma separated"), QStringLiteral("list"), QStringLiteral("1,1.3333333")});
    parser.addOption({QStringLiteral("decoration-plugin"), QStringLiteral("plugin file"), QStringLiteral("file"), QStringLiteral(PFDECO_PLUGIN)});
    parser.addOption({QStringLiteral("font"),
                      QStringLiteral("title font (QFont string)"),
                      QStringLiteral("font"),
                      QStringLiteral("Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0")});
    parser.process(app);

    if (parser.isSet(QStringLiteral("fonts"))) {
        QDir dir(parser.value(QStringLiteral("fonts")));
        for (const QString &f : dir.entryList({QStringLiteral("*.ttf")}, QDir::Files)) {
            QFontDatabase::addApplicationFont(dir.filePath(f));
        }
    }
    s_font.fromString(parser.value(QStringLiteral("font")));
    if (s_font.pointSizeF() > 0) {
        // KWin on Wayland: 96 dpi logical, so 10.5 pt = 14 px (the offscreen platform uses another dpi)
        s_font.setPixelSize(int(std::lround(s_font.pointSizeF() * 96.0 / 72.0)));
    }
    out() << "title font: " << s_font.toString() << " resolved family " << QFontInfo(s_font).family() << " style " << QFontInfo(s_font).styleName() << " px "
          << QFontInfo(s_font).pixelSize() << "\n";

    const QString pluginPath = QFileInfo(parser.value(QStringLiteral("decoration-plugin"))).absoluteFilePath();
    QPluginLoader loader(pluginPath);
    auto *factory = qobject_cast<KPluginFactory *>(loader.instance());
    if (!factory) {
        out() << "FAIL cannot load plugin " << pluginPath << ": " << loader.errorString() << "\n";
        return 2;
    }
    // KWin takes the plugin id from the file name (the embedded metadata has no explicit Id).
    const KPluginMetaData meta(loader);
    out() << "plugin id: " << meta.pluginId() << " (" << meta.name() << ")\n";

    Harness h;
    h.factory = factory;
    h.settings = std::make_shared<DecorationSettings>(&h.bridge);
    h.scheme = KSharedConfig::openConfig(parser.value(QStringLiteral("scheme")), KConfig::SimpleConfig);
    if (parser.isSet(QStringLiteral("other-scheme"))) {
        h.otherScheme = KSharedConfig::openConfig(parser.value(QStringLiteral("other-scheme")), KConfig::SimpleConfig);
    }
    h.outDir = parser.value(QStringLiteral("out"));
    h.name = parser.value(QStringLiteral("name"));
    QDir().mkpath(h.outDir);
    if (parser.isSet(QStringLiteral("backdrop"))) {
        h.backdrop = QImage(parser.value(QStringLiteral("backdrop"))).convertToFormat(QImage::Format_ARGB32_Premultiplied);
    }
    const QStringList fr = parser.value(QStringLiteral("frame")).split(QLatin1Char(','));
    h.frame = QRectF(fr.value(0).toDouble(), fr.value(1).toDouble(), fr.value(2).toDouble(), fr.value(3).toDouble());
    h.clientColor = QColor(parser.value(QStringLiteral("client")));

    FakeAccel accel;
    bool dbus = false;
    {
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (bus.isConnected() && bus.registerService(QStringLiteral("org.kde.kglobalaccel"))
            && bus.registerObject(QStringLiteral("/component/kwin"), &accel, QDBusConnection::ExportScriptableSlots)) {
            dbus = true;
        }
    }
    out() << "fake kglobalaccel on the session bus: " << (dbus ? "yes" : "no (snap checks skipped)") << "\n";

    QList<qreal> scales;
    for (const QString &s : parser.value(QStringLiteral("scales")).split(QLatin1Char(','))) {
        scales << s.toDouble();
    }

    auto base = [&h](qreal scale) {
        auto st = std::make_unique<WindowState>();
        st->width = h.frame.width();
        st->height = h.frame.height() - 50;
        st->scale = scale;
        return st;
    };

    for (qreal scale : scales) {
        using Setup = std::function<void(WindowState &)>;
        using Action = std::function<void(Harness &, Decoration *)>;
        struct Scene {
            QString name;
            QString style;
            bool tool;
            Setup setup;
            Action action;
            QRectF tile = QRectF();
        };
        const QList<Scene> scenes{
            {QStringLiteral("01-active"), QStringLiteral("RightGlyphs"), false, nullptr, nullptr},
            {QStringLiteral("02-inactive"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.active = false;
             },
             nullptr},
            {QStringLiteral("03-hover-maximize"),
             QStringLiteral("RightGlyphs"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 h.hover(d, h.buttonCenter(d, DecorationButtonType::Maximize));
             }},
            {QStringLiteral("04-hover-close"),
             QStringLiteral("RightGlyphs"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 h.hover(d, h.buttonCenter(d, DecorationButtonType::Close));
             }},
            {QStringLiteral("05-pressed-minimize"),
             QStringLiteral("RightGlyphs"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 const QPointF c = h.buttonCenter(d, DecorationButtonType::Minimize);
                 h.hover(d, c);
                 h.press(d, c);
             }},
            {QStringLiteral("06-inactive-hover-close"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.active = false;
             },
             [](Harness &h, Decoration *d) {
                 h.hover(d, h.buttonCenter(d, DecorationButtonType::Close));
             }},
            {QStringLiteral("07-maximized"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.maximized = true;
             },
             nullptr},
            {QStringLiteral("08-tiled-left"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.edges = Qt::LeftEdge | Qt::TopEdge | Qt::BottomEdge;
             },
             nullptr},
            {QStringLiteral("09-tiled-right"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.edges = Qt::RightEdge | Qt::TopEdge | Qt::BottomEdge;
             },
             nullptr},
            {QStringLiteral("09b-tiled-left-gaps"), QStringLiteral("RightGlyphs"), false, nullptr, nullptr, QRectF(0, 0, 0.5, 1)},
            {QStringLiteral("09c-tiled-quarter-gaps"), QStringLiteral("RightGlyphs"), false, nullptr, nullptr, QRectF(0.5, 0.5, 0.5, 0.5)},
            {QStringLiteral("10-tool"),
             QStringLiteral("RightGlyphs"),
             true,
             [](WindowState &s) {
                 s.caption = QStringLiteral("Layers");
             },
             nullptr},
            {QStringLiteral("11-left"), QStringLiteral("LeftCircles"), false, nullptr, nullptr},
            {QStringLiteral("12-left-hover"),
             QStringLiteral("LeftCircles"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 h.hover(d, h.buttonCenter(d, DecorationButtonType::Minimize));
             }},
            {QStringLiteral("13-left-inactive"),
             QStringLiteral("LeftCircles"),
             false,
             [](WindowState &s) {
                 s.active = false;
             },
             nullptr},
            {QStringLiteral("14-showonhover-away"), QStringLiteral("ShowOnHover"), false, nullptr, nullptr},
            {QStringLiteral("15-showonhover-over"),
             QStringLiteral("ShowOnHover"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 h.hover(d, QPointF(300, 20));
             }},
            {QStringLiteral("16-long-title"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.caption = QStringLiteral("A very long document title that does not fit into the title bar of this window at all — Kate");
             },
             nullptr},
            {QStringLiteral("17-disabled"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.maximizeable = false;
                 s.minimizeable = false;
             },
             nullptr},
            {QStringLiteral("18-shaded"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.shaded = true;
             },
             nullptr},
            {QStringLiteral("19-maximized-left"),
             QStringLiteral("LeftCircles"),
             false,
             [](WindowState &s) {
                 s.maximized = true;
             },
             nullptr},
        };

        for (const Scene &scene : scenes) {
            writeConfig(scene.style, true, true);
            wait(5); // lets the per-pass config throttle expire
            auto st = base(scale);
            if (scene.setup) {
                scene.setup(*st);
            }
            const bool maximized = st->maximized;
            QRectF where = h.frame;
            if (maximized) {
                where = QRectF(0, 34, h.backdrop.isNull() ? 1440 : h.backdrop.width(), 600);
                st->width = where.width();
                st->height = where.height() - 40;
            }
            auto in = h.create(std::move(st), scene.tool, scene.tile);
            if (!in.deco) {
                continue;
            }
            if (scene.action) {
                scene.action(h, in.deco);
            }
            wait(350);
            h.render(in.deco, scene.name, scale, where);
            h.destroy(in);
        }

        // Extra buttons in the same style, a toggled keep-above and context help.
        {
            s_left = {DecorationButtonType::Menu, DecorationButtonType::OnAllDesktops};
            s_right = {DecorationButtonType::ContextHelp,
                       DecorationButtonType::KeepAbove,
                       DecorationButtonType::KeepBelow,
                       DecorationButtonType::Shade,
                       DecorationButtonType::ApplicationMenu,
                       DecorationButtonType::Spacer,
                       DecorationButtonType::Minimize,
                       DecorationButtonType::Maximize,
                       DecorationButtonType::Close};
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto st = base(scale);
            st->keepAbove = true;
            st->contextHelp = true;
            st->shadeable = true;
            auto in = h.create(std::move(st));
            if (in.deco) {
                h.hover(in.deco, h.buttonCenter(in.deco, DecorationButtonType::KeepBelow));
                wait(350);
                h.render(in.deco, QStringLiteral("20-extra-buttons"), scale, h.frame);
                h.destroy(in);
            }
            s_left = {DecorationButtonType::Menu};
            s_right = {DecorationButtonType::Minimize, DecorationButtonType::Maximize, DecorationButtonType::Close};
        }

        // Geometry checks against the board (Windows.dc.html anatomy), at this scale.
        {
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto in = h.create(base(scale));
            if (in.deco) {
                const qreal w = in.deco->size().width();
                auto *deco = in.deco;
                const auto buttons = deco->findChildren<DecorationButton *>();
                QRectF close, maximize, minimize, menu;
                // hit areas are the circle plus half the gap on each side: same centre as the circle
                for (auto *b : buttons) {
                    const QRectF g = b->geometry();
                    switch (b->type()) {
                    case DecorationButtonType::Close:
                        close = g;
                        break;
                    case DecorationButtonType::Maximize:
                        maximize = g;
                        break;
                    case DecorationButtonType::Minimize:
                        minimize = g;
                        break;
                    case DecorationButtonType::Menu:
                        menu = g;
                        break;
                    default:
                        break;
                    }
                }
                const qreal tol = 1.0 / scale + 0.01;
                h.check(std::abs(in.deco->borderTop() - 50) <= tol,
                        QStringLiteral("title bar %1 px (board 50) at scale %2").arg(in.deco->borderTop()).arg(scale));
                h.check(std::abs((w - close.center().x()) - 24) <= 0.01,
                        QStringLiteral("close centre %1 px from the right (board 10 + 14 = 24)").arg(w - close.center().x()));
                h.check(std::abs(close.center().x() - maximize.center().x() - 34) <= 0.01,
                        QStringLiteral("circle pitch %1 (board 28 + 6 = 34)").arg(close.center().x() - maximize.center().x()));
                h.check(std::abs((w - maximize.center().x()) - 58) <= 0.01,
                        QStringLiteral("maximize centre %1 px from the right (snap flyout expects 58)").arg(w - maximize.center().x()));
                h.check(std::abs(menu.center().x() - (16 + 13)) <= 0.01, QStringLiteral("icon centre x %1 (board 16 + 13 = 29)").arg(menu.center().x()));
                h.check(in.deco->borderLeft() == 0 && in.deco->borderRight() == 0 && in.deco->borderBottom() == 0, QStringLiteral("no side/bottom borders"));
                const BorderRadius r = in.deco->borderRadius();
                h.check(r.bottomLeft() > 12 && r.bottomRight() > 12, QStringLiteral("bottom clip radius %1").arg(r.bottomLeft()));
                const BorderOutline o = in.deco->borderOutline();
                h.check(!o.isNull() && o.radius().topLeft() + o.thickness() > 13.5 && o.radius().topLeft() + o.thickness() < 14.5,
                        QStringLiteral("outline outer radius %1 (board 14)").arg(o.radius().topLeft() + o.thickness()));
                h.check(in.deco->resizeOnlyBorders().left() >= 7.5 && in.deco->resizeOnlyBorders().bottom() >= 7.5,
                        QStringLiteral("resize band %1 px (board 8)").arg(in.deco->resizeOnlyBorders().left()));
                h.check(bool(in.deco->shadow()), QStringLiteral("active shadow present"));
                if (const auto shadow = in.deco->shadow()) {
                    // The bottom profile under the middle of the window against the CSS model
                    // (Gaussian, sigma = blur / 2, shape = frame + 1 px outline moved down by dy).
                    const QImage img = shadow->shadow();
                    const QMarginsF pad = shadow->padding();
                    const int col = int(shadow->innerShadowRect().x());
                    const qreal frameBottom = img.height() - pad.bottom();
                    const bool dark = in.window->palette().color(QPalette::Window).lightness() < 128;
                    const qreal opacity = dark ? 0.55 : 0.22;
                    const qreal sigma = 45;
                    const qreal shapeBottom = frameBottom + 1 + 34;
                    qreal worst = 0;
                    for (int row = int(frameBottom); row < img.height(); ++row) {
                        const qreal y = row + 0.5;
                        const qreal model = opacity * 0.5 * std::erfc((y - shapeBottom) / (sigma * std::sqrt(2.0)));
                        const qreal got = qAlpha(img.pixel(col, row)) / 255.0;
                        worst = std::max(worst, std::abs(got - model));
                    }
                    h.check(worst < 0.02, QStringLiteral("shadow below the window within %1 alpha of the CSS Gaussian").arg(worst, 0, 'f', 4));
                }
                h.destroy(in);
            }
            auto st = base(scale);
            st->maximized = true;
            auto mx = h.create(std::move(st));
            if (mx.deco) {
                h.check(std::abs(mx.deco->borderTop() - 40) <= 1.0 / scale + 0.01,
                        QStringLiteral("maximized title bar %1 (board 40)").arg(mx.deco->borderTop()));
                h.check(!mx.deco->shadow() && mx.deco->borderOutline().isNull() && mx.deco->borderRadius().bottomLeft() == 0,
                        QStringLiteral("maximized: no shadow, no outline, square"));
                h.destroy(mx);
            }
            auto padded = h.create(base(scale), false, QRectF(0, 0, 0.5, 1));
            if (padded.deco) {
                const BorderRadius r = padded.deco->borderRadius();
                const BorderRadius o = padded.deco->borderOutline().radius();
                h.check(r.bottomLeft() > 12 && r.bottomRight() == 0 && o.topLeft() == 0 && o.topRight() == 0 && o.bottomLeft() > 12 && o.bottomRight() == 0,
                        QStringLiteral("left tile with gaps: only the outer bottom corner is round"));
                h.destroy(padded);
            }
            auto tool = h.create(base(scale), true);
            if (tool.deco) {
                h.check(std::abs(tool.deco->borderTop() - 32) <= 1.0 / scale + 0.01,
                        QStringLiteral("tool window title bar %1 (board 32)").arg(tool.deco->borderTop()));
                h.destroy(tool);
            }
        }

        // State changes on a live decoration: no crash, borders follow.
        {
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto in = h.create(base(scale));
            if (in.deco) {
                auto *win = in.window;
                auto *dw = win->w();
                for (int i = 0; i < 3; ++i) {
                    in.state->maximized = true;
                    Q_EMIT dw->maximizedChanged(true);
                    in.state->active = false;
                    Q_EMIT dw->activeChanged(false);
                    in.state->edges = Qt::LeftEdge | Qt::TopEdge | Qt::BottomEdge;
                    Q_EMIT dw->adjacentScreenEdgesChanged(in.state->edges);
                    in.state->maximized = false;
                    Q_EMIT dw->maximizedChanged(false);
                    in.state->width = 200 + 50 * i;
                    Q_EMIT dw->widthChanged(in.state->width);
                    Q_EMIT dw->sizeChanged(QSizeF(in.state->width, in.state->height));
                    in.state->active = true;
                    Q_EMIT dw->activeChanged(true);
                    in.state->caption = QString();
                    Q_EMIT dw->captionChanged(QString());
                    in.state->edges = {};
                    Q_EMIT dw->adjacentScreenEdgesChanged({});
                    in.state->width = 40; // narrower than the buttons
                    Q_EMIT dw->widthChanged(in.state->width);
                    in.state->shaded = true;
                    Q_EMIT dw->shadedChanged(true);
                    in.state->shaded = false;
                    Q_EMIT dw->shadedChanged(false);
                    Q_EMIT dw->paletteChanged(win->palette());
                    Q_EMIT h.settings->reconfigured();
                    wait(30);
                    QImage img(QSize(260, 60), QImage::Format_ARGB32_Premultiplied);
                    img.fill(Qt::transparent);
                    QPainter p(&img);
                    in.deco->paint(&p, QRectF(0, 0, 260, 60));
                }
                h.check(std::abs(in.deco->borderTop() - 50) <= 1.0 / scale + 0.01,
                        QStringLiteral("state churn survived, title bar back to %1").arg(in.deco->borderTop()));
                // A window that switches to another colour scheme (per-window schemes, or the global
                // Dark <-> Light switch): the title bar follows the new Header colour.
                if (h.otherScheme) {
                    in.state->width = 650;
                    Q_EMIT dw->widthChanged(in.state->width);
                    const KSharedConfig::Ptr previous = in.state->scheme;
                    in.state->scheme = h.otherScheme;
                    Q_EMIT dw->paletteChanged(win->palette());
                    wait(250);
                    QImage img(QSize(650, 60), QImage::Format_ARGB32_Premultiplied);
                    img.fill(Qt::transparent);
                    {
                        QPainter p(&img);
                        in.deco->paint(&p, QRectF(0, 0, 650, 60));
                    }
                    const QColor expected = KColorScheme(QPalette::Active, KColorScheme::Header, h.otherScheme).background().color();
                    const QColor got = img.pixelColor(300, 5);
                    h.check(std::abs(got.red() - expected.red()) <= 1 && std::abs(got.blue() - expected.blue()) <= 1,
                            QStringLiteral("palette change: title bar %1 follows the new scheme %2").arg(got.name(), expected.name()));
                    in.state->scheme = previous;
                }
                h.destroy(in);
            }
        }

        // Snap-layouts trigger (contract: hover or hold maximize 600 ms -> invokeShortcut).
        if (dbus) {
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto in = h.create(base(scale));
            if (in.deco) {
                const QPointF c = h.buttonCenter(in.deco, DecorationButtonType::Maximize);
                accel.count = 0;
                h.hover(in.deco, c);
                wait(450);
                h.check(accel.count == 0, QStringLiteral("hover: nothing before 600 ms"));
                wait(400);
                h.check(accel.count == 1 && accel.names.value(0) == QStringLiteral("Plasma Fusion: Snap Layouts"),
                        QStringLiteral("hover 600 ms invokes 'Plasma Fusion: Snap Layouts' (%1 calls)").arg(accel.count));
                wait(700);
                h.check(accel.count == 1, QStringLiteral("hover: fires once per hover"));
                // off the button onto the title and back, without leaving the decoration: the
                // flyout's shortcut toggles, so no second trigger
                QHoverEvent away(QEvent::HoverMove, QPointF(200, 20), QPointF(200, 20), c);
                QCoreApplication::sendEvent(in.deco, &away);
                wait(50);
                QHoverEvent back(QEvent::HoverMove, c, c, QPointF(200, 20));
                QCoreApplication::sendEvent(in.deco, &back);
                wait(800);
                h.check(accel.count == 1, QStringLiteral("hover: no second trigger until the pointer leaves the title bar"));
                h.leave(in.deco);
                wait(50);
                h.hover(in.deco, c);
                wait(800);
                h.check(accel.count == 2, QStringLiteral("hover: fires again after leaving (%1 calls)").arg(accel.count));
                h.leave(in.deco);
                wait(50);
                // hold
                accel.count = 0;
                const int before = in.state->toggleMaximize;
                h.hover(in.deco, c);
                wait(100);
                h.press(in.deco, c);
                wait(750);
                h.check(accel.count == 1, QStringLiteral("hold 600 ms invokes the shortcut (%1 calls)").arg(accel.count));
                h.release(in.deco, c);
                wait(100);
                h.check(in.state->toggleMaximize == before, QStringLiteral("release after the hold does not toggle maximize"));
                // a quick click still maximizes, and does not fire
                accel.count = 0;
                h.press(in.deco, c);
                wait(80);
                h.release(in.deco, c);
                wait(100);
                h.check(in.state->toggleMaximize == before + 1 && accel.count == 0, QStringLiteral("a click maximizes without the flyout"));
                h.leave(in.deco);
                h.destroy(in);
            }
            // inactive window: no trigger
            {
                auto st = base(scale);
                st->active = false;
                auto inactive = h.create(std::move(st));
                if (inactive.deco) {
                    accel.count = 0;
                    h.hover(inactive.deco, h.buttonCenter(inactive.deco, DecorationButtonType::Maximize));
                    wait(800);
                    h.check(accel.count == 0, QStringLiteral("inactive window: no trigger"));
                    h.destroy(inactive);
                }
            }
            // SnapLayoutsOnHover=false or the script disabled: plain maximize
            for (const auto &cfg : {std::pair<bool, bool>{false, true}, std::pair<bool, bool>{true, false}}) {
                writeConfig(QStringLiteral("RightGlyphs"), cfg.first, cfg.second);
                wait(5);
                auto off = h.create(base(scale));
                if (off.deco) {
                    const QPointF c = h.buttonCenter(off.deco, DecorationButtonType::Maximize);
                    accel.count = 0;
                    h.hover(off.deco, c);
                    h.press(off.deco, c);
                    wait(800);
                    h.release(off.deco, c);
                    wait(100);
                    h.check(accel.count == 0 && off.state->toggleMaximize == 1,
                            QStringLiteral("SnapLayoutsOnHover=%1 script=%2: hold does nothing special, release maximizes")
                                .arg(cfg.first ? QStringLiteral("true") : QStringLiteral("false"), cfg.second ? QStringLiteral("on") : QStringLiteral("off")));
                    h.destroy(off);
                }
            }
            // reconfigure switches the style live
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto live = h.create(base(scale));
            if (live.deco) {
                writeConfig(QStringLiteral("LeftCircles"), true, true);
                wait(5);
                Q_EMIT h.settings->reconfigured();
                wait(50);
                const QPointF close = h.buttonCenter(live.deco, DecorationButtonType::Close);
                h.check(close.x() < 40, QStringLiteral("reconfigure: LeftCircles moves close to the left (x %1)").arg(close.x()));
                writeConfig(QStringLiteral("RightGlyphs"), true, true);
                wait(5);
                Q_EMIT h.settings->reconfigured();
                wait(50);
                h.check(h.buttonCenter(live.deco, DecorationButtonType::Close).x() > live.deco->size().width() - 40,
                        QStringLiteral("reconfigure: back to RightGlyphs"));
                h.destroy(live);
            }
        }
    }

    out() << (h.failures == 0 ? "ALL PASS" : "FAILURES: ") << (h.failures ? QString::number(h.failures) : QString()) << "\n";
    return h.failures == 0 ? 0 : 1;
}

#include "preview.moc"
