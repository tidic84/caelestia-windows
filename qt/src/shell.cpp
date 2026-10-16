#include "shell.h"
#include "backend.h"
#include "core.h"
#include "tray.h"
#include "winctl.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QQmlComponent>
#include <QScreen>
#include <QSet>
#include <QTimer>

#include <windows.h>
#include <shellapi.h>

static Shell *s_shell = nullptr;
static const UINT WM_TRAY = WM_APP + 1;
static UINT s_taskbarCreated = 0;
enum { MenuSettings = 1, MenuReload, MenuQuit };
// hauteur de la barre (pixels logiques), comme BAR_H
static const qreal BAR_H = 30;
// fenetre d'une barre : la barre et l'apercu des fenetres qui s'ouvre dessous
static const int BAR_WIN_H = 240;

static QJsonObject parse(const QString &json)
{
    return QJsonDocument::fromJson(json.toUtf8()).object();
}

static QJsonValue ok(const QString &json)
{
    return parse(json).value(QStringLiteral("ok"));
}

// `\\.\DISPLAY2` -> `bar-DISPLAY2`
static QString barLabel(const QString &name)
{
    QString s;
    for (QChar c : name)
        if (c.isLetterOrNumber() && c.unicode() < 128)
            s += c;
    return QStringLiteral("bar-") + s;
}

Shell::Shell(QObject *parent) : QObject(parent)
{
    s_shell = this;
}

Shell::~Shell()
{
    if (m_msgWnd) {
        NOTIFYICONDATAW nid{sizeof(nid)};
        nid.hWnd = HWND(m_msgWnd);
        nid.uID = 1;
        Shell_NotifyIconW(NIM_DELETE, &nid);
        UnregisterHotKey(HWND(m_msgWnd), 1);
        DestroyWindow(HWND(m_msgWnd));
    }
}

bool Shell::start()
{
    Backend *b = Backend::instance();
    m_engine.addImageProvider(QStringLiteral("ilot"), new IlotImages);
    m_engine.addImageProvider(QStringLiteral("tray"), new TrayImages);
    m_engine.loadFromModule("Ilot", "Main");
    if (m_engine.rootObjects().isEmpty())
        return false;
    m_island = qobject_cast<QQuickWindow *>(m_engine.rootObjects().first());
    if (!m_island)
        return false;
    // la fenetre native existe : le coeur peut demarrer (touche Windows,
    // barre des taches...), puis l'interface
    if (WinCtl *c = WinCtl::find(QStringLiteral("island")))
        c->declare();
    ilot_start(&Backend::onEmit);

    connect(b, &Backend::internal, this, [this](const QString &name, const QString &json) {
        if (name == QLatin1String("@focus")) {
            QString label = QJsonDocument::fromJson(json.toUtf8()).toVariant().toString();
            if (WinCtl *c = WinCtl::find(label.isEmpty() ? QStringLiteral("island") : label))
                c->grabFocus();
        } else if (name == QLatin1String("@place")) {
            place();
        } else if (name == QLatin1String("@quit")) {
            QCoreApplication::quit();
        }
    });
    connect(b, &Backend::event, this, [this](const QString &name, const QString &json) {
        if (name != QLatin1String("settings"))
            return;
        QJsonObject c = parse(json);
        bool barChanged = c.value("bar") != m_cfg.value("bar") || c.value("bar_autohide") != m_cfg.value("bar_autohide");
        m_cfg = c;
        Tray::instance()->setEnabled(c.value("bar").toBool());
        if (barChanged)
            place();
    });
    connect(b, &Backend::resizeRequested, this, [this](qreal w, qreal h) {
        m_winW = w;
        m_winH = h;
        place();
    });
    auto watchScreen = [this](QScreen *s) {
        connect(s, &QScreen::geometryChanged, this, &Shell::place);
        connect(s, &QScreen::logicalDotsPerInchChanged, this, &Shell::place);
    };
    for (QScreen *s : QGuiApplication::screens())
        watchScreen(s);
    connect(qGuiApp, &QGuiApplication::screenAdded, this, [this, watchScreen](QScreen *s) {
        watchScreen(s);
        QTimer::singleShot(300, this, &Shell::place);
    });
    connect(qGuiApp, &QGuiApplication::screenRemoved, this, [this] { QTimer::singleShot(300, this, &Shell::place); });
    connect(qGuiApp, &QCoreApplication::aboutToQuit, this, [] { ilot_shutdown(); });

    m_cfg = ok(b->invokeSync(QStringLiteral("island"), QStringLiteral("settings_get"))).toObject();
    Tray::instance()->setEnabled(m_cfg.value("bar").toBool());
    place();
    m_island->show();
    QMetaObject::invokeMethod(m_island, "start");
    createTray();
    shot();
    return true;
}

