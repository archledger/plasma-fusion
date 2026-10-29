// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include <backends/virtual/virtual_egl_backend.h>
#include <core/renderbackend.h>
#include <effect/effecthandler.h>
#include <effect/quickeffect.h>
#include <opengl/eglcontext.h>
#include <opengl/glframebuffer.h>
#include <opengl/gltexture.h>
#include <scene/item.h>
#include <scene/workspacescene.h>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QFile>
#include <QGuiApplication>
#include <QInputMethod>
#include <QInputMethodEvent>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QPointer>
#include <QQmlExtensionPlugin>
#include <QQuickItem>
#include <QQuickWindow>
#include <QThread>
#include <QTimer>
#include <atomic>
#include <qqml.h>

using namespace KWin;

class NavigationProbe : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.plasmafusion.NavigationTest")

public:
    explicit NavigationProbe(QObject *parent = nullptr)
        : QObject(parent)
        , m_output(qEnvironmentVariable("PF_NAV_PROBE_OUT"))
    {
        if (m_output.isEmpty() || !effects || !effects->scene()) {
            return;
        }
        m_registered =
            QDBusConnection::sessionBus().registerObject(QStringLiteral("/PlasmaFusionNavigationTest"), this, QDBusConnection::ExportScriptableSlots);
        connect(effects->scene(), &WorkspaceScene::frameRendered, this, &NavigationProbe::frameRendered);
    }

    ~NavigationProbe() override
    {
        if (m_registered) {
            QDBusConnection::sessionBus().unregisterObject(QStringLiteral("/PlasmaFusionNavigationTest"));
        }
    }

    Q_INVOKABLE void observe(QQuickItem *item, QObject *state, const QString &owner)
    {
        QuickSceneView *view = item ? QuickSceneView::findView(item) : nullptr;
        if (!view || !m_registered) {
            record({{QStringLiteral("event"), QStringLiteral("lookup-failed")}});
            return;
        }
        m_effect = view->effect();
        if (m_state != state) {
            if (m_state) {
                disconnect(m_state, nullptr, this, nullptr);
            }
            m_state = state;
            connect(m_state, SIGNAL(activeOutputNameChanged()), this, SLOT(ownerChanged()));
            connect(m_state, SIGNAL(gestureInProgressChanged()), this, SLOT(gestureChanged()));
        }
        const int id = ++m_nextId;
        m_entries.append({view, id, false, false, false});
        record({{QStringLiteral("event"), QStringLiteral("completed")},
                {QStringLiteral("id"), id},
                {QStringLiteral("output"), view->screen()->name()},
                {QStringLiteral("owner"), owner},
                {QStringLiteral("opacity"), view->opacity()},
                {QStringLiteral("visible"), view->isVisible()}});
        connect(
            view->window(),
            &QQuickWindow::afterRendering,
            this,
            [this, id]() {
                if (QThread::currentThread() != thread()) {
                    m_wrongThread.store(true);
                    return;
                }
                for (Entry &entry : m_entries) {
                    if (entry.id != id || entry.captured) {
                        continue;
                    }
                    if (entry.renderSeen) {
                        fail(entry, QStringLiteral("first render was not captured"));
                    } else {
                        entry.renderSeen = true;
                        entry.pending = true;
                    }
                    break;
                }
            },
            Qt::DirectConnection);
        connect(view, &QObject::destroyed, this, [this, id]() {
            m_entries.removeIf([id](const Entry &entry) {
                return entry.id == id;
            });
        });
    }

