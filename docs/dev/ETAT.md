# État du projet : journal des sessions

**À lire en premier à chaque session.** Ajoute une entrée en haut à la fin de
chaque session : ce qui a été fait, ce qui a été vérifié ou non, et où
reprendre.

## Où on en est (mis à jour le 2026-10-17)

- **Version** : 0.4.9, publiée par le tag `v0.4.9` (GitHub Action
  `release.yml`). La 0.4.8 n'a jamais été publiée seule : elle est incluse
  dans la 0.4.9.
- **Installée sur le poste** : oui, dans `%LOCALAPPDATA%\Programs\Ilot`, avec
  un raccourci dans le dossier Démarrage. Elle a été construite depuis les
  sources par `install.ps1`.
- **Consigne de l'utilisateur** : ne corriger que l'essentiel, sans rien qui
  change l'usage. Le Rust se traite « selon l'usage », et les bugs au fur et à
  mesure. Ce qui reste à faire est dans `BACKLOG.md`.
- **Prochaine étape** : aucune n'est imposée. Attendre les retours d'usage,
  puis piocher dans `BACKLOG.md` (les 🔴 Qt d'abord).

## Journal

### 2026-10-18 : plantages de l'îlot (dumps du 16 et du 17)

Neuf plantages en deux jours, retrouvés dans `%LOCALAPPDATA%\CrashDumps`
(`ilot.exe.<pid>.dmp`) et lus avec `cdbX64.exe` (WinDbg). Il y avait deux
causes :
- **Pointeur nul dans `Tray::setEnabled`** (6 dumps, `[rcx+0x58]`, qui
  correspond à `m_thread.joinable()`). L'appel venait de `Shell` à la
  fermeture ou au « Recharger » : un événement `settings` en attente arrivait
  pendant que les membres de `Shell` (le moteur QML) étaient détruits, alors
  que `Tray::instance()` était déjà nul. Correction : `~Shell` se désabonne
  d'abord de `Backend`, de `qGuiApp` et des écrans, et les deux appels à
  `Tray::instance()` sont protégés.
- **Bug de Qt dans `QDxgiVSyncService`** (2 dumps, thread de rendu,
  `_purecall` ou corruption du tas). Il survient quand l'écran ou le GPU
  change (veille, rebranchement). Correction : `QT_D3D_NO_VBLANK_THREAD=1`
  dans `main.cpp`, sauf si la variable est déjà définie.

Vérifié : ça compile avec `qt\build.cmd`, et l'îlot se relance.
Non vérifié : aucune fermeture, aucun « Recharger », aucune mise en veille
de l'écran n'a été testée. Pas de relecture par l'agent `relecteur`, qui
n'est pas installé sur ce poste. Pour vérifier, surveiller les nouveaux
`.dmp` dans `CrashDumps`.

### 2026-10-17 : publication de la 0.4.9

- Passage de `Cargo.toml` et `Cargo.lock` en 0.4.9, plus une section dans
  `CHANGELOG.md`.
- Tag `v0.4.9` poussé, ce qui lance la GitHub Action qui publie
  `ilot-0.4.9-win64.zip`.
- Pour publier une version : changer la version dans `Cargo.toml`, ajouter
  une section `## x.y.z — date` dans `CHANGELOG.md`, commiter, puis
  `git tag vx.y.z && git push origin main vx.y.z`.

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