QScreen *Shell::screenNamed(const QString &name) const
{
    for (QScreen *s : QGuiApplication::screens())
        if (s->name() == name)
            return s;
    // le nom de QScreen peut differer : on compare la position (Qt garde
    // l'origine de chaque ecran en pixels physiques)
    QJsonObject n = nativeScreen(name);
    for (QScreen *s : QGuiApplication::screens())
        if (s->geometry().topLeft() == QPoint(n.value("x").toInt(), n.value("y").toInt()))
            return s;
    return nullptr;
}

// ecran tel que Windows le voit (pixels physiques), d'apres son nom
QJsonObject Shell::nativeScreen(const QString &name) const
{
    const QJsonArray list = ok(Backend::instance()->invokeSync(QStringLiteral("island"), QStringLiteral("screens"))).toArray();
    for (const QJsonValue &v : list)
        if (v.toObject().value("name").toString() == name)
            return v.toObject();
    return {};
}

// Haut de l'ecran reserve (fenetres maximisees sous la barre) ou libere
void Shell::reserve(const QString &label, QScreen *s, bool on)
{
    QJsonObject args;
    if (on && s) {
        QJsonObject n = nativeScreen(s->name());
        int x = n.contains("x") ? n.value("x").toInt() : s->geometry().x();
        int y = n.contains("y") ? n.value("y").toInt() : s->geometry().y();
        int w = n.contains("width") ? n.value("width").toInt() : qRound(s->geometry().width() * s->devicePixelRatio());
        args.insert("rect", QJsonArray{x, y, x + w, y + qRound(BAR_H * s->devicePixelRatio())});
    } else {
        args.insert("rect", QJsonValue::Null);
    }
    Backend::instance()->invokeSync(label, QStringLiteral("bar_reserve"), QString::fromUtf8(QJsonDocument(args).toJson(QJsonDocument::Compact)));
}

// En haut, au centre de l'ecran choisi (l'ecran principal par defaut, ou si
// l'ecran choisi est debranche). Avec la barre, la fenetre prend toute la
// largeur et le haut de l'ecran est reserve (sauf masquage automatique).
void Shell::place()
{
    if (!m_island || m_placing)
        return;
    m_placing = true;
    QJsonObject t = ok(Backend::instance()->invokeSync(QStringLiteral("island"), QStringLiteral("monitor_target"))).toObject();
    QScreen *s = screenNamed(t.value("name").toString());
    if (!s)
        s = QGuiApplication::primaryScreen();
    bool bar = m_cfg.value("bar").toBool();
    QRect sg = s->geometry();
    int w = bar ? sg.width() : qMin(qRound(m_winW), sg.width());
    int h = qMin(qRound(m_winH), sg.height());
    QRect g(sg.x() + (sg.width() - w) / 2, sg.y(), w, h);
    if (m_island->screen() != s)
        m_island->setScreen(s);
    if (m_island->geometry() != g)
        m_island->setGeometry(g);
    reserve(QStringLiteral("island"), s, bar && !m_cfg.value("bar_autohide").toBool());
    m_island->setProperty("screenName", s->name());
    syncBars();
    m_placing = false;
}

// Une barre sur chaque ecran qui n'a pas l'ilot (avec les memes reglages)
void Shell::syncBars()
{
    QSet<QString> wanted;
    QHash<QString, QScreen *> screenOf;
    if (m_cfg.value("bar").toBool()) {
        for (QScreen *s : QGuiApplication::screens()) {
            if (m_island && s == m_island->screen())
                continue;
            QString l = barLabel(s->name());
            wanted.insert(l);
            screenOf.insert(l, s);
        }
    }
    for (auto it = m_bars.begin(); it != m_bars.end();) {
        if (!wanted.contains(it.key()) || !it.value()) {
            reserve(it.key(), nullptr, false);
            if (it.value())
                it.value()->deleteLater();
            it = m_bars.erase(it);
        } else {
            ++it;
        }
    }
    for (const QString &l : wanted) {
        QQuickWindow *w = m_bars.value(l);
        if (!w) {
            QQmlComponent c(&m_engine);
            c.loadFromModule("Ilot", "Bar");
            QObject *o = c.createWithInitialProperties({{QStringLiteral("label"), l}});
            w = qobject_cast<QQuickWindow *>(o);
            if (!w) {
                qWarning() << c.errors();
                delete o;
                continue;
            }
            m_bars.insert(l, w);
            if (WinCtl *ctl = WinCtl::find(l))
                ctl->declare();
            placeBar(w, screenOf.value(l));
            w->show();
        } else {
            placeBar(w, screenOf.value(l));
        }
        reserve(l, screenOf.value(l), !m_cfg.value("bar_autohide").toBool());
    }
}

