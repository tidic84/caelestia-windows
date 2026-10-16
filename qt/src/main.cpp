#include "backend.h"
#include "core.h"
#include "shell.h"
#include "tray.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQuickWindow>

#include <windows.h>

// ILOT_QT_LOG=<fichier> : messages Qt / QML (l'appli n'a pas de console)
static QFile *s_log = nullptr;
static void toFile(QtMsgType, const QMessageLogContext &, const QString &msg)
{
    if (!s_log)
        return;
    s_log->write((QDateTime::currentDateTime().toString("hh:mm:ss.zzz ") + msg + "\n").toUtf8());
    s_log->flush();
}

int main(int argc, char *argv[])
{
    // diagnostics en ligne de commande (`--check-all`...), sans interface
    int code = ilot_cli();
    if (code >= 0)
        return code;

    // « Recharger » : l'ancien processus doit d'abord avoir quitte
    for (int i = 1; i + 1 < argc; ++i) {
        if (!strcmp(argv[i], "--restart-of")) {
            if (HANDLE p = OpenProcess(SYNCHRONIZE, FALSE, DWORD(atoi(argv[i + 1])))) {
                WaitForSingleObject(p, 10000);
                CloseHandle(p);
            }
        }
    }
    // une seule instance : deux hooks clavier se disputeraient la touche
    // Windows (l'un verrait l'appui, l'autre le relachement)
    HANDLE single = CreateMutexW(nullptr, TRUE, L"Local\\io.github.tidic84.ilot");
    if (GetLastError() == ERROR_ALREADY_EXISTS)
        return 0;

    QString logFile = qEnvironmentVariable("ILOT_QT_LOG");
    if (!logFile.isEmpty()) {
        s_log = new QFile(logFile);
        if (s_log->open(QIODevice::WriteOnly | QIODevice::Truncate))
            qInstallMessageHandler(toFile);
    }

    QGuiApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    app.setApplicationName(QStringLiteral("Ilot"));

    // Rubik (texte) et Material Symbols Rounded (icones), comme l'interface web
    for (const QString &f : QDir(QStringLiteral(":/fonts")).entryList({QStringLiteral("*.ttf")}))
        QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/") + f);

    Backend backend;
    qmlRegisterSingletonInstance("IlotCore", 1, 0, "Backend", &backend);

    Tray tray;
    Shell shell;
    if (!shell.start())
        return 1;
    int r = app.exec();
    CloseHandle(single);
    return r;
}
