#include "viz.h"

#include <QMetaObject>
#include <QRandomGenerator>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <complex>
#include <vector>

using namespace std::chrono_literals;

namespace {

constexpr int BANDS = 24;
constexpr int FFT_N = 1024;
// +3 dB par octave : sinon les graves ecrasent tout (comme cava)
constexpr float TILT_DB = 3.0f * 8.4f;
constexpr float RANGE_DB = 42.0f;

template <class T> struct Com
{
    T *p = nullptr;
    ~Com() { if (p) p->Release(); }
    T **operator&() { return &p; }
    T *operator->() const { return p; }
    explicit operator bool() const { return p; }
};

// FFT radix 2 iterative, module du spectre normalise
std::vector<float> spectrum(const std::vector<float> &x, const std::vector<float> &win)
{
    const int n = int(x.size());
    std::vector<std::complex<float>> a(n);
    for (int i = 0; i < n; ++i)
        a[i] = x[i] * win[i];
    for (int i = 1, j = 0; i < n; ++i) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1)
            j ^= bit;
        j ^= bit;
        if (i < j)
            std::swap(a[i], a[j]);
    }
    for (int len = 2; len <= n; len <<= 1) {
        float ang = -2.0f * 3.14159265f / float(len);
        std::complex<float> wl(std::cos(ang), std::sin(ang));
        for (int i = 0; i < n; i += len) {
            std::complex<float> w(1);
            for (int k = 0; k < len / 2; ++k) {
                auto u = a[i + k], v = a[i + k + len / 2] * w;
                a[i + k] = u + v;
                a[i + k + len / 2] = u - v;
                w *= wl;
            }
        }
    }
    std::vector<float> mags(n / 2);
    for (int i = 0; i < n / 2; ++i)
        mags[i] = std::abs(a[i]) / float(n);
    return mags;
}

// bornes (indices FFT) de bandes reparties logarithmiquement
std::vector<std::pair<int, int>> bandEdges(float rate)
{
    float fmin = 45.0f, fmax = std::min(15000.0f, rate / 2.0f - 1.0f);
    float bin = rate / float(FFT_N);
    std::vector<std::pair<int, int>> e;
    for (int b = 0; b < BANDS; ++b) {
        float f0 = fmin * std::pow(fmax / fmin, float(b) / BANDS);
        float f1 = fmin * std::pow(fmax / fmin, float(b + 1) / BANDS);
        int lo = std::clamp(int(f0 / bin), 1, FFT_N / 2 - 1);
        int hi = std::clamp(int(std::ceil(f1 / bin)), lo + 1, FFT_N / 2);
        e.emplace_back(lo, hi);
    }
    return e;
}

} // namespace

Viz::Viz(bool simulate, QObject *parent) : QObject(parent), m_simulate(simulate)
{
    m_bands.fill(0.0, BANDS);
}

Viz::~Viz()
{
    m_on = false;
    if (m_thread.joinable())
        m_thread.join();
}

void Viz::setActive(bool on)
{
    if (on == m_active)
        return;
    m_active = on;
    Q_EMIT activeChanged();
    if (on) {
        // l'ancien thread s'arrete de lui-meme (m_on faux) : on l'attend
        // avant de relancer
        if (m_thread.joinable())
            m_thread.join();
        m_on = true;
        m_thread = std::thread([this] { run(); });
    } else {
        m_on = false;
        setLive(false);
    }
}

void Viz::setLive(bool on)
{
    if (on != m_live) {
        m_live = on;
        Q_EMIT liveChanged();
    }
}

void Viz::publish(const QList<qreal> &b)
{
    QMetaObject::invokeMethod(this, [this, b] {
        if (!m_on)
            return;
        m_bands = b;
        setLive(true);
        Q_EMIT bandsChanged();
    }, Qt::QueuedConnection);
}

void Viz::run()
{
    if (m_simulate)
        simulate();
    else
        capture();
}

void Viz::simulate()
{
    while (m_on) {
        QList<qreal> b(BANDS);
        for (auto &v : b)
            v = QRandomGenerator::global()->bounded(1.0);
        publish(b);
        std::this_thread::sleep_for(33ms);
    }
}

