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

- 🟢 **Réglages refaits (2026-10-29) : à confirmer par l'utilisateur**
  - Tant qu'un brouillon existe, les raccourcis d'onglets, Win+V et le
    dépôt de fichiers rouvrent Réglages (barre qui tremble) au lieu de leur
    onglet, même îlot refermé (règle « comme Discord » choisie). À assouplir
    s'il le demande.
  - La liste des onglets dépasse la hauteur du panneau : elle défile (barre
    de défilement, onglet choisi toujours visible).
  - Monochrome ressemble à OLED : à retirer s'il le demande.
  - Une puce revenue à sa valeur par défaut jamais enregistrée (ex.
    `cc_min` 30) reste comptée comme modification (bénin).
- 🟢 **Animations : plan à faire (demande de l'utilisateur, 2026-10-28)** :
  remplacer les réglages d'animation actuels par un simple « Animations :
  oui / non », puis revoir toutes les animations une par une. Prévoir une
  session de planification (maquette de départ :
  `docs/dev/maquettes/animations.html`). Lié : la grille « Style de la
  palette » (ex-Variantes, `SettingsPage.qml`) disparaît pendant le fondu de
  fermeture, car `swatchCache` n'est jamais rempli. L'utilisateur veut le
  traiter dans ce plan, pas seul.
- 🟢 **Quick Share avec iPhone (AirDrop), à étudier (2026-10-28)** :
  recherche faite. AirDrop depuis Windows n'est pas faisable : il faut AWDL,
  donc une carte Wi-Fi en mode moniteur sous Linux, et OWL/OpenDrop sont
  archivés. Le pont AirDrop ↔ Quick Share de Google (Pixel 10, puis Galaxy
  S24-S26…, mode « Tout le monde pendant 10 min ») est propre à Android, et
  son code n'est pas publié. Pistes réalistes :
  1. un mini-serveur HTTP local dans le cœur Rust, avec une page d'envoi et
     de réception ouverte par QR code depuis Safari (rien à installer sur
     l'iPhone ; environ 2 à 4 jours) ;
  2. le protocole LocalSend v2 (ouvert, Apache-2.0 ; appli gratuite sur
     iPhone ; environ 3 à 5 jours).
  Sources principales : blog.google (security, nov. 2025), MacRumors
  (2026-06-02), github.com/seemoo-lab/owl (archivé le 2026-10-12),
  github.com/localsend/protocol.
- 🟢 **Réglages, saut au changement de section** (relevé du 2026-10-26, non
  corrigé, l'utilisateur doit le confirmer) : `SettingsPage.qml`, `Behavior
  on contentY`. Après avoir défilé en bas d'une longue section, cliquer une
  section courte laisse la zone vide environ 0,2 s, puis le contenu tombe du
  haut. Correctif prêt : couper le `Behavior` pendant le retour en haut.
  Même cause : la barre de défilement glissée suit avec retard.
- 🟢 **Bugs visuels relevés le 2026-10-26 et laissés de côté (choix de
  l'utilisateur)** : jaquette de jeu qui tremble au bord bas
  (`AppsPage.qml`, `Translate` au survol), cloche de la barre sans retour
  au survol avec des notifications (`BarContent.qml`), horloge à volets dont
  les 4 chiffres basculent (`PillClock.qml`, modèle recréé chaque minute),
  infobulle au-dessus du menu qu'on vient d'ouvrir (voir plus bas, « menu
  natif »).

- 🟢 **Historique du presse-papiers au clavier (2026-10-27)** : valider
  referme l'îlot même verrouillé (on ne copie plus plusieurs éléments à la
  suite). Avec la touche Windows remappée (F24), Win+↑/↓ puis relâcher Win
  referme l'îlot (la page accepte la flèche, `winTap` reste vrai). Cas rare.

- 🟠 **Îlot en plein écran (2026-10-27)** : pas compilé ni testé sur le
  poste (session cloud). Limites connues :
  - Devant une appli en plein écran, l'îlot n'a jamais le clavier : pas de
    saisie (recherche, champs) ni d'Échap. C'est voulu, pour que le jeu
    garde le focus.
  - Le style `WS_EX_NOACTIVATE` n'est posé qu'au relevé suivant (500 ms au
    plus) : un clic juste à l'entrée en plein écran active encore l'îlot.
  - Les applis UWP sont vues comme `applicationframehost.exe` : on ne peut
    pas en choisir une en particulier.
  - La touche Windows reste rendue à Windows en plein écran, même en
    « Toujours affiché » (`winkey.rs`, `fullscreen_foreground`).

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

- 🟢 **Pilule de dépôt et conversion** (`FileDrop.qml`, `Convert.qml`,
  `files::file_convert`, 2026-10-27) : à tester avec un vrai glisser.
  Restes connus :
  - lâcher directement sur « Applis » (avant 350 ms) ne transmet pas les
    fichiers ;
  - quitter l'appli pendant une longue conversion ffmpeg attend la fin
    (`waitForDone`, ffmpeg n'est pas tué) ;
  - tif, heic et avif sont proposés vers une image même sans ffmpeg, puis
    échouent avec « ffmpeg introuvable » ;
  - « Tout convertir en » pendant une passe peut faire réessayer les lignes
    en erreur ;
  - un GIF animé converti en image ne garde que la première image ;
  - WebP est enregistré sans perte (fichiers gros).

- 🟢 **Infobulle au-dessus d'un menu natif** : `Btn.qml`. Après un clic sur
  une icône de la zone de notification, le menu de l'appli capture la souris.
  Notre infobulle peut rester affichée jusqu'au prochain mouvement sur la
  barre. Correction possible : masquer le `Tip` à l'appui.

- 🔴 **Réglages qui reviennent en arrière** : `qt/qml/Ilot.qml:30` (`setCfg`).
  Les réponses `settings_set` passent par le pool de threads, donc elles
  peuvent arriver dans le désordre. Chacune contient la configuration complète
  et écrase `cfg`. Correction possible : un numéro de séquence, ou fusionner
  seulement les clés du `patch`.
- 🟢 **Animations d'ouverture** : `setHit` n'est plus refait à chaque
  image (`hitBox`, `Main.qml`, 2026-10-27). Reste : `setBackdrop` à chaque
  image en mode acrylique, nécessaire pour que le flou suive la forme ; à
  mesurer si ce mode saccade.
- 🟢 **Ombre portée de l'îlot** (maquette `animations.html`, 3) : impossible
  telle quelle, le masque de la fenêtre (`setMask`, `SetWindowRgn`) coupe
  tout ce qui sort de l'îlot. Il faudrait une fenêtre d'ombre séparée,
  transparente aux clics (`WS_EX_TRANSPARENT`), sous l'îlot.
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

- 🟢 **Outils Windows dans Apps** (`src/apps.rs`, `TOOLS`) :
  - les éléments du Panneau de configuration qui renvoient aux Paramètres
    restent listés (masquables) ;
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

## Mémoire (voir `docs/perf-memoire.md`)

Répartition mesurée le 2026-10-29 (297 Mo privés, 193 Mo au Gestionnaire).

- 🟠 **NVML** (`activity.rs`) : ~19 Mo. Remplaçable par D3DKMT
  (température) et PDH « GPU Engine » (charge).
- 🟢 **Barre du second écran** : ~40 Mo et ~40 threads (2e device D3D11).
  Device partagé (`QQuickGraphicsDevice::fromRhi`, boucle `basic`), risqué.
- 🟠 **Montée en cours de journée** : 449 Mo une heure après le lancement
  (2026-10-29), contre ~300 Mo au départ. Ce sont surtout des blocs privés
  de ~15 Mo qui s'ajoutent (9 de plus au bout d'une heure). Relever avec
  `%TEMP%\ilot-vm.ps1` toutes les 10 min pendant une journée normale.

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

- 2026-10-29, 0.4.24 à venir : icônes des applis demandées à 48 px
  (`apps.rs`, `icon_of`) au lieu de 64 : −75 Mo au lancement (liste jumbo
  du shell évitée). Qualité validée par l'utilisateur.
- 2026-10-29, après 0.4.23 : images de l'historique du presse-papiers
  gardées en PNG au lieu du RGBA brut (jusqu'à 8 × 15 à 33 Mo). Détail
  dans `docs/perf-memoire.md`.
- 2026-10-28, 0.4.23 à venir : 25 bugs visuels (survol, clics qui
  traversent, coins, thème clair, aperçu des fenêtres, soundboard, Wi-Fi).
  Détail dans `ETAT.md`, session « bugs visuels ».
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
