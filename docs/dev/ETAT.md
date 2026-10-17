# État du projet : journal des sessions

**À lire en premier à chaque session.** Ajoute une entrée en haut à la fin de
chaque session : ce qui a été fait, ce qui a été vérifié ou non, et où
reprendre.

## Où on en est (mis à jour le 2026-10-17)

- **Version** : 0.4.8 (sur `main`, avec les optimisations de consommation au
  repos déjà fusionnées).
- **Installée sur le poste** : oui, dans `%LOCALAPPDATA%\Programs\Ilot`, avec
  un raccourci dans le dossier Démarrage. Elle a été construite depuis les
  sources par `install.ps1`.
- **Consigne de l'utilisateur** : ne corriger que l'essentiel, sans rien qui
  change l'usage. Le Rust se traite « selon l'usage », et les bugs au fur et à
  mesure. Ce qui reste à faire est dans `BACKLOG.md`.
- **Prochaine étape** : aucune n'est imposée. Attendre les retours d'usage,
  puis piocher dans `BACKLOG.md` (les 🔴 Qt d'abord).

## Journal

### 2026-10-17 : revue complète, installation, documentation

Fait :
- **Revue complète** par des agents (Rust, Qt/QML, build). Résultats dans
  `BACKLOG.md`.
- **Poste** : installation de Qt 6.9.3 msvc2022_64 (aqtinstall, `C:\Qt`), de
  Ninja et de LLVM/clangd. Voir `OUTILS.md`.
- **Plugins Claude Code** installés : `qt-development-skills` et `clangd-lsp`.
- **Correctifs essentiels** (commit « Correctifs essentiels et documentation
  de développement ») :
  1. `src/system.rs` : les copies marquées privées ne vont plus dans
     l'historique du presse-papiers. Formats concernés :
     `ExcludeClipboardContentFromMonitorProcessing`, `Clipboard Viewer Ignore`,
     et `CanIncludeInClipboardHistory` quand il vaut 0.
  2. `qt/src/backend.cpp` : `~Backend()` remet `s_instance` à nul et attend le
     pool de threads. Cela évite qu'un objet détruit soit utilisé à la
     fermeture ou au redémarrage.
  3. `qt/src/backend.cpp` `IlotImages` : quand seul `sourceSize.width` est
     donné, l'image est réduite comme pour un carré de ce côté. Avant, elle
     restait en pleine résolution. Le petit côté reste assez grand pour le
     mode cover, donc l'image n'est pas plus floue qu'avant.
  4. `qt/CMakeLists.txt` : `CMAKE_EXPORT_COMPILE_COMMANDS` est activé, pour
     clangd.

Vérifié :
- `qt\build.cmd` et `install.ps1` compilent sans erreur.
- `ilot.exe` tourne et répond.
- Au lancement : 4,7 % d'un cœur et 228 Mo (mémoire privée), mesurés sur 30 s
  pendant la première minute. Ce n'est pas une mesure de repos stricte : les
  animations ne se mettent en pause qu'après 1 min sans clavier ni souris.
- Les correctifs ont été relus par l'agent `relecteur`, et ses deux remarques
  (images en cover, valeur de `CanIncludeInClipboardHistory`) ont été
  appliquées.

Non vérifié :
- L'exclusion des mots de passe, à tester en copiant depuis KeePass ou
  Bitwarden.
- La netteté des pochettes 16:9 à l'écran.
- La consommation au repos réel. Pour la mesurer, utiliser la méthode de
  `docs/perf-ilot.md`.
