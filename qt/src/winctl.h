#pragma once

#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QStringList>
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
    // la fenetre se masque : une appli est en plein ecran sur son ecran,
    // selon fsMode
    Q_PROPERTY(bool fullscreen READ fullscreen NOTIFY fullscreenChanged)
    // une appli est en plein ecran sur l'ecran de la fenetre, quel que soit
    // fsMode (ou, en "custom", une appli choisie y est agrandie)
    Q_PROPERTY(bool covered READ covered NOTIFY coveredChanged)
    // plein ecran : "normal" (masquee), "show" (toujours affichee), "auto"
    // (masquee, revient quand la souris touche le haut de l'ecran), "custom"
    // (masquee seulement devant les applis de fsApps)
    Q_PROPERTY(QString fsMode READ fsMode WRITE setFsMode NOTIFY fsModeChanged)
    // executables (« rocketleague.exe », en minuscules) du mode "custom"
    Q_PROPERTY(QStringList fsApps READ fsApps WRITE setFsApps NOTIFY fsAppsChanged)
    // executable de la derniere appli vue en plein ecran
    Q_PROPERTY(QString fsExe READ fsExe NOTIFY fsExeChanged)

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
    bool covered() const { return m_covered; }
    QString fsMode() const { return m_fsMode; }
    void setFsMode(const QString &m);
    QStringList fsApps() const { return m_fsApps; }
    void setFsApps(const QStringList &l);
    QString fsExe() const { return m_fsExe; }

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
    void coveredChanged();
    void fsModeChanged();
    void fsAppsChanged();
    void fsExeChanged();

private:
    void checkFullscreen();
    void pollTop();
    void pollPeek();
    void setHidden(bool fs);

    QPointer<QQuickWindow> m_win;
    QString m_label;
    qreal m_topBand = 0;
    bool m_topHover = false;
    bool m_fullscreen = false;
    bool m_covered = false;
    QString m_fsMode = QStringLiteral("normal");
    QStringList m_fsApps;
    QString m_fsExe;
    // processus de la fenetre au premier plan et son executable (lu une fois
    // par processus)
    unsigned long m_fgPid = 0;
    QString m_fgExe;
    // mode "auto" : la fenetre serait masquee, mais la souris l'a rappelee
    bool m_hideWanted = false;
    bool m_peek = false;
    int m_peekOut = 0;
    QRegion m_mask;
    std::unique_ptr<Backdrop> m_backdrop;
    QVariantList m_shapes;
    QTimer m_fsTimer;
    QTimer m_topTimer;
    QTimer m_hideTimer;
    QTimer m_peekTimer;
};