void Viz::capture()
{
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    {
        Com<IMMDeviceEnumerator> en;
        Com<IMMDevice> dev;
        Com<IAudioClient> client;
        Com<IAudioCaptureClient> cap;
        WAVEFORMATEX *fmt = nullptr;
        if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&en)))
            || FAILED(en->GetDefaultAudioEndpoint(eRender, eConsole, &dev))
            || FAILED(dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(&client)))
            || FAILED(client->GetMixFormat(&fmt))) {
            CoUninitialize();
            return;
        }
        const int channels = fmt->nChannels;
        const float rate = float(fmt->nSamplesPerSec);
        bool isFloat = fmt->wBitsPerSample == 32;
        if (FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 10000000, 0, fmt, nullptr))
            || FAILED(client->GetService(IID_PPV_ARGS(&cap))) || FAILED(client->Start())) {
            CoTaskMemFree(fmt);
            CoUninitialize();
            return;
        }
        CoTaskMemFree(fmt);

        auto edges = bandEdges(rate);
        std::vector<float> window(FFT_N), ring(FFT_N, 0.0f);
        for (int i = 0; i < FFT_N; ++i)
            window[i] = 0.5f - 0.5f * std::cos(2.0f * 3.14159265f * float(i) / float(FFT_N - 1));
        std::vector<float> bands(BANDS, 0.0f);
        float top = -70.0f;
        int quiet = 0;
        while (m_on) {
            UINT32 n = 0;
            while (SUCCEEDED(cap->GetNextPacketSize(&n)) && n) {
                BYTE *data;
                UINT32 frames;
                DWORD flags;
                if (FAILED(cap->GetBuffer(&data, &frames, &flags, nullptr, nullptr)))
                    break;
                bool silent = flags & AUDCLNT_BUFFERFLAGS_SILENT;
                int take = std::min<int>(frames, FFT_N);
                std::move(ring.begin() + take, ring.end(), ring.begin());
                for (int i = 0; i < take; ++i) {
                    int fi = int(frames) - take + i;
                    float s = 0;
                    if (!silent)
                        for (int c = 0; c < channels; ++c)
                            s += isFloat ? reinterpret_cast<float *>(data)[fi * channels + c]
                                         : reinterpret_cast<int16_t *>(data)[fi * channels + c] / 32768.0f;
                    ring[FFT_N - take + i] = s / float(channels);
                }
                cap->ReleaseBuffer(frames);
            }
            auto mags = spectrum(ring, window);
            float dbs[BANDS], loudest = -200.0f;
            for (int b = 0; b < BANDS; ++b) {
                float peak = 0;
                for (int k = edges[b].first; k < std::max(edges[b].second, edges[b].first + 1); ++k)
                    peak = std::max(peak, mags[k]);
                dbs[b] = 20.0f * std::log10(peak + 1e-9f) + TILT_DB * (float(b) / BANDS - 0.35f);
                loudest = std::max(loudest, dbs[b]);
            }
            // gain automatique : monte vite, redescend lentement
            top = loudest > top ? loudest : std::max({top - 0.15f, loudest, -70.0f});
            bool isSilent = loudest < -85.0f, any = false;
            for (int b = 0; b < BANDS; ++b) {
                float t = isSilent ? 0.0f : std::clamp((dbs[b] - (top - RANGE_DB)) / RANGE_DB, 0.0f, 1.0f);
                bands[b] = t > bands[b] ? bands[b] * 0.35f + t * 0.65f : bands[b] * 0.82f + t * 0.18f;
                any |= bands[b] > 0.01f;
            }
            quiet = any ? 0 : quiet + 1;
            if (quiet < 3)
                publish(QList<qreal>(bands.begin(), bands.end()));
            else if (quiet == 3)
                QMetaObject::invokeMethod(this, [this] { setLive(false); }, Qt::QueuedConnection);
            std::this_thread::sleep_for(33ms);
        }
        client->Stop();
    }
    CoUninitialize();
}
