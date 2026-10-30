#include "backend.h"
#include "core.h"
#include "shell.h"
#include "tray.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
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

// `ilot.exe --claude` : lance par les hooks Claude Code (src/claude.rs), avec
// le JSON du hook sur stdin. Transmet l'evenement a l'ilot deja lance, puis
// quitte sans rien ecrire (la sortie d'UserPromptSubmit irait a Claude).
// Ne lance jamais l'ilot.
static int claudeHook()
{
    QByteArray in;
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    if (h && h != INVALID_HANDLE_VALUE) {
        // pas de console : la lecture attendrait une saisie
        DWORD type = GetFileType(h);
        if (type == FILE_TYPE_PIPE || type == FILE_TYPE_DISK) {
            char buf[8192];
            DWORD n = 0;
            while (in.size() < (1 << 20) && ReadFile(h, buf, sizeof buf, &n, nullptr) && n > 0)
                in.append(buf, int(n));
        }
    }
    const QJsonObject hook = QJsonDocument::fromJson(in).object();
    const QString event = hook.value(QStringLiteral("hook_event_name")).toString();
    HWND ilot = FindWindowW(L"IlotTray", L"Ilot");
    // journal des derniers hooks recus (diagnostic) : %TEMP%\ilot-claude.log, 64 Ko au plus
    {
        QFile log(QDir::tempPath() + QStringLiteral("/ilot-claude.log"));
        if (log.size() > 65536)
            log.remove();
        if (log.open(QIODevice::Append | QIODevice::Text))
            log.write((QDateTime::currentDateTime().toString(QStringLiteral("hh:mm:ss ")) + (event.isEmpty() ? QStringLiteral("?") : event) + QLatin1Char(' ')
                       + hook.value(QStringLiteral("session_id")).toString().left(8) + (ilot ? QString() : QStringLiteral(" (ilot absent)")) + QLatin1Char('\n'))
                          .toUtf8());
    }
    if (event.isEmpty())
        return 0;
    if (!ilot)
        return 0;
    // fenetre au premier plan : le terminal ou l'on vient de taper le prompt
    const QJsonObject msg{
        {QStringLiteral("event"), event},
        {QStringLiteral("session"), hook.value(QStringLiteral("session_id")).toString()},
        {QStringLiteral("cwd"), hook.value(QStringLiteral("cwd")).toString()},
        {QStringLiteral("hwnd"), QString::number(quintptr(GetForegroundWindow()))},
    };
    QByteArray data = QJsonDocument(msg).toJson(QJsonDocument::Compact);
    COPYDATASTRUCT cds{kClaudeCopyData, DWORD(data.size()), data.data()};
    SendMessageTimeoutW(ilot, WM_COPYDATA, 0, LPARAM(&cds), SMTO_ABORTIFHUNG | SMTO_BLOCK, 1000, nullptr);
    return 0;
}

int main(int argc, char *argv[])
{
    for (int i = 1; i < argc; ++i)
        if (!strcmp(argv[i], "--claude"))
            return claudeHook();

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

    // `--autostart` (tache planifiee, src/settings.rs) : lancee des
    // l'ouverture de session, parfois avant la barre de l'Explorateur, que
    // la zone de notification et le masquage de la barre supposent la
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--autostart")) {
            for (int t = 0; t < 240 && !FindWindowW(L"Shell_TrayWnd", nullptr); ++t)
                Sleep(250);
            break;
        }
    }

    QString logFile = qEnvironmentVariable("ILOT_QT_LOG");
    if (!logFile.isEmpty()) {
        s_log = new QFile(logFile);
        if (s_log->open(QIODevice::WriteOnly | QIODevice::Truncate))
            qInstallMessageHandler(toFile);
    }

    // Qt plante en demontant ce thread de synchro (QDxgiVSyncService) quand
    // l'ecran ou le GPU change (veille, rebranchement) ; la synchro reste
    // assuree par la swapchain
    if (!qEnvironmentVariableIsSet("QT_D3D_NO_VBLANK_THREAD"))
        qputenv("QT_D3D_NO_VBLANK_THREAD", "1");

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
