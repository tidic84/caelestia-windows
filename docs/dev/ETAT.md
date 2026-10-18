# État du projet : journal des sessions

**À lire en premier à chaque session.** Ajoute une entrée en haut à la fin de
chaque session : ce qui a été fait, ce qui a été vérifié ou non, et où
reprendre.

## Où on en est (mis à jour le 2026-10-18)

- **Version** : 0.4.11 dans `Cargo.toml` (gestionnaire des tâches retravaillé),
  installée sur le poste, publiée le 2026-10-18 par le tag `v0.4.11`. Dernière publiée :
  0.4.10, par le tag `v0.4.10` (GitHub Action
  `release.yml`). La 0.4.8 n'a jamais été publiée seule : elle est incluse
  dans la 0.4.9.
- **Installée sur le poste** : oui, dans `%LOCALAPPDATA%\Programs\Ilot`, avec
  un raccourci dans le dossier Démarrage. Elle a été construite depuis les
  sources par `install.ps1`.
- **Consigne de l'utilisateur** : ne corriger que l'essentiel, sans rien qui
  change l'usage. Le Rust se traite « selon l'usage », et les bugs au fur et à
  mesure. Ce qui reste à faire est dans `BACKLOG.md`.
- **Prochaine étape** : aucune n'est imposée. Option encore en attente de son
  accord : « Redémarrer » dans le clic droit de la ligne `explorer`.
  Ensuite, piocher dans `BACKLOG.md`.

## Journal

### 2026-10-18 : 0.4.11, processus « principal »

Retour d'usage : terminer une sous-ligne a fermé tout le programme (c'était
sans doute le processus principal, dont les autres dépendent). Une autre
sous-ligne a fait planter un seul onglet (processus de rendu, comportement
normal). Ajouts : `Proc.ppid`, `Sub.main`. Est principal une racine du
groupe qui a au moins un enfant dans ce groupe, avec un parent né avant
l'enfant (contre les PID réutilisés). Des instances indépendantes, comme
plusieurs notepad, ne sont pas marquées. Dans le QML, ça donne « PID x ·
principal », la confirmation « Tout fermer ? » et une infobulle
d'avertissement. Nouveau test avec cmd → cmd → ping. Tests 6/6, clippy
propre, relu par `relecteur` (sa remarque sur les instances indépendantes
est appliquée). Compilé et installé.

### 2026-10-18 : 0.4.11, nom de Spotify

`apps::file_description` coupe maintenant au premier `\0`. Pour Spotify
(paquet Store), `VerQueryValueW` annonce une longueur qui va plus loin que
le zéro final, d'où « Spotify\b8…FileV ». Vérifié par un test temporaire sur
le vrai `Spotify.exe`, qui renvoie « Spotify » (test retiré ensuite : il
dépend du poste). Compilé et installé.

### 2026-10-18 : 0.4.11, groupes développés dans le gestionnaire des tâches

- **Rust** (`src/tasks.rs`). `tasks_get` prend `expanded` (noms des groupes
  ouverts). Seuls ces groupes reçoivent `procs`, une liste de `Sub` : pid,
  `created` (heure de création en ms, exacte en JS), titre de la fenêtre
  (`GetWindowTextW`, sans message envoyé aux autres processus), CPU,
  mémoire, disque, GPU et connexions. `pids_with_window` renvoie maintenant
  pid → HWND. `task_kill` prend `pid` et `created` en option. Un seul
  processus est alors terminé, et seulement s'il porte toujours ce nom et
  cette heure de création (contre la réutilisation des PID).
- **`src/host.rs`** : `State::of`, réservé aux tests (`#[cfg(test)]`).
- **QML** (`TasksPage.qml`). Un clic sur un groupe de plusieurs processus
  le développe ou le replie (chevron à gauche du nom). Les sous-lignes ont
  la clé `nom/pid`, font 32 px, sont en retrait et sans icône. Chacune a sa
  fin de tâche (bouton, et « Fin du processus » au clic droit). `opened`
  garde les groupes ouverts, même quand l'onglet est fermé. `again` relance
  un rafraîchissement demandé pendant qu'un autre est en cours. Le bouton
  s'arme sur `key` au lieu de `name`, et il est désarmé quand on replie le
  groupe.
- **Vérifié.** `cargo test` : 5/5, dont un nouveau test qui lance deux
  `ping`. Il vérifie que le groupe ouvert est seul à recevoir son détail,
  qu'un PID avec un autre nom ou une autre heure de création est refusé, et
  qu'on termine un seul des deux `ping`. `cargo clippy` : aucun nouvel
  avertissement. `qt\build.cmd` et `install.ps1` OK, aucune erreur QML au
  démarrage. Mémoire privée : 227 Mo, sans changement. Relu par
  `relecteur` : deux remarques appliquées (heure de création, désarmement).
  **Pas manipulé à la main** : le clic sur un groupe, l'affichage des
  sous-lignes et la fin d'un seul processus dans l'interface restent à
  confirmer.

### 2026-10-18 : 0.4.11, gestionnaire des tâches retravaillé

Audit par deux agents `relecteur` (Rust et QML), puis réécriture de
`src/tasks.rs` et `qt/qml/TasksPage.qml`, relue par un troisième.

