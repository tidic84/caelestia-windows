#include "tray.h"

#include <QUuid>

#include <future>

#include <windows.h>
#include <shellapi.h>

static Tray *s_tray = nullptr;
static UINT s_taskbarCreated = 0;
enum { TimerTop = 1, TimerRebroadcast };

// Ce que Shell_NotifyIcon envoie a `Shell_TrayWnd` (COPYDATASTRUCT.dwData = 1) :
// NOTIFYICONDATAW en disposition 32 bits (handles sur 32 bits, quelle que
// soit l'architecture de l'appli)
struct NotifyData
{
    DWORD signature; // 0x34753423
    DWORD message; // NIM_ADD...
    DWORD cbSize;
    DWORD hWnd;
    UINT uID;
    UINT uFlags;
    UINT uCallbackMessage;
    DWORD hIcon;
    WCHAR szTip[128];
    DWORD dwState;
    DWORD dwStateMask;
    WCHAR szInfo[256];
    UINT uVersion;
    WCHAR szInfoTitle[64];
    DWORD dwInfoFlags;
    GUID guidItem;
    DWORD hBalloonIcon;
};

// Shell_NotifyIconGetRect (dwData = 3) : coin haut-gauche (message 1) ou
// bas-droit (message 2) de l'icone
struct IconIdentifier
{
    DWORD signature;
    DWORD message;
    DWORD cbSize;
    DWORD padding;
    quint64 hWnd;
    UINT uID;
    GUID guidItem;
};

// les handles 32 bits sont etendus avec leur signe
template<typename T>
static T handle32(DWORD v)
{
    return reinterpret_cast<T>(intptr_t(int32_t(v)));
}

Tray::Tray(QObject *parent) : QObject(parent)
{
    s_tray = this;
}

Tray::~Tray()
{
    stop();
    s_tray = nullptr;
}

Tray *Tray::instance()
{
    return s_tray;
}

Tray *Tray::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(s_tray, QJSEngine::CppOwnership);
    return s_tray;
}

void Tray::setEnabled(bool on)
{
    if (on == m_thread.joinable())
        return;
    if (!on) {
        stop();
        return;
    }
    std::promise<void> ready;
    std::future<void> created = ready.get_future();
    m_thread = std::thread([this, &ready] {
        run();
        const bool ok = m_wnd;
        ready.set_value();
        if (!ok)
            return;
        MSG msg;
        while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    });
    created.wait();
}

void Tray::stop()
{
    if (!m_thread.joinable())
        return;
    if (m_wnd)
        PostMessageW(HWND(m_wnd), WM_CLOSE, 0, 0);
    m_thread.join();
    m_wnd = nullptr;
    QMutexLocker lock(&m_mutex);
    m_icons.clear();
    lock.unlock();
    changed();
}

// --------------------------------------------------- thread de la fenetre

void Tray::run()
{
    HINSTANCE inst = GetModuleHandleW(nullptr);
    s_taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
    WNDCLASSW wc{};
    wc.lpfnWndProc = reinterpret_cast<WNDPROC>(&Tray::wndProc);
    wc.hInstance = inst;
    wc.lpszClassName = L"Shell_TrayWnd";
    RegisterClassW(&wc);
    HWND w = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE, L"Shell_TrayWnd", L"", WS_POPUP,
                             0, 0, 0, 0, nullptr, nullptr, inst, nullptr);
    m_wnd = w;
    if (!w)
        return;
    // FindWindow(L"Shell_TrayWnd") doit nous trouver avant l'Explorateur
    SetWindowPos(w, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    SetTimer(w, TimerTop, 1000, nullptr);
    // les applis deja lancees remettent leurs icones (chez nous, puis
    // transmises a l'Explorateur qui les a deja)
    broadcast();
}

void Tray::broadcast()
{
    m_broadcastAt = GetTickCount64();
    SendNotifyMessageW(HWND_BROADCAST, s_taskbarCreated, 0, 0);
}

// Barre des taches de l'Explorateur (pas la notre)
void *Tray::explorerTray() const
{
    HWND h = nullptr;
    while ((h = FindWindowExW(nullptr, h, L"Shell_TrayWnd", nullptr))) {
        DWORD pid = 0;
        GetWindowThreadProcessId(h, &pid);
        if (h != HWND(m_wnd) && pid != GetCurrentProcessId())
            return h;
    }
    return nullptr;
}

