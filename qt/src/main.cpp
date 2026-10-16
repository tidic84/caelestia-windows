// Prototype de l'ilot en Qt Quick / QML : meme fenetre transparente en haut
// de l'ecran, pilule, panneau (Accueil, Media), lecteur GSMTC, jauges et
// visualiseur, pour comparer la consommation avec la version Tauri.

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>

#include "island.h"
#include "media.h"
#include "sysmon.h"
#include "viz.h"

// `ILOT_QT_LOG=<fichier>` : messages Qt et QML dans un fichier (l'appli n'a
// pas de console)
static void logToFile(QtMsgType, const QMessageLogContext &, const QString &msg)
{
    static FILE *f = _wfopen(qEnvironmentVariable("ILOT_QT_LOG").toStdWString().c_str(), L"a");
    if (f && !msg.startsWith(QLatin1String("DirectWrite"))) {
        fprintf(f, "%s\n", msg.toUtf8().constData());
        fflush(f);
    }
}

int main(int argc, char *argv[])
{
    if (qEnvironmentVariableIsSet("ILOT_QT_LOG"))
        qInstallMessageHandler(logToFile);
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Ilot (Qt)"));
    // les mises en page se font en pixels logiques, comme en CSS
    QQuickWindow::setDefaultAlphaBuffer(true);

    Island island;
    Media media;
    SysMon sys;
    Viz viz(app.arguments().contains(QStringLiteral("--sim-viz")));

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("art"), new ArtProvider(&media));
    QQmlContext *ctx = engine.rootContext();
    ctx->setContextProperty(QStringLiteral("island"), &island);
    ctx->setContextProperty(QStringLiteral("media"), &media);
    ctx->setContextProperty(QStringLiteral("sys"), &sys);
    ctx->setContextProperty(QStringLiteral("viz"), &viz);
    ctx->setContextProperty(QStringLiteral("startOpen"), app.arguments().contains(QStringLiteral("--open")));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); },
                     Qt::QueuedConnection);
    engine.loadFromModule("Ilot", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    island.attach(win);
    // `ILOT_QT_SHOT=<fichier.png>` : capture de la fenetre apres 4 s (une
    // capture d'ecran GDI ne voit pas les fenetres DirectComposition a jour)
    if (qEnvironmentVariableIsSet("ILOT_QT_SHOT"))
        QTimer::singleShot(4000, win, [win] { win->grabWindow().save(qEnvironmentVariable("ILOT_QT_SHOT")); });
    return app.exec();
}
