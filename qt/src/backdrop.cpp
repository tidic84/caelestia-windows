#include "backdrop.h"

#include <windows.h>
#include <cmath>
#include <d2d1.h>
#include <dwmapi.h>
#include <DispatcherQueue.h>
#include <windows.graphics.interop.h>
#include <windows.ui.composition.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Numerics.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.UI.Composition.Desktop.h>

using namespace winrt::Windows::UI::Composition;
using winrt::com_ptr;

namespace {

enum { DWMWA_USE_HOSTBACKDROPBRUSH_ = 17, DWMWA_WINDOW_CORNER_PREFERENCE_ = 33, DWMWCP_DONOTROUND_ = 1 };

// la forme (geometrie Direct2D) donnee au moteur de composition
struct GeometrySource : winrt::implements<GeometrySource, winrt::Windows::Graphics::IGeometrySource2D,
                                          ABI::Windows::Graphics::IGeometrySource2DInterop>
{
    com_ptr<ID2D1Geometry> geo;
    explicit GeometrySource(com_ptr<ID2D1Geometry> g) : geo(std::move(g)) {}
    HRESULT __stdcall GetGeometry(ID2D1Geometry **out) override
    {
        geo.copy_to(out);
        return S_OK;
    }
    HRESULT __stdcall TryGetGeometryUsingFactory(ID2D1Factory *, ID2D1Geometry **out) override
    {
        *out = nullptr;
        return E_NOTIMPL;
    }
};

com_ptr<ID2D1Geometry> combine(ID2D1Factory *f, ID2D1Geometry *a, ID2D1Geometry *b, D2D1_COMBINE_MODE mode)
{
    com_ptr<ID2D1PathGeometry> path;
    f->CreatePathGeometry(path.put());
    com_ptr<ID2D1GeometrySink> sink;
    path->Open(sink.put());
    a->CombineWithGeometry(b, mode, nullptr, sink.get());
    sink->Close();
    return path;
}

com_ptr<ID2D1Geometry> rect(ID2D1Factory *f, float x, float y, float w, float h)
{
    com_ptr<ID2D1RectangleGeometry> g;
    f->CreateRectangleGeometry(D2D1::RectF(x, y, x + w, y + h), g.put());
    return g;
}

// une forme : "rect", "round" (coins arrondis), "island" (coins bas arrondis), "earLeft" / "earRight"
// (carre creuse d'un quart de cercle centre en bas, du cote exterieur)
com_ptr<ID2D1Geometry> shape(ID2D1Factory *f, const QVariantMap &m, float k)
{
    const QString kind = m.value("kind").toString();
    const float x = m.value("x").toFloat() * k, y = m.value("y").toFloat() * k;
    const float w = m.value("w").toFloat() * k, h = m.value("h").toFloat() * k;
    const float r = m.value("r").toFloat() * k;
    com_ptr<ID2D1Geometry> box = rect(f, x, y, w, h);
    if (kind == QLatin1String("island") && r > 0) {
        // le haut du rectangle arrondi depasse de la boite : seul le bas l'est
        com_ptr<ID2D1RoundedRectangleGeometry> rr;
        f->CreateRoundedRectangleGeometry(D2D1::RoundedRect(D2D1::RectF(x, y - r, x + w, y + h), r, r), rr.put());
        return combine(f, box.get(), rr.get(), D2D1_COMBINE_MODE_INTERSECT);
    }
    if (kind == QLatin1String("round")) {
        com_ptr<ID2D1RoundedRectangleGeometry> rr;
        f->CreateRoundedRectangleGeometry(D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), r, r), rr.put());
        return rr;
    }
    if (kind == QLatin1String("earLeft") || kind == QLatin1String("earRight")) {
        const float cx = kind == QLatin1String("earLeft") ? x : x + r;
        com_ptr<ID2D1EllipseGeometry> e;
        f->CreateEllipseGeometry(D2D1::Ellipse(D2D1::Point2F(cx, y + r), r, r), e.put());
        return combine(f, box.get(), e.get(), D2D1_COMBINE_MODE_EXCLUDE);
    }
    return box;
}

} // namespace

struct Backdrop::Impl
{
    HWND hwnd = nullptr;
    com_ptr<ID2D1Factory> d2d;
    com_ptr<ABI::Windows::System::IDispatcherQueueController> queue;
    Compositor comp{nullptr};
    Desktop::DesktopWindowTarget target{nullptr};
    SpriteVisual sprite{nullptr};
    bool shown = false;