public Q_SLOTS:
    Q_SCRIPTABLE QString snapshot() const
    {
        QJsonObject result{{QStringLiteral("registered"), m_registered},
                           {QStringLiteral("ioOk"), !m_writeFailed},
                           {QStringLiteral("hasFocusObject"), QGuiApplication::focusObject() != nullptr},
                           {QStringLiteral("running"), m_effect && m_effect->isRunning()}};
        QuickSceneView *active = m_effect ? m_effect->activeView() : nullptr;
        result.insert(QStringLiteral("activeOutput"), active ? active->screen()->name() : QString());
        result.insert(QStringLiteral("focusMatches"), active && QGuiApplication::focusWindow() == active->window());
        const QVariant enabled = QInputMethod::queryFocusObject(Qt::ImEnabled, {});
        result.insert(QStringLiteral("inputMethodQueryValid"), enabled.isValid());
        result.insert(QStringLiteral("inputMethodEnabled"), enabled.toBool());
        QJsonArray views;
        for (const Entry &entry : m_entries) {
            if (entry.view) {
                views.append(QJsonObject{{QStringLiteral("id"), entry.id},
                                         {QStringLiteral("output"), entry.view->screen()->name()},
                                         {QStringLiteral("opacity"), entry.view->opacity()},
                                         {QStringLiteral("visible"), entry.view->isVisible()},
                                         {QStringLiteral("firstFrameSeen"), entry.captured}});
            }
        }
        result.insert(QStringLiteral("views"), views);
        if (m_state) {
            result.insert(QStringLiteral("ownerOutput"), m_state->property("activeOutputName").toString());
            const auto timers = m_state->findChildren<QTimer *>(QString(), Qt::FindDirectChildrenOnly);
            result.insert(QStringLiteral("closeTimerAvailable"), timers.size() == 1);
            if (timers.size() == 1) {
                result.insert(QStringLiteral("closeTimerActive"), timers.front()->isActive());
            }
        }
        return encode(result);
    }

    Q_SCRIPTABLE QString activateEditor(const QString &output)
    {
        for (const Entry &entry : m_entries) {
            if (!entry.view || entry.view->screen()->name() != output || !m_effect) {
                continue;
            }
            QPointer<QuickSceneView> view = entry.view;
            QPointer<QQuickItem> editor = view->rootItem()->findChild<QQuickItem *>(QStringLiteral("nativeProbeEditor"));
            if (!editor) {
                break;
            }
            m_effect->activateView(view);
            if (!view || !editor) {
                break;
            }
            editor->forceActiveFocus();
            return snapshot();
        }
        return encode({{QStringLiteral("error"), QStringLiteral("test editor unavailable")}});
    }

    Q_SCRIPTABLE QString exerciseInput()
    {
        QPointer<QuickSceneView> active = m_effect ? m_effect->activeView() : nullptr;
        QPointer<QObject> focus = QGuiApplication::focusObject();
        const auto focused = [&]() {
            return m_effect && active && focus && QGuiApplication::focusWindow() == active->window() && QGuiApplication::focusObject() == focus;
        };
        if (!active || QGuiApplication::focusWindow() != active->window() || !focus || focus->objectName() != QLatin1String("nativeProbeEditor")
            || !QInputMethod::queryFocusObject(Qt::ImEnabled, {}).toBool()) {
            return encode({{QStringLiteral("error"), QStringLiteral("test editor is not the focused input")}});
        }
        focus->setProperty("text", QStringLiteral("abc"));
        if (!focused()) {
            return encode({{QStringLiteral("error"), QStringLiteral("focus changed during reset")}});
        }
        focus->setProperty("cursorPosition", 3);
        if (!focused()) {
            return encode({{QStringLiteral("error"), QStringLiteral("focus changed during reset")}});
        }
        const QString before = QInputMethod::queryFocusObject(Qt::ImSurroundingText, {}).toString();
        if (!focused()) {
            return encode({{QStringLiteral("error"), QStringLiteral("focus changed during query")}});
        }
        QInputMethodEvent preedit(QStringLiteral("compose"), QList<QInputMethodEvent::Attribute>{});
        QCoreApplication::sendEvent(active->window(), &preedit);
        if (!focused()) {
            return encode({{QStringLiteral("error"), QStringLiteral("focus changed during preedit")}});
        }
        const QString composing = focus->property("preeditText").toString();
        QInputMethodEvent commit;
        commit.setCommitString(QStringLiteral("Ω"));
        QCoreApplication::sendEvent(active->window(), &commit);
        if (!focused()) {
            return encode({{QStringLiteral("error"), QStringLiteral("focus changed during commit")}});
        }
        const QString afterCommit = focus->property("preeditText").toString();
        QKeyEvent press(QEvent::KeyPress, Qt::Key_Z, Qt::NoModifier, QStringLiteral("z"));
        m_effect->grabbedKeyboardEvent(&press);
        if (!focused() || !m_effect) {
            return encode({{QStringLiteral("error"), QStringLiteral("focus changed during key press")}});
        }
        QKeyEvent release(QEvent::KeyRelease, Qt::Key_Z, Qt::NoModifier, QStringLiteral("z"));
        m_effect->grabbedKeyboardEvent(&release);
        if (!focused()) {
            return encode({{QStringLiteral("error"), QStringLiteral("focus changed during key release")}});
        }
        const QString after = QInputMethod::queryFocusObject(Qt::ImSurroundingText, {}).toString();
        const int cursor = QInputMethod::queryFocusObject(Qt::ImCursorPosition, {}).toInt();
        const int anchor = QInputMethod::queryFocusObject(Qt::ImAnchorPosition, {}).toInt();
        const bool passed = before == QLatin1String("abc") && composing == QLatin1String("compose") && afterCommit.isEmpty()
            && focus->property("preeditText").toString().isEmpty() && after == QStringLiteral("abcΩz") && cursor == 5 && anchor == 5;
        return encode({{QStringLiteral("passed"), passed},
                       {QStringLiteral("before"), before},
                       {QStringLiteral("preedit"), composing},
                       {QStringLiteral("after"), after},
                       {QStringLiteral("preeditAfterCommit"), afterCommit},
                       {QStringLiteral("cursor"), cursor},
                       {QStringLiteral("anchor"), anchor},
                       {QStringLiteral("opacity"), active->opacity()},
                       {QStringLiteral("visible"), active->isVisible()}});
    }

    Q_SCRIPTABLE QString checkGuards()
    {
        if (!m_state || !m_effect || !m_effect->activeView()) {
            return encode({{QStringLiteral("passed"), false}});
        }
        const QString before = snapshot();
        QQuickItem *nullItem = nullptr;
        QQuickWindow unrelatedWindow;
        QQuickItem unrelatedItem(unrelatedWindow.contentItem());
        QQuickItem *foreignItem = &unrelatedItem;
        const bool nullCalled = QMetaObject::invokeMethod(m_state, "updateViewOpacity", Qt::DirectConnection, Q_ARG(QQuickItem *, nullItem));
        const bool foreignCalled = QMetaObject::invokeMethod(m_state, "updateViewOpacity", Qt::DirectConnection, Q_ARG(QQuickItem *, foreignItem));
        bool otherEffectUnchanged = false;
        {
            QuickSceneEffect otherEffect;
            QuickSceneView otherView(&otherEffect, m_effect->activeView()->screen());
            otherView.setAutomaticRepaint(false);
            otherView.setRootItem(new QQuickItem());
            otherView.setOpacity(0.25);
            QQuickItem *otherRoot = otherView.rootItem();
            const bool called = QMetaObject::invokeMethod(m_state, "updateViewOpacity", Qt::DirectConnection, Q_ARG(QQuickItem *, otherRoot));
            otherEffectUnchanged = called && otherView.opacity() == 0.25;
        }
        return encode({{QStringLiteral("passed"), nullCalled && foreignCalled && otherEffectUnchanged && before == snapshot()},
                       {QStringLiteral("otherEffectUnchanged"), otherEffectUnchanged}});
    }

