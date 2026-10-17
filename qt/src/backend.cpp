#include "backend.h"
#include "core.h"

#include <QCoreApplication>
#include <QImage>
#include <QThreadPool>
#include <QUrl>

#include <thread>
#include <windows.h>

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

QByteArray Backend::imageBytes(const QString &url)
{
    static const QString prefix = QStringLiteral("image://ilot/");
    if (url.startsWith(prefix)) {
        size_t len = 0;
        uint8_t *p = ilot_image(url.mid(prefix.size()).toUtf8().constData(), &len);
        if (!p)
            return {};
        QByteArray b(reinterpret_cast<const char *>(p), qsizetype(len));
        ilot_free_bytes(p, len);
        return b;
    }
    return {};
}

static QImage load(const QString &url)
{
    QByteArray b = Backend::imageBytes(url);
    if (!b.isEmpty())
        return QImage::fromData(b);
    QUrl u(url);
    return QImage(u.isLocalFile() ? u.toLocalFile() : url);
}

QVariantList Backend::imagePixels(const QString &url, int maxSide) const
{
    QImage img = load(url);
    QVariantList out;
    if (img.isNull())
        return out;
    if (img.width() > maxSide || img.height() > maxSide)
        img = img.scaled(maxSide, maxSide, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    img = img.convertToFormat(QImage::Format_ARGB32);
    out.reserve(img.width() * img.height());
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            if (qAlpha(line[x]) == 255)
                out.append(double(line[x]));
        }
    }
    return out;
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

void Backend::chime()
{
    // comme le carillon de la version web (la, re, sol)
    std::thread([] {
        Beep(880, 150);
        Beep(1175, 150);
        Beep(1568, 320);
    }).detach();
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
    size_t len = 0;
    uint8_t *p = ilot_image(id.toUtf8().constData(), &len);
    QImage img;
    if (p) {
        img = QImage::fromData(QByteArrayView(p, qsizetype(len)));
        ilot_free_bytes(p, len);
    }
    if (size)
        *size = img.size();
    // une seule dimension demandee (sourceSize.width seul) : traitee comme un
    // carre, le petit cote reste assez grand pour un affichage en cover
    const int rw = requested.width(), rh = requested.height();
    const int bw = rw > 0 ? rw : rh, bh = rh > 0 ? rh : rw;
    if (!img.isNull() && bw > 0 && bw < img.width() && bh < img.height())
        img = img.scaled(img.size().scaled(bw, bh, Qt::KeepAspectRatioByExpanding), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    return img;
}
