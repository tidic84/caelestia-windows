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

- 🟢 **Puce Jeux (2026-10-27)** : une appli de `folders.games` qui est aussi
  détectée (Steam…) apparaît deux fois. CurseForge et Overwolf sont rangés
  dans « Launcher ». Les jeux ajoutés à la main ne déclenchent pas le mode
  jeu (détection Rust seule).

- 🟢 **Sélecteur Bluetooth (2026-10-26), limites connues** :
  - Seuls les casques et enceintes (classe audio) se connectent depuis
    l'îlot. Souris, claviers, manettes se connectent d'eux-mêmes ; la ligne
    n'a pas d'action.
  - Les pilotes audio d'un appareil sont retrouvés par l'adresse (A2DP) ou
    par « (Nom » dans le nom de la sortie (mains libres) : un appareil
    nommé « Nom 2 » serait visé aussi.
  - Pour un code affiché (DisplayPin), pas de bouton Annuler : l'attente va
    jusqu'à 90 s.
  - Un appareil classique + BLE de même nom n'apparaît qu'une fois.

- 🟢 **Mélangeur, appli en pause** : après un changement de sortie, une appli
  qui ne joue pas peut rester listée sous l'ancienne et la nouvelle sortie
  (`hide_stale` ne masque que si une session est active ailleurs).
- 🟢 **Code mort des profils de volume** : `Watch.qml` (`mixProfiles`,
  `saveProfile`, `applyProfile`, `gameMix`) et `cfg.mix_auto` ne servent
  plus depuis la 0.4.19.
- 🟠 **Échap ne marche plus après avoir changé d'onglet** (déjà avant la
  0.4.20). Un champ a pris le focus (recherche du lanceur, ville, raccourci,
  renommage d'une sortie), puis on change d'onglet. Le Loader de la page est
  désactivé (`enabled: shown`, `Panel.qml`), le focus tombe sur l'item racine
  de la fenêtre, et `Keys.onPressed` de `Main.qml` ne reçoit plus Échap.
  Correctif proposé : dans `Main.qml`, si `activeFocusItem === contentItem`,
  rendre le focus à `root`. Relevé par un relecteur, confirmé par un test
  `qmltestrunner`.
- 🟢 **Sorties affichées (0.4.20), restes connus** :
  - Le nom choisi d'une sortie débranchée, mais pas masquée, reste dans
    `audio_alias` sans moyen de l'oublier. « Tout afficher » oublie aussi les
    sorties « Absente ».
  - La détection des virtuelles se fait par le nom : « Speakers (Virtual
    Surround) » de Realtek ou Nahimic est rangée dans « Virtuelles ».
  - La soundboard garde les noms Windows.
  - Si la page faisait moins d'environ 470 px de large (aujourd'hui au moins
    708), le titre « Sorties affichées · N sur M » passerait sur deux lignes
    au premier choix, et les lignes descendraient de 17 px. Correctif :
    `elide` sur ce titre, ou le compteur ailleurs.
  - Le point de « +N » s'allume aussi pour une appli en pause : `mixer_all`
    ne dit pas si une session est active. Il faudrait renvoyer un champ
    `active`, côté Rust.
  - À la fermeture, l'envoi synchrone peut passer avant un envoi asynchrone
    parti juste avant (fenêtre de quelques ms). L'avant-dernier choix
    l'emporterait alors.
  - Doublons : la numérotation se fait sur le nom court et s'ajoute au
    libellé (« LG (HDMI) » et « Samsung (HDMI) » donnent « LG » et
    « Samsung 2 »). Cette règle existait déjà dans le mélangeur.
- 🟢 **Mélangeur, `Ilot.later`** : les rafraîchissements différés après un
  changement de sortie peuvent arriver après le déchargement de la page
  (TypeError dans le journal, sans effet).

- 🟢 **Lecteur, une seule session** : seule `GetCurrentSession()` est suivie,
  donc on ne choisit pas entre deux applis qui jouent. Il n'y a pas non plus
  d'aléatoire ni de répétition, qui demanderaient du Rust en plus. Voir
  `PLAN-MEDIA.md`, « Hors plan ».
- 🟢 **Fond « art » de l'onglet Média** : le masque des coins (layer +
  MultiEffect sur `bgClip`, `MediaPage.qml`) refait 2 passes GPU par image
  pendant la dérive. À mesurer (`docs/perf-*.md`). Option : couper la dérive.
