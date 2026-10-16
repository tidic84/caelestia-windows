#pragma once

#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

#include <memory>

class Backdrop;

// Ce que la fenetre transparente de l'ilot (ou d'une barre) demande a
// Windows : zones qui recoivent la souris (le reste laisse passer les clics),
// bande du haut de l'ecran (barre masquee automatiquement), plein ecran,
// clavier. Declare aussi la fenetre au coeur Rust sous son label.
class WinCtl : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickWindow *window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(QString label READ label WRITE setLabel NOTIFY labelChanged)
    // hauteur (pixels logiques) de la bande du haut de l'ecran suivie ; 0 : aucune
    Q_PROPERTY(qreal topBand READ topBand WRITE setTopBand NOTIFY topBandChanged)
    Q_PROPERTY(bool topHover READ topHover NOTIFY topHoverChanged)
    // une appli est en plein ecran sur l'ecran de la fenetre
    Q_PROPERTY(bool fullscreen READ fullscreen NOTIFY fullscreenChanged)

public:
    explicit WinCtl(QObject *parent = nullptr);
    ~WinCtl() override;

    QQuickWindow *window() const { return m_win; }
    void setWindow(QQuickWindow *w);
    QString label() const { return m_label; }
    void setLabel(const QString &l);
    qreal topBand() const { return m_topBand; }
    void setTopBand(qreal h);
    bool topHover() const { return m_topHover; }
    bool fullscreen() const { return m_fullscreen; }

    // zones {x, y, w, h} en pixels logiques de la fenetre
    Q_INVOKABLE void setHit(const QVariantList &rects);
    // flou de ce qu'il y a derriere la fenetre, dans la forme donnee :
    // {kind, x, y, w, h, r} en pixels logiques de la fenetre, kind valant
    // "rect", "round" (coins arrondis de rayon r), "island" (coins bas arrondis), "earLeft" / "earRight"
    // (coin concave de rayon r) ; liste vide : pas de flou
    Q_INVOKABLE void setBackdrop(const QVariantList &shapes);
    Q_INVOKABLE void grabFocus();
    Q_INVOKABLE void releaseFocus();

    static WinCtl *find(const QString &label);
    void declare();

Q_SIGNALS:
    void windowChanged();
    void labelChanged();
    void topBandChanged();
    void topHoverChanged();
    void fullscreenChanged();

private:
    void checkFullscreen();
    void pollTop();

    QPointer<QQuickWindow> m_win;
    QString m_label;
    qreal m_topBand = 0;
    bool m_topHover = false;
    bool m_fullscreen = false;
    QRegion m_mask;
    std::unique_ptr<Backdrop> m_backdrop;
    QVariantList m_shapes;
    QTimer m_fsTimer;
    QTimer m_topTimer;
    QTimer m_hideTimer;
};