- **Chiffres.** `NtQuerySystemInformation(SystemProcessInformation)`, un seul
  appel par tick, remplace sysinfo pour les processus (sysinfo ne sert plus
  qu'à `Networks`). Raison : sysinfo ouvre chaque processus, et 142 sur 279
  refusaient sans admin (svchost, postgres…), d'où 0 % de CPU et une mémoire
  surévaluée. La struct `SpInfo` est maison (256 octets, vérifiés par un
  assert). Le chemin de l'exe vient de `QueryFullProcessImageNameW`, sinon de
  la classe 88 (`SystemProcessIdInformation`) + `QueryDosDeviceW`. Il est mis
  en cache par pid + heure de création.
- **Amorce.** Au premier relevé, ou après plus de 6 s sans appel, un relevé
  d'amorce est suivi d'une pause de 300 ms. Sinon, débits et CPU seraient des
  moyennes depuis le démarrage.
- **`tasks_stop`.** Nouvelle commande, appelée quand l'onglet se cache : elle
  libère PDH, `Networks`, le tampon et les caches par pid.
- **`task_kill`.** Passe par `TerminateProcess` (plus de `taskkill.exe` par
  processus) et renvoie `{killed, denied}`.
- **QML.** `ListModel` synchronisé sur place (`sync()`, clé = nom en
  minuscules), au lieu d'un tableau remplacé toutes les 2 s. Ce remplacement
  ramenait la liste en haut et recréait ~1 500 objets. Ajouts : menu clic
  droit (`CtxMenu`) avec Fin de tâche, Ouvrir l'emplacement et Rechercher en
  ligne ; tri en cliquant les en-têtes de colonnes ; virgule décimale.
- **Vérifié.** `cargo clippy` sans nouvel avertissement. `cargo test` : 4/4,
  dont un nouveau test qui relève svchost avec des valeurs non nulles et
  compare le chemin NT converti à `exe_path`. Build complet et `install.ps1`
  OK, aucune erreur QML au démarrage dans `ILOT_QT_LOG`. **L'onglet n'a pas
  été manipulé à la main par Claude** : défilement, clic droit et fin de tâche
  restent à confirmer à l'usage.

### 2026-10-18 : 0.4.10, Claude Code dans l'îlot + plantages de Tidic, publiée

**Fonctionnement.** Les hooks Claude Code (`UserPromptSubmit`, `Stop`,
`SessionEnd`, `Notification idle_prompt`) lancent `ilot.exe --claude`. Ce
processus est traité en tête de `main.cpp`, avant le mutex : il lit le JSON du
hook sur stdin et l'envoie par `WM_COPYDATA` (`'ILCC'`) à la fenêtre
`IlotTray`. `shell.cpp` le relaie en événement `claude`, qui arrive dans
`Watch.qml` (`onClaude`).

**Fichiers.**
- Nouveaux : `src/claude.rs`, `qt/qml/ClaudeMark.qml`,
  `qt/shaders/claude.frag`.
- Modifiés : `main.cpp`, `shell.cpp/.h`, `backend.cpp/.h` (`bubble`,
  `foreground`), `Watch.qml`, `Pill.qml`, `Ilot.qml`, `SettingsPage.qml`.
- `serde_json` passe en `preserve_order`.

**Vérifié.**
- Le build passe, `cargo test` aussi (2 tests).
- Le passage par stdin fonctionne : animation et minuteur affichés puis
  effacés, vus sur des captures d'écran.
- Une seule instance tourne, et `--claude` met environ 80 ms.
- Relecture par l'agent `relecteur`. Ses points ont été corrigés : hook
  `idle_prompt`, ordre des clés gardé, filtre de messages retiré, id de
  session validé, largeur pendant le fondu, BOM, sauvegarde unique.

**Ensuite, avec l'utilisateur.**
- Le son jouait trop rarement : la condition « terminal plus au premier
  plan » est retirée. Ajout d'un bouton « Tester ».
- L'animation a été atténuée (halos × 0,4, couleurs plus sourdes).
- Ajout d'un journal des hooks dans `%TEMP%\ilot-claude.log`.
- Vérifié avec `claude -p` : UserPromptSubmit, puis Stop, puis SessionEnd
  arrivent ; l'animation s'affiche puis s'efface. Hooks installés par le
  bouton : les clés de `settings.json` sont intactes. L'utilisateur a validé.

**Fusionné** : le commit fdf06a6 de Tidic (plantages, voir l'entrée plus
bas), mis avant le nôtre. Release `v0.4.10`.

**Non vérifié** : la consommation au repos sans session (la mesure stricte
reste à faire).

### 2026-10-18 : maquette de l'animation Claude Code

- Tâche de Tyz dans le tableau de suivi de l'équipe (Google Sheets).
- Plusieurs variantes essayées en maquette web. Retenu : **L4**. Ce sont
  4 nœuds orange en orbite qui fusionnent en étoile Claude, en boucle de 5 s.
  À la fin, un son court, puis l'animation et le minuteur s'effacent.
- Ajouté : `docs/design/claude-code/README.md` (spécification, minutage,
  couleurs, pistes de portage QML et hooks) et `maquette.html` (référence).
- Vérifié : le script de la maquette passe `node --check`. Le rendu visuel a
  été validé par l'utilisateur sur la maquette en ligne. **Rien n'est codé
  dans l'appli.**
- Prochaine étape : planifier l'implémentation (hooks, tube nommé dans
  `main.cpp`, `ShaderEffect` dans la pilule) et choisir le son.

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