    bool init()
    {
        if (comp)
            return true;
        // le moteur de composition veut une file de messages WinRT sur ce thread
        // (le thread de Qt, deja en STA)
        if (!winrt::Windows::System::DispatcherQueue::GetForCurrentThread()) {
            DispatcherQueueOptions o{sizeof(o), DQTYPE_THREAD_CURRENT, DQTAT_COM_NONE};
            if (FAILED(CreateDispatcherQueueController(o, queue.put())))
                return false;
        }
        if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, d2d.put())))
            return false;

        static const wchar_t *cls = L"IlotBackdrop";
        HINSTANCE inst = GetModuleHandleW(nullptr);
        WNDCLASSW wc{};
        wc.lpfnWndProc = DefWindowProcW;
        wc.hInstance = inst;
        wc.lpszClassName = cls;
        RegisterClassW(&wc);
        // sans surface propre (tout vient du moteur de composition), ni souris, ni clavier
        hwnd = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT
                                   | WS_EX_NOREDIRECTIONBITMAP,
                               cls, L"", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, inst, nullptr);
        if (!hwnd)
            return false;
        DWORD round = DWMWCP_DONOTROUND_;
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE_, &round, sizeof(round));
        BOOL host = TRUE;
        DwmSetWindowAttribute(hwnd, DWMWA_USE_HOSTBACKDROPBRUSH_, &host, sizeof(host));

        try {
            comp = Compositor();
            ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget *raw = nullptr;
            winrt::check_hresult(comp.as<ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop>()
                                     ->CreateDesktopWindowTarget(hwnd, FALSE, &raw));
            winrt::attach_abi(target, raw);
            sprite = comp.CreateSpriteVisual();
            sprite.Brush(comp.CreateHostBackdropBrush());
            target.Root(sprite);
        } catch (...) {
            comp = nullptr;
            DestroyWindow(hwnd);
            hwnd = nullptr;
            return false;
        }
        return true;
    }
};

Backdrop::Backdrop() : d(std::make_unique<Impl>()) {}

Backdrop::~Backdrop()
{
    d->sprite = nullptr;
    d->target = nullptr;
    d->comp = nullptr;
    if (d->hwnd)
        DestroyWindow(d->hwnd);
}

void Backdrop::setShapes(void *owner, const QVariantList &shapes, qreal k)
{
    if (!d->init())
        return;
    ID2D1Factory *f = d->d2d.get();
    com_ptr<ID2D1Geometry> all;
    // la fenetre prendrait les clics partout ou elle est : sa region se
    // limite aux formes (leurs boites, que l'ilot et la barre couvrent deja ;
    // la decoupe exacte et lissee vient du moteur de composition)
    HRGN hit = CreateRectRgn(0, 0, 0, 0);
    for (const QVariant &v : shapes) {
        com_ptr<ID2D1Geometry> one = shape(f, v.toMap(), float(k));
        D2D1_RECT_F b;
        if (SUCCEEDED(one->GetBounds(nullptr, &b))) {
            HRGN r = CreateRectRgn(int(std::floor(b.left)) - 1, int(std::floor(b.top)) - 1, int(std::ceil(b.right)) + 1,
                                   int(std::ceil(b.bottom)) + 1);
            CombineRgn(hit, hit, r, RGN_OR);
            DeleteObject(r);
        }
        all = all ? combine(f, all.get(), one.get(), D2D1_COMBINE_MODE_UNION) : one;
    }
    // la fenetre garde la region (et la libere)
    SetWindowRgn(d->hwnd, hit, FALSE);
    if (!all)
        return hide();
    try {
        auto src = winrt::make<GeometrySource>(all);
        auto geo = d->comp.CreatePathGeometry(CompositionPath(src));
        d->sprite.Clip(d->comp.CreateGeometricClip(geo));
    } catch (...) {
        return hide();
    }
    d->shown = true;
    place(owner, true);
}

void Backdrop::place(void *owner, bool visible)
{
    if (!d->hwnd || !d->shown)
        return;
    RECT r;
    if (!visible || !GetWindowRect(HWND(owner), &r)) {
        ShowWindow(d->hwnd, SW_HIDE);
        return;
    }
    const int w = r.right - r.left, h = r.bottom - r.top;
    d->sprite.Size({float(w), float(h)});
    SetWindowPos(d->hwnd, HWND(owner), r.left, r.top, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void Backdrop::hide()
{
    d->shown = false;
    if (d->hwnd)
        ShowWindow(d->hwnd, SW_HIDE);
}
