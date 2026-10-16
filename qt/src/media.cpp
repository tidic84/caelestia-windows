// En-tetes C++/WinRT avant ceux de Qt
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>

#include "media.h"

#include <QDateTime>
#include <QMetaObject>
#include <QRegularExpression>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <vector>

using namespace std::chrono_literals;
using namespace winrt::Windows::Media::Control;
using namespace winrt::Windows::Storage::Streams;
using Session = GlobalSystemMediaTransportControlsSession;

namespace {

struct Info
{
    bool has = false, playing = false;
    QString title, artist, album, app;
    double position = 0, duration = 0;

    // meme piece, meme etat : seule la position differe (elle avance seule)
    bool sameButPosition(const Info &o) const
    {
        return has == o.has && playing == o.playing && title == o.title && artist == o.artist
            && album == o.album && app == o.app && duration == o.duration;
    }
};

QString qs(const winrt::hstring &h)
{
    return QString::fromWCharArray(h.c_str(), int(h.size()));
}

double secs(winrt::Windows::Foundation::TimeSpan t)
{
    return std::chrono::duration<double>(t).count();
}

Info read(const Session &s)
{
    Info i;
    auto props = s.TryGetMediaPropertiesAsync().get();
    auto tl = s.GetTimelineProperties();
    i.has = true;
    i.title = qs(props.Title());
    i.artist = qs(props.Artist());
    i.album = qs(props.AlbumTitle());
    i.playing = s.GetPlaybackInfo().PlaybackStatus() == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;
    i.duration = secs(tl.EndTime() - tl.StartTime());
    i.position = secs(tl.Position());
    // la position n'est publiee que ponctuellement par l'appli : on extrapole
    if (i.playing) {
        double since = secs(winrt::clock::now() - tl.LastUpdatedTime());
        if (since > 0 && since < 3600)
            i.position += since;
    }
    if (i.duration > 0)
        i.position = std::clamp(i.position, 0.0, i.duration);
    QString app = qs(s.SourceAppUserModelId());
    app = app.section(QRegularExpression(QStringLiteral("[\\\\!]")), -1);
    if (app.endsWith(QLatin1String(".exe")))
        app.chop(4);
    i.app = app;
    return i;
}

QImage readArt(const Session &s)
{
    auto ref = s.TryGetMediaPropertiesAsync().get().Thumbnail();
    if (!ref)
        return {};
    auto stream = ref.OpenReadAsync().get();
    uint32_t size = uint32_t(stream.Size());
    DataReader reader(stream);
    reader.LoadAsync(size).get();
    std::vector<uint8_t> bytes(size);
    reader.ReadBytes(bytes);
    return QImage::fromData(bytes.data(), int(bytes.size()));
}

} // namespace

Media::Media(QObject *parent) : QObject(parent)
{
    m_thread = std::thread([this] { run(); });
}

Media::~Media()
{
    {
        std::lock_guard l(m_lock);
        m_quit = true;
    }
    m_cv.notify_all();
    m_thread.join();
}

QImage Media::art() const
{
    QMutexLocker l(&m_artLock);
    return m_art;
}

void Media::wake()
{
    {
        std::lock_guard l(m_lock);
        ++m_events;
    }
    m_cv.notify_all();
}

void Media::action(const QString &what)
{
    {
        std::lock_guard l(m_lock);
        m_pending = what;
    }
    m_cv.notify_all();
}

// Reveille par les evenements GSMTC ; un releve toutes les 1 s en lecture
// (5 s sinon) rattrape les applis qui ne les envoient pas.
void Media::run()
{
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    GlobalSystemMediaTransportControlsSessionManager mgr{nullptr};
    try {
        mgr = GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
    } catch (...) {
        return;
    }
    mgr.CurrentSessionChanged([this](auto &&, auto &&) { wake(); });

    Session sub{nullptr};
    winrt::event_token tokens[3]{};
    Info last;
    bool first = true;
    QString lastKey;
    auto lastAt = std::chrono::steady_clock::now();

    for (;;) {
        QString act;
        int seen;
        {
            std::lock_guard l(m_lock);
            if (m_quit)
                break;
            act.swap(m_pending);
            seen = m_events;
        }
        Session s{nullptr};
        try {
            s = mgr.GetCurrentSession();
        } catch (...) {
        }
        if (s != sub) {
            if (sub) {
                sub.PlaybackInfoChanged(tokens[0]);
                sub.MediaPropertiesChanged(tokens[1]);
                sub.TimelinePropertiesChanged(tokens[2]);
            }
            sub = s;
            if (sub) {
                tokens[0] = sub.PlaybackInfoChanged([this](auto &&, auto &&) { wake(); });
                tokens[1] = sub.MediaPropertiesChanged([this](auto &&, auto &&) { wake(); });
                tokens[2] = sub.TimelinePropertiesChanged([this](auto &&, auto &&) { wake(); });
            }
        }
        if (s && !act.isEmpty()) {
            try {
                if (act == QLatin1String("toggle"))
                    s.TryTogglePlayPauseAsync().get();
                else if (act == QLatin1String("next"))
                    s.TrySkipNextAsync().get();
                else if (act == QLatin1String("prev"))
                    s.TrySkipPreviousAsync().get();
            } catch (...) {
            }
        }

        Info info;
        try {
            if (s)
                info = read(s);
        } catch (...) {
            info = Info{};
        }
        QString key = info.title + QChar(1) + info.artist + QChar(1) + info.album;
        if (key != lastKey) {
            lastKey = key;
            QImage img;
            if (s) {
                // certaines applis publient la pochette avec un temps de retard
                std::this_thread::sleep_for(300ms);
                try {
                    img = readArt(s);
                } catch (...) {
                }
            }
            {
                QMutexLocker l(&m_artLock);
                m_art = img;
            }
            bool has = !img.isNull();
            QMetaObject::invokeMethod(this, [this, has] {
                m_hasArt = has;
                ++m_artSerial;
                Q_EMIT artChanged();
            }, Qt::QueuedConnection);
        }

        double expected = last.position
            + (last.playing ? std::chrono::duration<double>(std::chrono::steady_clock::now() - lastAt).count() : 0);
        if (first || !info.sameButPosition(last) || std::abs(info.position - expected) > 1.5) {
            first = false;
            last = info;
            lastAt = std::chrono::steady_clock::now();
            double stamp = double(QDateTime::currentMSecsSinceEpoch());
            QMetaObject::invokeMethod(this, [this, info, stamp] {
                m_has = info.has;
                m_playing = info.playing;
                m_title = info.title;
                m_artist = info.artist;
                m_album = info.album;
                m_app = info.app;
                m_position = info.position;
                m_duration = info.duration;
                m_stamp = stamp;
                Q_EMIT changed();
            }, Qt::QueuedConnection);
        }

        std::unique_lock l(m_lock);
        m_cv.wait_for(l, last.playing ? 1s : 5s, [&] { return m_quit || m_events != seen || !m_pending.isEmpty(); });
        l.unlock();
        // plusieurs evenements arrivent souvent ensemble
        std::this_thread::sleep_for(50ms);
    }
    if (sub) {
        sub.PlaybackInfoChanged(tokens[0]);
        sub.MediaPropertiesChanged(tokens[1]);
        sub.TimelinePropertiesChanged(tokens[2]);
    }
}