private Q_SLOTS:
    void gestureChanged()
    {
        if (m_state) {
            record({{QStringLiteral("event"), QStringLiteral("gesture")},
                    {QStringLiteral("owner"), m_state->property("activeOutputName").toString()},
                    {QStringLiteral("inProgress"), m_state->property("gestureInProgress").toBool()},
                    {QStringLiteral("squaredVelocity"), m_state->property("totalSquaredVelocity").toDouble()},
                    {QStringLiteral("flickThreshold"), m_state->property("flickVelocityThreshold").toDouble()}});
        }
    }

    void ownerChanged()
    {
        if (!m_state) {
            return;
        }
        const auto timers = m_state->findChildren<QTimer *>(QString(), Qt::FindDirectChildrenOnly);
        if (timers.size() != 1) {
            record({{QStringLiteral("event"), QStringLiteral("close-timer-unavailable")}});
            return;
        }
        record({{QStringLiteral("event"), QStringLiteral("owner-change")},
                {QStringLiteral("owner"), m_state->property("activeOutputName").toString()},
                {QStringLiteral("closeTimerActive"), timers.front()->isActive()},
                {QStringLiteral("remainingMs"), timers.front()->remainingTime()}});
    }

private:
    struct Entry {
        QPointer<QuickSceneView> view;
        int id;
        bool renderSeen;
        bool pending;
        bool captured;
    };

    static QString encode(const QJsonObject &value)
    {
        return QString::fromUtf8(QJsonDocument(value).toJson(QJsonDocument::Compact));
    }

    void record(const QJsonObject &value) const
    {
        if (m_output.isEmpty()) {
            return;
        }
        QFile file(m_output + QStringLiteral("/probe.jsonl"));
        const QByteArray line = QJsonDocument(value).toJson(QJsonDocument::Compact) + '\n';
        if (!file.open(QIODevice::WriteOnly | QIODevice::Append) || file.write(line) != line.size()) {
            m_writeFailed = true;
        }
    }

    void fail(Entry &entry, const QString &reason)
    {
        entry.pending = false;
        entry.captured = true;
        record({{QStringLiteral("event"), QStringLiteral("capture-failed")}, {QStringLiteral("id"), entry.id}, {QStringLiteral("reason"), reason}});
    }

    void frameRendered()
    {
        if (m_wrongThread.exchange(false)) {
            record({{QStringLiteral("event"), QStringLiteral("wrong-render-thread")}});
        }
        for (Entry &entry : m_entries) {
            if (!entry.view || !entry.pending || entry.captured) {
                continue;
            }
            QuickSceneView *rendered = entry.view;
            if (!m_effect || !m_state || !m_effect->isRunning() || !EglContext::currentContext()) {
                fail(entry, QStringLiteral("first composition context unavailable"));
                continue;
            }
            QJsonObject result{{QStringLiteral("event"), QStringLiteral("first-frame")},
                               {QStringLiteral("id"), entry.id},
                               {QStringLiteral("output"), rendered->screen()->name()},
                               {QStringLiteral("owner"), m_state->property("activeOutputName").toString()},
                               {QStringLiteral("opacity"), rendered->opacity()},
                               {QStringLiteral("width"), rendered->geometry().width()},
                               {QStringLiteral("height"), rendered->geometry().height()},
                               {QStringLiteral("visible"), rendered->isVisible()}};
            for (RenderView *candidate : effects->scene()->views()) {
                auto scene = dynamic_cast<SceneView *>(candidate);
                if (!scene || scene->logicalOutput() != rendered->screen()) {
                    continue;
                }
                auto layer = dynamic_cast<VirtualEglLayer *>(scene->layer());
                if (!layer || !layer->texture() || layer->sourceRect() != RectF(scene->deviceRect()) || layer->targetRect() != scene->deviceRect()) {
                    continue;
                }
                GLFramebuffer *framebuffer = GLFramebuffer::currentFramebuffer();
                if (!framebuffer || framebuffer->colorAttachment() != layer->texture()) {
                    continue;
                }
                const QString name = QStringLiteral("first-%1.png").arg(entry.id);
                if (layer->texture()->toImage().save(m_output + QLatin1Char('/') + name)) {
                    result.insert(QStringLiteral("image"), name);
                }
                break;
            }
            if (result.contains(QStringLiteral("image"))) {
                entry.pending = false;
                entry.captured = true;
                record(result);
            } else {
                fail(entry, QStringLiteral("first composition target or image unavailable"));
            }
        }
    }

    QString m_output;
    bool m_registered = false;
    int m_nextId = 0;
    QPointer<QuickSceneEffect> m_effect;
    QPointer<QObject> m_state;
    QList<Entry> m_entries;
    std::atomic_bool m_wrongThread = false;
    mutable bool m_writeFailed = false;
};

class NavigationProbePlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterType<NavigationProbe>(uri, 1, 0, "NavigationProbe");
    }
};

#include "probe.moc"