intptr_t __stdcall Tray::wndProc(void *h, unsigned msg, uintptr_t wp, intptr_t lp)
{
    HWND hwnd = HWND(h);
    Tray *t = s_tray;
    auto forward = [&]() -> intptr_t {
        HWND ex = t ? HWND(t->explorerTray()) : nullptr;
        DWORD_PTR r = 0;
        if (ex && SendMessageTimeoutW(ex, msg, WPARAM(wp), LPARAM(lp), SMTO_ABORTIFHUNG, 3000, &r))
            return intptr_t(r);
        return 0;
    };
    if (msg == WM_COPYDATA && t) {
        auto *cds = reinterpret_cast<COPYDATASTRUCT *>(lp);
        if (cds->dwData == 1) {
            intptr_t r = t->notify(cds->lpData, cds->cbData);
            forward();
            return r;
        }
        if (cds->dwData == 3) {
            intptr_t r = t->iconRect(cds->lpData, cds->cbData);
            return r ? r : forward();
        }
        // AppBar (dwData = 0) et le reste : l'Explorateur repond
        return forward();
    }
    if (msg == WM_TIMER && t) {
        if (wp == TimerRebroadcast) {
            KillTimer(hwnd, TimerRebroadcast);
            SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            t->broadcast();
            return 0;
        }
        // l'Explorateur repasse parfois devant ; meme rectangle que sa barre,
        // pour les applis qui la cherchent avec GetWindowRect
        if (FindWindowW(L"Shell_TrayWnd", nullptr) != hwnd)
            SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        RECT er, r;
        if (HWND ex = HWND(t->explorerTray()); ex && GetWindowRect(ex, &er) && GetWindowRect(hwnd, &r) && !EqualRect(&er, &r))
            SetWindowPos(hwnd, nullptr, er.left, er.top, er.right - er.left, er.bottom - er.top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
        t->prune();
        return 0;
    }
    if (s_taskbarCreated && msg == s_taskbarCreated) {
        // l'Explorateur a redemarre : les applis ont pu remettre leurs icones
        // chez lui seulement, on leur redemande une fois devant
        if (t && GetTickCount64() - t->m_broadcastAt > 3000)
            SetTimer(hwnd, TimerRebroadcast, 1500, nullptr);
        return 0;
    }
    if (msg == WM_CLOSE) {
        DestroyWindow(hwnd);
        return 0;
    }
    if (msg == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, WPARAM(wp), LPARAM(lp));
}

qintptr Tray::notify(const void *data, quint32 size)
{
    NotifyData d{};
    if (size < offsetof(NotifyData, szTip))
        return FALSE;
    memcpy(&d, data, qMin<size_t>(size, sizeof(d)));
    if (d.signature != 0x34753423)
        return FALSE;
    const bool byGuid = d.uFlags & NIF_GUID;
    const QString key = byGuid ? QUuid(d.guidItem).toString() : QStringLiteral("%1:%2").arg(d.hWnd).arg(d.uID);

    QMutexLocker lock(&m_mutex);
    int i = 0;
    while (i < m_icons.size() && m_icons[i].key != key)
        ++i;
    const bool found = i < m_icons.size();
    switch (d.message) {
    case NIM_ADD:
    case NIM_MODIFY: {
        if (!found) {
            if (d.message == NIM_MODIFY)
                return FALSE;
            Icon n;
            n.id = m_nextId++;
            n.key = key;
            m_icons.append(n);
        }
        Icon &ic = m_icons[i];
        ic.hwnd = quintptr(handle32<HWND>(d.hWnd));
        ic.uid = d.uID;
        ic.flags = d.uFlags;
        if (d.uFlags & NIF_MESSAGE)
            ic.msg = d.uCallbackMessage;
        if ((d.uFlags & NIF_ICON) && d.hIcon) {
            ic.img = QImage::fromHICON(handle32<HICON>(d.hIcon));
            ic.rev++;
        }
        if (d.uFlags & NIF_TIP) {
            // NOTIFYICONDATA de la premiere version : 64 caracteres
            int max = d.cbSize && d.cbSize <= 152 ? 64 : 128;
            ic.tip = QString::fromWCharArray(d.szTip, int(wcsnlen(d.szTip, max)));
        }
        if ((d.uFlags & NIF_STATE) && (d.dwStateMask & NIS_HIDDEN))
            ic.hidden = d.dwState & NIS_HIDDEN;
        break;
    }
    case NIM_DELETE:
        if (!found)
            return FALSE;
        m_icons.removeAt(i);
        break;
    case NIM_SETVERSION:
        if (found)
            m_icons[i].version = d.uVersion;
        return d.uVersion <= NOTIFYICON_VERSION_4;
    case NIM_SETFOCUS:
        return TRUE;
    default:
        return FALSE;
    }
    lock.unlock();
    changed();
    return TRUE;
}

qintptr Tray::iconRect(const void *data, quint32 size)
{
    IconIdentifier d{};
    memcpy(&d, data, qMin<size_t>(size, sizeof(d)));
    if (d.signature != 0x34753423)
        return 0;
    const QString guid = QUuid(d.guidItem).isNull() ? QString() : QUuid(d.guidItem).toString();
    QMutexLocker lock(&m_mutex);
    for (const Icon &ic : std::as_const(m_icons)) {
        bool match = !guid.isEmpty() ? ic.key == guid : (quint32(ic.hwnd) == quint32(d.hWnd) && ic.uid == d.uID);
        if (!match || ic.rect[2] <= ic.rect[0])
            continue;
        if (d.message == 1)
            return MAKELONG(ic.rect[0], ic.rect[1]);
        if (d.message == 2)
            return MAKELONG(ic.rect[2], ic.rect[3]);
    }
    return 0;
}

// Icones des applis fermees sans NIM_DELETE (plantage...)
void Tray::prune()
{
    QMutexLocker lock(&m_mutex);
    qsizetype n = m_icons.removeIf([](const Icon &ic) { return !IsWindow(HWND(ic.hwnd)); });
    lock.unlock();
    if (n)
        changed();
}

// ------------------------------------------------------ cote interface

void Tray::changed()
{
    QMutexLocker lock(&m_mutex);
    if (m_pending)
        return;
    m_pending = true;
    QMetaObject::invokeMethod(this, &Tray::refresh, Qt::QueuedConnection);
}

void Tray::refresh()
{
    QVariantList list;
    {
        QMutexLocker lock(&m_mutex);
        m_pending = false;
        for (const Icon &ic : std::as_const(m_icons)) {
            if (ic.hidden || ic.img.isNull())
                continue;
            list.append(QVariantMap{{"id", ic.id}, {"tip", ic.tip}, {"rev", ic.rev}});
        }
    }
    if (list == m_list)
        return;
    m_list = list;
    Q_EMIT iconsChanged();
}

QImage Tray::image(int id) const
{
    QMutexLocker lock(&m_mutex);
    for (const Icon &ic : m_icons)
        if (ic.id == id)
            return ic.img;
    return {};
}

void Tray::click(int id, const QString &button)
{
    HWND hwnd = nullptr;
    UINT uid = 0, cb = 0, version = 0;
    POINT p;
    GetCursorPos(&p);
    {
        QMutexLocker lock(&m_mutex);
        for (Icon &ic : m_icons) {
            if (ic.id != id)
                continue;
            hwnd = HWND(ic.hwnd);
            uid = ic.uid;
            cb = ic.msg;
            version = ic.version;
            // rectangle de l'icone pour Shell_NotifyIconGetRect : autour de la souris
            const int r = GetSystemMetrics(SM_CXSMICON) / 2 + 4;
            ic.rect[0] = p.x - r;
            ic.rect[1] = p.y - r;
            ic.rect[2] = p.x + r;
            ic.rect[3] = p.y + r;
        }
    }
    if (!hwnd || !cb || !IsWindow(hwnd))
        return;
    auto send = [&](UINT m) {
        if (version >= NOTIFYICON_VERSION_4)
            PostMessageW(hwnd, cb, MAKEWPARAM(p.x, p.y), MAKELPARAM(m, uid));
        else
            PostMessageW(hwnd, cb, uid, m);
    };
    if (button == QLatin1String("hover")) {
        send(WM_MOUSEMOVE);
        return;
    }
    // l'appli peut passer au premier plan (son menu, sa fenetre)
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    AllowSetForegroundWindow(pid);
    if (button == QLatin1String("right")) {
        send(WM_RBUTTONDOWN);
        send(WM_RBUTTONUP);
        if (version >= NOTIFYICON_VERSION)
            send(WM_CONTEXTMENU);
    } else if (button == QLatin1String("double")) {
        send(WM_LBUTTONDBLCLK);
        send(WM_LBUTTONUP);
    } else {
        send(WM_LBUTTONDOWN);
        send(WM_LBUTTONUP);
        if (version >= NOTIFYICON_VERSION)
            send(NIN_SELECT);
    }
}

QImage TrayImages::requestImage(const QString &id, QSize *size, const QSize &requested)
{
    QImage img = Tray::instance() ? Tray::instance()->image(id.section(u'-', 0, 0).toInt()) : QImage();
    if (!img.isNull() && requested.isValid() && requested != img.size())
        img = img.scaled(requested, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    if (size)
        *size = img.size();
    return img;
}
