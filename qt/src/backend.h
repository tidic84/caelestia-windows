#pragma once

#include <QObject>
#include <QQuickImageProvider>
#include <QVariantList>

// Pont entre l'interface QML et le coeur Rust : commandes (invoke, comme
// avec Tauri, sur un thread a part), evenements, images `image://ilot/...`.
class Backend : public QObject
{
    Q_OBJECT

public:
    explicit Backend(QObject *parent = nullptr);
    static Backend *instance();

    // Commande `cmd` (arguments en JSON) appelee pour la fenetre `label` ;
    // la reponse arrive par `reply(id, json)` : {"ok": ...} ou {"err": "..."}
    Q_INVOKABLE int invoke(const QString &label, const QString &cmd, const QString &args);
    // Meme chose sans thread (commandes instantanees, au demarrage)
    Q_INVOKABLE QString invokeSync(const QString &label, const QString &cmd, const QString &args = QStringLiteral("{}"));

    // Pixels ARGB opaques d'une image reduite a `maxSide` (couleur source du theme)
    Q_INVOKABLE QVariantList imagePixels(const QString &url, int maxSide = 128) const;
    // Taille d'origine d'une image (fond d'ecran flouté de l'ilot)
    Q_INVOKABLE QSize imageSize(const QString &url) const;

    // `--open <onglet>` : panneau ouvert au demarrage (tests, captures)
    Q_INVOKABLE QString startupTab() const;
    Q_INVOKABLE void setIslandOpen(bool open);
    // Fin du minuteur
    Q_INVOKABLE void beep();
    // Panneau agrandi : taille de la fenetre de l'ilot, en pixels logiques
    Q_INVOKABLE void winResize(qreal w, qreal h);
    Q_INVOKABLE void quit();

    // appele par le coeur Rust, depuis n'importe quel thread
    static void onEmit(const char *name, const char *json);

    static QByteArray imageBytes(const QString &url);

Q_SIGNALS:
    void reply(int id, const QString &json);
    void event(const QString &name, const QString &json);
    // evenements internes (@focus, @place, @quit) et taille demandee
    void internal(const QString &name, const QString &json);
    void resizeRequested(qreal w, qreal h);

private:
    int m_next = 1;
};

// image://ilot/<cle>.<ext> : icones, pochettes, fonds, apercus gardes par Rust
class IlotImages : public QQuickImageProvider
{
public:
    IlotImages() : QQuickImageProvider(QQuickImageProvider::Image, QQmlImageProviderBase::ForceAsynchronousImageLoading) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override;
};
