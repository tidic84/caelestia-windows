# Backlog technique

Problèmes connus **non corrigés**, relevés par la revue du 2026-10-17 (version
0.4.8). Ils ont été laissés de côté **volontairement** : l'utilisateur ne veut
que des correctifs essentiels, qui ne changent pas l'usage. On les traite au
fur et à mesure, quand l'usage les fait remonter.

Chaque correctif ajouté ici doit être compilé (`qt\build.cmd`) et relu (agent
`relecteur`) avant d'être commité. Quand une entrée est traitée, déplace-la
dans « Fait », avec la version.

Légende : 🔴 bug réel · 🟠 risque ou perte de performance · 🟢 propreté

## Qt / QML (`qt/`)

- 🔴 **Réglages qui reviennent en arrière** : `qt/qml/Ilot.qml:30` (`setCfg`).
  Les réponses `settings_set` passent par le pool de threads, donc elles
  peuvent arriver dans le désordre. Chacune contient la configuration complète
  et écrase `cfg`. Correction possible : un numéro de séquence, ou fusionner
  seulement les clés du `patch`.
- 🔴 **Écouteurs `Api.listen` jamais retirés** : `SoundsPage.qml:88`,
  `SettingsPage.qml:46`. Si on désactive puis réactive un module, les erreurs
  TypeError s'accumulent. Correction : `Api.unlisten` dans
  `Component.onDestruction`.
- 🟠 **Décodage synchrone sur le thread GUI** : `Ilot.qml` (`artColor()`,
  `themeFrom()`) décode la pochette ou le fond d'écran à chaque `setCfg`. Il
  faudrait décoder seulement si `color` ou `art` change, avec
  `QImageReader::setScaledSize`.
- 🟠 **Animations d'ouverture** : `Main.qml:101-106,137`. `setHit` et
  `setBackdrop` sont appelés à chaque image, ce qui recrée D2D,
  `SetWindowRgn` et `SetWindowPos`. Il faudrait les limiter.
- 🟠 **`shell.cpp:177-199`** : `place()` fait plusieurs `invokeSync("screens")`
  et est appelé deux fois quand `bar` change.
- 🟠 **`winctl.cpp:94,182`** : un timer de 500 ms qui appelle `SetWindowPos`
  même quand rien n'a bougé.
- 🟠 **`tray.cpp:95-101`** : un `join()` sur le thread GUI qui peut bloquer
  jusqu'à 3 s. Le thread n'est jamais relancé si `CreateWindowExW` échoue.
- 🟢 Fichiers géants à découper : `PetWindow.qml` (≈2400 lignes), `Pet.qml`,
  `SettingsPage.qml`, `Ilot.qml`, `Watch.qml`. Le code de `updateHit` et
  `updateBackdrop` est dupliqué entre `Main.qml` et `Bar.qml`.
- 🟢 Les 311 `property var` empêchent la compilation AOT (`qmlsc`) des
  liaisons concernées.

## Rust (`src/`), à voir selon l'usage

- 🟠 **Deux piles TLS** : `ureq` garde ses fonctions par défaut, donc rustls
  est compilé en plus de native-tls. `system.rs` (`http_get`) et
  `google.rs:135` n'utilisent pas `crate::http()`. Derrière un proxy
  d'entreprise, la météo et la connexion Google peuvent échouer.
- 🟠 **Paniques dans les rappels Win32** : `lock().unwrap()` dans
  `winkey.rs:247` et `host.rs:113`. Une panique dans une fonction
  `extern "system"` arrête tout le processus. Utiliser
  `unwrap_or_else(|e| e.into_inner())`, comme dans `apps.rs:149`.
- 🟠 **Mise à jour sans signature** : `update.rs:327`. Le SHA-256 est
  optionnel et vient de la même source que l'archive.
- 🟠 **Course dans `audio.rs` `viz_set`** : le visualiseur peut rester figé
  si on le coupe puis le rallume très vite.
- 🟢 Quick Share `safe_name` (`quickshare/mod.rs`) ne filtre pas les noms
  réservés de Windows (`CON`, `NUL`…).
- 🟢 Un seul test (`prefs::tests::combos`). Candidats faciles : `safe_name`,
  `update::newer`, le découpage des trames Quick Share.
- 🟢 Clippy : 59 avertissements, sans gravité, dont 49 se corrigent avec
  `cargo clippy --fix`. La dépendance `imap-proto 0.10.2` sera refusée par
  une future version de Rust.

## Claude Code dans l'îlot (0.4.10) : restes

- 🟢 Son définitif à choisir : seule la « bulle » est codée, dans
  `Backend::bubble`.
- 🟢 Le son joue même si on regarde encore le terminal (choix de
  l'utilisateur). `hwnd` est toujours transmis par le hook, au cas où.
- 🟢 Clic sur la pilule pour revenir au terminal : pas fait.
- 🟢 Après Échap, l'animation ne s'arrête qu'avec la notification
  `idle_prompt` (≈ 1 min). Sans elle, elle s'arrête au bout de 3 h.
- 🟢 `ilot.exe --claude` lancé à la main depuis mintty (Git Bash) attend
  stdin. Ce n'est pas un problème avec Claude Code, qui ferme stdin.

## Fait

- 0.4.10 : Claude Code dans l'îlot (hooks, animation L4, son de fin).
  Voir `docs/design/claude-code/`.
- 0.4.8 : consommation au repos (animations à 25 images/s mises en pause,
  événements Windows au lieu des sondages). Voir `docs/perf-pistes.md`.
- Session du 2026-10-17, après 0.4.8 :
  - copies privées du presse-papiers exclues de l'historique ;
  - `~Backend()` (plantage possible à la fermeture) ;
  - images réduites quand un seul côté de `sourceSize` est donné.
  Voir `ETAT.md`.
- Session du 2026-10-18 : deux plantages trouvés dans les dumps de Windows,
  le pointeur nul de `Tray` à la fermeture (`~Shell`) et le bug de Qt
  `QDxgiVSyncService`. Voir `ETAT.md`.