- 🟢 **Réglage spectre** : une fois touché, `player_spectrum` devient un
  booléen et ne suit plus la forme de la pochette (pas de retour à « auto »
  dans l'UI).

- 🟢 **Infobulle au-dessus d'un menu natif** : `Btn.qml`. Après un clic sur
  une icône de la zone de notification, le menu de l'appli capture la souris.
  Notre infobulle peut rester affichée jusqu'au prochain mouvement sur la
  barre. Correction possible : masquer le `Tip` à l'appui.

- 🔴 **Réglages qui reviennent en arrière** : `qt/qml/Ilot.qml:30` (`setCfg`).
  Les réponses `settings_set` passent par le pool de threads, donc elles
  peuvent arriver dans le désordre. Chacune contient la configuration complète
  et écrase `cfg`. Correction possible : un numéro de séquence, ou fusionner
  seulement les clés du `patch`.
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

- 🟢 **Propriétés QML typées sans effet tant que `Ilot` n'est pas résolu** :
  le singleton `Ilot` porte le nom du module QML (`URI Ilot`). qmllint ne
  trouve donc aucun de ses membres (182 avertissements dans `Pill.qml`), et
  qmlcachegen ne compile pas les liaisons qui le lisent. Typer `shown`, `cfg`
  ou `media` ne servira qu'après avoir levé ce conflit, en renommant le
  module ou le singleton (touche presque tous les fichiers QML).
- 🟢 **Visualiseur replié en 3 bandes** : non fait. `Aurora` (graves 0-3,
  médiums 3-12, aigus 12-24) et `Pet` lisent les 24 bandes quand l'îlot est
  replié. Le gain (21 octets de JSON par trame, à 15 trames/s) ne vaut pas
  de changer leur rendu.

## Rust (`src/`), à voir selon l'usage

- 🟢 **Lot suivant du lecteur** (touche `src/media.rs`) : clic sur la pochette
  pour ramener l'appli au premier plan. Aléatoire, répétition et choix de
  l'appli suivie sont déjà notés plus haut (« Lecteur, une seule session »).
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

## Alerte « partie trouvée » (hors Valorant)

- 🟢 Seul signal : le clignotement de la fenêtre du jeu. À confirmer pour
  Apex (s'il ne clignote pas, pas d'alerte). Pas de minuteur de file, faute
  de savoir si une recherche est lancée.

## Relevés encore sondés

- 🟠 **Tube Discord en vocal** : `discord.rs:395`, lu toutes les 60 ms. Une
  lecture bloquante dans un autre thread bloquerait les écritures sur le même
  handle synchrone. Il faudrait passer le tube en E/S asynchrones
  (`FILE_FLAG_OVERLAPPED` + événement), à tester en vocal.
- 🟢 **Verr. Maj sans crochet clavier** : quand ni l'îlot sur la touche
  Windows, ni ses raccourcis, ni le remappage ne sont actifs, le crochet
  n'est pas installé. Verr. Maj est alors encore sondée toutes les 120 ms.

## Gestionnaire des tâches : restes

- 🟢 Colonne « Disque » : les E/S des processus sont ramenées au débit
  physique total. La somme est juste, mais la répartition est approximative.
  Le débit exact demande ETW noyau : l'essai du 2026-10-20 montre que les
  fournisseurs Kernel-Disk/Network/File/Process refusent l'accès sans admin,
  même dans le groupe « Utilisateurs du journal de performances ». Abandonné.
- 🟢 Colonne Réseau par ligne : un nombre de connexions TCP, pas un débit.
  Faisable sans admin via `Microsoft-Windows-TCPIP`, mais indirect (octets
  reçus sous le PID 4, à retrouver par la connexion) et coûteux. Abandonné
  le 2026-10-20.
- 🟢 Spotify : 10 processus contre 12 chez Windows (≈ 7 Mo d'écart),
  probablement des WebView2 hors du dossier du paquet.
- 🟢 Console sous Windows Terminal (terminal par défaut) : Windows affiche
  « PowerShell (3) » comme une app ; chez nous pwsh est en arrière-plan, car
  sa fenêtre appartient à WindowsTerminal.
- 🟢 Clé `app:` instable si le chemin de l'exe devient lisible plus tard
  (`app:notepad` → `app:c:\…\notepad.exe`) : le groupe ouvert se replie.
- 🟢 Titre d'une sous-ligne d'appli du Store : lu sur la CoreWindow, il peut
  être plus court que celui du cadre.
- 🟢 Une page détruite pendant un `tasks_get` en cours peut recréer l'état
  Rust après `tasks_stop`. Il est libéré à la prochaine fermeture de
  l'onglet.
- 🟢 Liste des services relue toutes les 5 s (≈ 31 ms en release).

## Fait

- 2026-10-24, 0.4.18 : `Theme.lift` rend de nouveau une couleur opaque, donc
  les `IconBtn filled`, `TextBtn primary` et `BarContent` sont éclaircis au
  survol au lieu de perdre leur fond. Boucle de liaison `overIsland` corrigée
  (survol de l'îlot).
- 2026-10-20 : onglet Tâches regroupé comme Windows (`procgroup.rs`) :
  hôtes de service par ligne, applis du Store par paquet, statuts Suspendu /
  Ne répond pas / Mode efficacité, ligne Interruptions système, icônes et
  chemins propres aux sous-lignes, caches bornés, chemin illisible retenté.
- 2026-10-18, après 0.4.11 : écouteurs `Api.listen` retirés à la
  destruction (`Api.unlisten`, Réglages et Soundboard) ; couleur source du
  thème calculée par le cœur (`theme_source`), hors du thread de l'interface.
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