void Shell::placeBar(QQuickWindow *w, QScreen *s)
{
    if (!s)
        return;
    QRect sg = s->geometry();
    QRect g(sg.x(), sg.y(), sg.width(), qMin(BAR_WIN_H, sg.height()));
    if (w->screen() != s)
        w->setScreen(s);
    if (w->geometry() != g)
        w->setGeometry(g);
}

// --------------------------------------- zone de notification, raccourci

intptr_t __stdcall Shell::wndProc(void *h, unsigned msg, uintptr_t wp, intptr_t lp)
{
    HWND hwnd = HWND(h);
    if (msg == WM_TRAY) {
        UINT ev = LOWORD(lp);
        if (ev == WM_LBUTTONUP || ev == WM_RBUTTONUP || ev == WM_CONTEXTMENU)
            s_shell->trayMenu();
        return 0;
    }
    if (msg == WM_HOTKEY) {
        // Ctrl+Alt+Espace : lanceur d'applications
        Backend::instance()->invoke(QStringLiteral("island"), QStringLiteral("bar_open"), QStringLiteral("{\"tab\":\"launcher\"}"));
        return 0;
    }
    if (s_taskbarCreated && msg == s_taskbarCreated) {
        // l'Explorateur a redemarre : l'icone est a remettre
        s_shell->createTray();
        return 0;
    }
    return DefWindowProcW(hwnd, msg, WPARAM(wp), LPARAM(lp));
}

void Shell::createTray()
{
    HINSTANCE inst = GetModuleHandleW(nullptr);
    if (!m_msgWnd) {
        WNDCLASSW wc{};
        wc.lpfnWndProc = reinterpret_cast<WNDPROC>(&Shell::wndProc);
        wc.hInstance = inst;
        wc.lpszClassName = L"IlotTray";
        RegisterClassW(&wc);
        // fenetre invisible (pas HWND_MESSAGE : le menu doit pouvoir passer au premier plan)
        m_msgWnd = CreateWindowExW(WS_EX_TOOLWINDOW, L"IlotTray", L"Ilot", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, inst, nullptr);
        s_taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
        RegisterHotKey(HWND(m_msgWnd), 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_SPACE);
    }
    NOTIFYICONDATAW nid{sizeof(nid)};
    nid.hWnd = HWND(m_msgWnd);
    nid.uID = 1;
    nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    nid.uCallbackMessage = WM_TRAY;
    nid.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(1));
    wcscpy_s(nid.szTip, L"Ilot");
    Shell_NotifyIconW(NIM_ADD, &nid);
}

void Shell::trayMenu()
{
    HWND hwnd = HWND(m_msgWnd);
    HMENU m = CreatePopupMenu();
    AppendMenuW(m, MF_STRING, MenuSettings, L"Réglages");
    AppendMenuW(m, MF_STRING, MenuReload, L"Recharger");
    AppendMenuW(m, MF_STRING, MenuQuit, L"Quitter Ilot");
    POINT p;
    GetCursorPos(&p);
    SetForegroundWindow(hwnd);
    int cmd = TrackPopupMenu(m, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, p.x, p.y, 0, hwnd, nullptr);
    PostMessageW(hwnd, WM_NULL, 0, 0);
    DestroyMenu(m);
    if (cmd == MenuSettings)
        Backend::instance()->invoke(QStringLiteral("island"), QStringLiteral("bar_open"), QStringLiteral("{\"tab\":\"settings\"}"));
    else if (cmd == MenuReload)
        restart();
    else if (cmd == MenuQuit)
        QCoreApplication::quit();
}

// Recharger : un nouveau processus attend que celui-ci soit ferme
void Shell::restart()
{
    QStringList args = {QStringLiteral("--restart-of"), QString::number(GetCurrentProcessId())};
    QProcess::startDetached(QCoreApplication::applicationFilePath(), args);
    QCoreApplication::quit();
}

// ILOT_QT_SHOT=<fichier.png> : capture de la fenetre de l'ilot apres
// ILOT_QT_SHOT_DELAY ms (4000 par defaut), puis on quitte si ILOT_QT_SHOT_QUIT
void Shell::shot()
{
    QString file = qEnvironmentVariable("ILOT_QT_SHOT");
    if (file.isEmpty())
        return;
    int delay = qEnvironmentVariableIntValue("ILOT_QT_SHOT_DELAY");
    QTimer::singleShot(delay > 0 ? delay : 4000, this, [this, file] {
        if (m_island)
            m_island->grabWindow().save(file);
        if (qEnvironmentVariableIsSet("ILOT_QT_SHOT_QUIT"))
            QCoreApplication::quit();
    });
}
