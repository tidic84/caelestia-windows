#include "backend.h"
#include "core.h"

#include <QBuffer>
#include <QCoreApplication>
#include <QImage>
#include <QImageReader>
#include <QThreadPool>
#include <QUrl>

#include <cmath>
#include <thread>
#include <windows.h>
#include <mmsystem.h>

static Backend *s_instance = nullptr;

Backend::Backend(QObject *parent) : QObject(parent)
{
    s_instance = this;
    // des commandes bloquent longtemps (recherche Wi-Fi, mail, miniatures) :
    // assez de threads pour que les autres passent
    QThreadPool::globalInstance()->setMaxThreadCount(16);
}

// detruit avant l'application : les commandes encore en cours ne doivent plus
// toucher cet objet, ni le coeur Rust lui envoyer des evenements
Backend::~Backend()
{
    s_instance = nullptr;
    QThreadPool::globalInstance()->waitForDone();
}

Backend *Backend::instance()
{
    return s_instance;
}

void Backend::onEmit(const char *name, const char *json)
{
    if (!s_instance)
        return;
    QString n = QString::fromUtf8(name);
    QString j = QString::fromUtf8(json);
    QMetaObject::invokeMethod(
        s_instance,
        [n, j] {
            if (n.startsWith(QLatin1Char('@')))
                Q_EMIT s_instance->internal(n, j);
            else
                Q_EMIT s_instance->event(n, j);
        },
        Qt::QueuedConnection);
}

static QString call(const QString &label, const QString &cmd, const QString &args)
{
    char *r = ilot_invoke(label.toUtf8().constData(), cmd.toUtf8().constData(), args.toUtf8().constData());
    QString out = QString::fromUtf8(r);
    ilot_free(r);
    return out;
}

int Backend::invoke(const QString &label, const QString &cmd, const QString &args)
{
    int id = m_next++;
    QThreadPool::globalInstance()->start([this, id, label, cmd, args] {
        QString r = call(label, cmd, args);
        QMetaObject::invokeMethod(this, [this, id, r] { Q_EMIT reply(id, r); }, Qt::QueuedConnection);
    });
    return id;
}

QString Backend::invokeSync(const QString &label, const QString &cmd, const QString &args)
{
    return call(label, cmd, args);
}

QString Backend::startupTab() const
{
    const QStringList args = QCoreApplication::arguments();
    int i = args.indexOf(QStringLiteral("--open"));
    if (i < 0)
        return {};
    return i + 1 < args.size() && !args[i + 1].startsWith(QLatin1String("--")) ? args[i + 1] : QStringLiteral("home");
}

void Backend::setIslandOpen(bool open)
{
    ilot_set_open(open);
}

void Backend::beep()
{
    // meme rythme que la version web : deux salves de trois bips
    std::thread([] {
        const int at[] = {0, 250, 500, 1100, 1350, 1600};
        int t = 0;
        for (int ms : at) {
            if (ms > t)
                Sleep(DWORD(ms - t));
            Beep(880, 180);
            t = ms + 180;
        }
    }).detach();
}

// WAV 16 bits mono : sinus de 380 a 950 Hz en 90 ms, montee en 8 ms puis
// extinction exponentielle jusqu'a 220 ms (maquette docs/design/claude-code)
static QByteArray bubbleWav()
{
    const int rate = 44100, n = rate * 24 / 100;
    QByteArray pcm(n * 2, Qt::Uninitialized);
    auto *out = reinterpret_cast<qint16 *>(pcm.data());
    double phase = 0;
    for (int i = 0; i < n; ++i) {
        const double t = double(i) / rate;
        const double f = t < 0.09 ? 380.0 * std::pow(950.0 / 380.0, t / 0.09) : 950.0;
        phase += 6.283185307179586 * f / rate;
        double g = t < 0.008 ? 0.3 * t / 0.008 : 0.3 * std::pow(0.0001 / 0.3, (t - 0.008) / 0.212);
        if (t > 0.22)
            g = 0;
        out[i] = qint16(std::sin(phase) * g * 32767);
    }
    QByteArray wav;
    auto u32 = [&](quint32 v) { wav.append(reinterpret_cast<const char *>(&v), 4); };
    auto u16 = [&](quint16 v) { wav.append(reinterpret_cast<const char *>(&v), 2); };
    wav.append("RIFF");
    u32(quint32(36 + pcm.size()));
    wav.append("WAVEfmt ");
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(rate);
    u32(rate * 2);
    u16(2);
    u16(16);
    wav.append("data");
    u32(quint32(pcm.size()));
    wav.append(pcm);
    return wav;
}

void Backend::bubble()
{
    // garde en memoire : SND_ASYNC lit le tampon pendant la lecture
    static const QByteArray wav = bubbleWav();
    PlaySoundW(reinterpret_cast<LPCWSTR>(wav.constData()), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
}

QString Backend::foreground() const
{
    return QString::number(quintptr(GetForegroundWindow()));
}

void Backend::winResize(qreal w, qreal h)
{
    Q_EMIT resizeRequested(w, h);
}

void Backend::quit()
{
    QCoreApplication::quit();
}

void Backend::restart()
{
    Q_EMIT internal(QStringLiteral("@restart"), QString());
}

QImage IlotImages::requestImage(const QString &id, QSize *size, const QSize &requested)
{
    // une seule dimension demandee (sourceSize.width seul) : traitee comme un
    // carre, le petit cote reste assez grand pour un affichage en cover
    const int rw = requested.width(), rh = requested.height();
    const int bw = rw > 0 ? rw : rh, bh = rh > 0 ? rh : rw;
    size_t len = 0;
    uint8_t *p = ilot_image(id.toUtf8().constData(), &len);
    QImage img;
    QSize full;
    if (p) {
        // taille voulue donnee au decodeur (QImageReader::setScaledSize) : il
        // reduit pendant ou juste apres le decodage, sans seconde copie
        QByteArray bytes = QByteArray::fromRawData(reinterpret_cast<const char *>(p), qsizetype(len));
        QBuffer buf(&bytes);
        buf.open(QIODevice::ReadOnly);
        QImageReader reader(&buf);
        full = reader.size();
        if (full.isValid() && bw > 0 && bw < full.width() && bh < full.height())
            reader.setScaledSize(full.scaled(bw, bh, Qt::KeepAspectRatioByExpanding));
        img = reader.read();
        ilot_free_bytes(p, len);
        if (!full.isValid())
            full = img.size();
    }
    if (size)
        *size = full;
    // format dont la taille ne se lit pas avant decodage : reduction apres coup
    if (!img.isNull() && bw > 0 && bw < img.width() && bh < img.height())
        img = img.scaled(img.size().scaled(bw, bh, Qt::KeepAspectRatioByExpanding), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    return img;
}
