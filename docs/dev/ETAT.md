# État du projet : journal des sessions

**À lire en premier à chaque session.** Ajoute une entrée en haut à la fin de
chaque session : ce qui a été fait, ce qui a été vérifié ou non, et où
reprendre.

## Où on en est (mis à jour le 2026-10-25)

- **Version** : 0.4.21 (sélecteur Bluetooth, paroles des vidéos YouTube),
  publiée le 2026-10-26 par le tag `v0.4.21`. Appairage et connexion
  Bluetooth réels encore à tester (journal du 2026-10-26). Avant : 0.4.20
  (sorties affichées, Réglages › Son), publiée le 2026-10-25. Avant : 0.4.19 (mélangeur multi-sorties), publiée le 2026-10-25. Avant :
  0.4.18 (patch du lecteur), publiée le 2026-10-24 par le tag
  `v0.4.18` (GitHub Action `release.yml`). La 0.4.17 (addon Claude, hooks
  WSL, Apex) l'a été le même jour. La 0.4.8 n'a jamais été publiée seule : elle
  est incluse dans la 0.4.9.
- **Installée sur le poste** : oui, dans `%LOCALAPPDATA%\Programs\Ilot`, avec
  un raccourci dans le dossier Démarrage. Elle a été construite depuis les
  sources par `install.ps1`.
- **Consigne de l'utilisateur** : ne corriger que l'essentiel, sans rien qui
  change l'usage. Le Rust se traite « selon l'usage », et les bugs au fur et à
  mesure. Ce qui reste à faire est dans `BACKLOG.md`.
- **Lecteur de musique (0.4.16)** : une première version, validée par
  l'utilisateur. Il reste à le tester à la main (voir « Non vérifié » dans le
  journal du 2026-10-23).
- **Prochaine étape** : vérification visuelle par l'utilisateur (coins de
  l'onglet Média, pochette ronde + spectre, réglages du fond, nouvelle section
  Réglages), puis lot Rust média (`BACKLOG.md`, « Lot suivant du lecteur »).
  Option encore en attente de son accord, hors lecteur : « Redémarrer » dans
  le clic droit de la ligne `explorer`.

## Journal

### 2026-10-27 : Apps, Launcher et Jeux inversés, dossiers, commandes

- **Demande** : les launchers étaient dans « Jeux » et les jeux dans
  « Launcher ». Pouvoir supprimer les dossiers. Plus de commandes « > ».
- **Inversion** (`Ilot.qml` `seedGames`, `AppsPage.qml`) : la puce des jeux
  détectés s'appelle « Jeux ». Le dossier « Jeux » devient « Launcher ».
  Migration `folders.layout` 1 → 2 : dans l'ancien dossier, seuls les
  launchers restent (`launcherHints`). Le reste passe dans `folders.games`.
  Un jeu passe avant un launcher (`gameHints` : Minecraft, Valorant, Lunar
  Client, Genshin…). Nouvelle installation : dossier « Launcher » + jeux dans
  `folders.games`.
- **Dossiers** : `folderMenu` agissait sur le `modelData` du Repeater, qui
  est une copie. Supprimer et renommer étaient donc perdus. Le dossier est
  désormais retrouvé par id.
- **Commandes** : volume N %, muet, lecture/pause, pistes, « Ouvrir » +
  onglets activés, Corbeille, Téléchargements, dossier des fonds,
  gestionnaire des tâches de Windows, actualiser les applis et les jeux,
  mise à jour.
- Vérifié : compilé, la migration a tourné sur le `folders.json` du poste
  (sauvegarde prise avant). Relu par un agent : pas de bug, deux remarques
  appliquées (libellé du mode jeu, ancien `seeded:false` avec « Jeux »).
- Non vérifié : la suppression et le renommage d'un dossier au clic, et les
  nouvelles commandes, à tester par l'utilisateur. Rien n'est commité.

### 2026-10-26 : sélecteur Bluetooth (Contrôles)

- **Demande** : sélecteur Bluetooth avec appairage, et appareils déjà
  appairés dans l'onglet Contrôles.
- **Rust, nouveau `src/bt.rs`** : `bt_list` (appairés, classique + BLE, avec
  état connecté et icône d'après la classe / l'apparence, puis appareils
  trouvés), `bt_scan(on)` (DeviceWatcher sur les non-appairés ; arrêt seul
  après 20 s sans `bt_list` ; relancé si Windows l'a interrompu),
  `bt_pair` (appairage personnalisé : ConfirmOnly accepté, code envoyé à
  l'interface par l'événement `bt_pin`, réponse par `bt_pair_answer` ; un
  seul à la fois), `bt_unpair`, `bt_connect` (casques et enceintes :
  `IKsControl` `KSPROPSETID_BtAudio` ONESHOT_RECONNECT / DISCONNECT sur les
  pilotes retrouvés depuis les sorties audio, comme ToothTray).
  `Cargo.toml` : `windows-collections`, feature
  `Win32_Media_KernelStreaming`. `--check-all` affiche `bt:` (6 s de
  recherche).
- **QML, `CtrlPage.qml`** : chevron sur la tuile Bluetooth → feuille
  « Bluetooth » (Appareils appairés / À proximité), composants `BtHead` et
  `BtRow`. L'état des actions est gardé dans la page par identifiant
  (`btOps`) : le sondage (2 s) recrée les lignes quand la liste change, et
  ne la remplace pas pendant la saisie d'un code.
- **Vérifié** : clippy propre ; `--check-all` liste les 3 appareils
  appairés du poste (manette Xbox, Stadia, casque « Zen Air Plus » reconnu
  audio) ; essai temporaire (retiré) : 2 pilotes KS trouvés pour le casque ;
  capture de la feuille (`ILOT_QT_SHOT`) correcte. Installé.
- **Relecture** : un agent général (pas de `relecteur` sur le poste). Il a
  trouvé la recréation des lignes toutes les 2 s (état perdu, saisie du code
  impossible), la recherche non relancée après coupure de la radio, deux
  appairages simultanés, et le nom vide qui visait toutes les sorties :
  tout est corrigé.
- **Non vérifié** : appairage réel d'un nouvel appareil (avec code),
  connexion / déconnexion réelle du casque, oubli. À tester par
  l'utilisateur. Limites dans `BACKLOG.md`.
- **Publié** en 0.4.21 (tag `v0.4.21`), à la demande de l'utilisateur.

### 2026-10-26 : paroles des vidéos YouTube

- **Constat.** Une vidéo YouTube lue dans le navigateur donne pour titre
  « Artiste - Titre (Clip officiel) » et pour artiste la chaîne
  (« ArtisteVEVO », « Artiste - Topic », un label), sans album.
  `clean_title` coupait au « - » : la recherche portait sur « Artiste ».
- **`src/lyrics.rs`.** Nouvelle fonction `youtube()` : sans album, si le
  titre est « gauche - droite » et que la gauche ressemble à la chaîne, ou
  que la chaîne a un suffixe YouTube (`VEVO`, ` - Topic`, `Official`), ou
  que le titre a une mention vidéo entre parenthèses (official, clip,
  lyrics, audio, video…), on cherche (gauche, droite nettoyée de
  `ft.`/`feat.`/`|`/guillemets). Sans « - » : (chaîne sans suffixe, titre
  nettoyé). Sinon rien ne change. Recherche LRCLIB + NetEase sortie dans
  `lookup()`. Le cache reste indexé par l'artiste et le titre d'origine.
  Test `youtube_titles` (sans réseau).
- **Vérifié.** `cargo test --lib lyrics` OK, clippy sans avertissement dans
  `lyrics.rs`, le Rust compile dans `qt\build.cmd`.
- **Build.** Premier essai : lien de `ilot.exe` en échec (LNK1104, l'appli
  tournait).
- **Retour utilisateur : ne marchait pas.** Titre réel reçu de Chrome :
  `【Ado】Raven Sky` (artiste « Ado », sans album, 252 s). Ajout de
  `strip_jp()` : retire les `【…】` et prend le contenu de `「…」` comme
  titre ; `video_tag` lit aussi `【…】`. Essai réseau (test temporaire,
  retiré) : `lookup("Ado", "Raven Sky")` renvoie les paroles synchronisées.
  **Piège** : les deux builds précédents étaient en échec silencieux (lien
  de `ilot.exe` raté, code de sortie perdu par `powershell -Command`), donc
  `qt\build\ilot_core.dll` restait l'ancienne (la copie de la DLL est une
  étape après le lien). Lire `%errorlevel%` dans le `cmd /c` et la date de
  `qt\build\ilot_core.dll`. Rebuild vérifié puis `install.ps1` : version
  installée et lancée depuis `%LOCALAPPDATA%\Programs\Ilot`. Pour lire les métadonnées envoyées par le
  navigateur : script PowerShell WinRT (`GlobalSystemMediaTransportControlsSessionManager`).
- **Second morceau** : `Leina 「誓い」 Music Video` (clip de 191,8 s, morceau
  NetEase de 176,7 s). NetEase rejetait au-delà de 8 s d'écart. Pour une
  vidéo, si rien d'horodaté n'est trouvé, nouvel essai NetEase sans la
  durée. Essai réseau OK, installé (DLL du 26/10 12:54 dans
  `Programs\Ilot`). Limite : l'intro d'un clip peut décaler les paroles
  horodatées.
- **Validé par l'utilisateur** : paroles de 「誓い」 trouvées (cache du
  26/10 14:22). Section « À venir » dans `CHANGELOG.md`, poussé sans
  release ni changement de version (demande de l'utilisateur).
- **Non vérifié.** Pas de relecture par l'agent `relecteur`
  (absent du poste).

### 2026-10-25 : 0.4.20 (sorties affichées, Réglages › Son)

- **Demande** : pour les amis qui ont Voicemeeter, VB-Cable, Sonar…, choisir
  les sorties montrées par l'îlot.
- **Maquette validée** : `docs/dev/maquettes/sorties.html` (le style de
  Contrôle et de Réglages y est recopié du QML).
- **Choix de conception**, issus de 3 agents (UX, utilisateur de Voicemeeter,
  avocat du diable) :
  - liste noire, sans aucun masquage automatique (chez un utilisateur de
    Voicemeeter, la sortie virtuelle est celle qu'il utilise) ;
  - la sortie par défaut est toujours visible ;
  - avant le premier choix, le tri automatique est inchangé, et le premier
    choix part de son état ;
  - on peut renommer une sortie.
- **QML seul** :
  - nouvel onglet Son dans `SettingsPage` (composant `OutRow`) ;
  - filtrage dans `Mixer.rebuild` et dans `CtrlPage` : feuille, icône tune,
    ligne « N sorties masquées », encart du premier lancement ;
  - outils communs dans `Ilot.qml`.
- **Correctif lié** : le nom court du mélangeur abîmait « Speakers
  (Realtek(R) Audio) » en « Speakers Audio) ». Le nommage est maintenant
  commun au mélangeur et aux Réglages (`Ilot.outInfo`).
- **Colonne d'onglets de Réglages** : 12 onglets ne tenaient plus à la taille
  normale. Les boutons passent à 36 px et l'espacement à 2 px.
- **Relectures** : 6 séries, chaque fois par 2 agents `relecteur` neufs
  (13 relecteurs en tout). Les dernières se sont appuyées sur des bancs
  `qmltestrunner` qui reproduisent la vraie hiérarchie : focus, Échap,
  clics, `loadOuts`. Les défauts trouvés ont été corrigés au fur et à
  mesure : Échap entre deux renommages, focus rendu à la racine de la
  fenêtre, chargement initial vide, envoi à la fermeture, débordement de la
  colonne d'onglets, clics dans les marges. La dernière série (2 relecteurs)
  a tout validé.
- **Vérifié** :
  - compilation, et qmllint sans avertissement nouveau (hors singletons non
    résolus) ;
  - expressions régulières testées sous node ;
  - capture réelle de Contrôle en tri automatique, identique à avant.
- **Vérifié dans l'appli réelle** (poste à 9 sorties Sonar, réglages
  sauvegardés puis restaurés) :
  - **Captures** : Contrôle (mélangeur), Réglages › Son et feuille
    « Sortie audio », chacune en tri automatique puis avec un choix fait
    (sorties masquées, sortie absente, noms choisis).
  - **Vrais clics et vraies touches** (SendInput et SendKeys sur l'îlot
    ouvert), puis lecture de `settings.json` :
    - le premier interrupteur part du tri automatique ;
    - Entrée valide un nom, Échap l'annule et l'îlot reste ouvert ;
    - passer d'une ligne à l'autre enregistre la première ;
    - un clic dans le vide de la carte valide ;
    - Échap après les renommages referme l'îlot ;
    - quitter 62 ms après un clic enregistre quand même le choix (envoi à
      la fermeture).
  - **Défaut trouvé par ces tests, et corrigé** : le texte du tri
    automatique faisait remonter les lignes de 52 px au premier choix. Il
    est maintenant sous les listes.

### 2026-10-25 : 0.4.19 (mélangeur multi-sorties)

- Maquette validée : `docs/dev/maquettes/melangeur.html` (version « A
  pratique » : pastilles de sorties + liste groupée), avec filtre multiple,
  sans préréglages ni compteur d'applis. Différences dans l'appli : niveau
  dans le coin des pastilles, mode « essentiel » ci-dessous.
- Mode « essentiel » (demandé après la 1re capture réelle : 9 sorties, trop) :
  avec Sonar, seulement Game / Chat / Media / Aux ; sinon la sortie par
  défaut ; plus toujours la sortie par défaut et toute sortie où joue une
  vraie appli (hors « Sons système »). Bouton « +N » = tout montrer.
  `audiodg.exe` est ignoré ; « Sons système » seulement sur la sortie par
  défaut. Logique dans `Mixer.qml`, `rebuild()`.
- Publiée : tag `v0.4.19` poussé le 2026-10-25 (CI lancée, fin non suivie).
- **Retours de l'utilisateur attendus** sur le mélangeur (il a des choses à
  redire) : repartir de là.
- Rust (`src/audio.rs`) : `mixer_all`, `mixer_set` avec `device` optionnel,
  `device_volume_set`, `app_route` / `app_route_get` (fabrique WinRT
  `Windows.Media.Internal.AudioPolicyConfig`, vtable reprise d'EarTrumpet),
  `hide_stale` (masque la session inactive restée sur l'ancienne sortie),
  cache nom + icône par exe. Feature `Win32_System_WinRT`. Tests `#[ignore]`
  `route_reel` et `route_chrome` (lancent leur propre processus et restaurent
  la préférence).
- QML : nouveau `Mixer.qml` dans la carte audio de `CtrlPage`. Profils de
  volume retirés de l'interface, de `Watch` (plus appliqués au lancement d'un
  jeu) et de `SettingsPage`. Police : `drag_indicator` et `star` ajoutées
  (310 ligatures, axes FILL 0 / GRAD 0 / opsz 24 / wght 400).
- `shell.cpp` : `ILOT_QT_SHOT_TAB=<onglet>` ouvre l'îlot avant la capture
  `ILOT_QT_SHOT` (tests).

Vérifié : `cargo clippy`, `cargo test` (28 + 3 ignorés), tests réels de
routage (Sonar respecte le routage ; Chrome bascule à chaud, le lecteur WinMM
de PowerShell seulement après relance), `qt\build.cmd`, capture réelle de
l'onglet Contrôles avec les 9 sorties du poste, relectures `relecteur`.
Non vérifié : glisser, filtre et sélecteur à la vraie souris dans l'appli
(validés seulement hors appli par `qml.exe` et dans les maquettes).

### 2026-10-24 : 0.4.18 (patch lecteur)

- Maquette `docs/dev/maquettes/lecteur-reglages.html` validée.
- Correctif des coins de l'onglet Média.
- Nouveaux réglages du lecteur. Clés : `player_btn` (none), `player_btn_color`,
  `player_btn_ink`, `player_btn_spin` / `player_btn_morph` / `player_btn_pop` /
  `player_btn_glow`, `player_bar_size` / `player_bar_amp`, `player_art` (disc),
  `player_spectrum` (null = suit la pochette), `media_blur` / `media_drift` /
  `media_dim`, `player_mini_ring` / `player_mini_spin`.
- `Theme.lift` et boucle `overIsland` corrigés (voir `BACKLOG.md`, « Fait »).
- `Ilot.spectrumOn` coupe la capture audio.
- Numéro : prévu en 0.4.17, mais une autre session avait publié la 0.4.17
  (addon Claude) entre-temps ; rebasé et publié en 0.4.18.
- Vérifié : build + install OK, qmllint sans nouveau type d'avertissement,
  journal Qt vide au démarrage, 2 relectures (aucun bloquant).
- Non vérifié à l'écran : rendu des coins, pochette ronde + spectre, réglages
  du fond, nouvelle section Réglages.

### 2026-10-24 : addon « Claude », utilisation de l'abonnement

- **Demande.** Afficher l'utilisation de Claude, à la semaine et « au jour ».
  Claude ne publie pas de limite journalière : on montre la **session de
  5 h** et la **semaine** (plus Opus / Sonnet s'ils existent), comme `/usage`
  dans Claude Code.
- **Source.** `GET https://api.anthropic.com/api/oauth/usage` (en-tête
  `anthropic-beta: oauth-2025-04-20`) avec le jeton OAuth de Claude Code
  (`~/.claude/.credentials.json`, Windows puis WSL démarrés ; le jeton
  valable le plus longtemps). On ne le rafraîchit **jamais** : le jeton de
  rafraîchissement changerait et Claude Code serait déconnecté. Expiré :
  message « relance Claude Code ». Réponse gardée 1 min (10 s si Actualiser).
- **Fichiers.** `src/claude.rs` (`usage`, commande `cc_usage` dans
  `lib.rs`), nouveau `qt/qml/ClaudeUsagePage.qml`, entrée `cusage` du
  catalogue dans `Ilot.qml`. Relevé à l'ouverture puis toutes les 2 min,
  seulement quand la page se voit : rien en arrière-plan.
- **Projection.** Rythme moyen depuis le début de la fenêtre (5 h ou 7 j,
  déduit de `resets_at`) : « ≈ 68 % à la remise à zéro » ou « limite
  atteinte vers 16:10 », et partie claire de la barre jusqu'au niveau prévu.
  Rien d'affiché avant 5 % de la fenêtre écoulée (trop peu de recul).
- **Graphique façon Agent Burn** (Melvynx, `agent-burn.melvynx.dev`) :
  nouveau `qt/qml/UsageChart.qml` (Canvas). Utilisation sur toute la fenêtre
  (choix Session / Semaine), relevés en trait plein, prévision en tirets
  jusqu'à la remise à zéro (ou jusqu'à 100 %), rythme régulier en pointillés,
  point « maintenant ». Phrase d'état au-dessus (« De la marge… », « Rythme
  serré », « Limite atteinte vers… »). Contrairement à Agent Burn, l'axe
  montre l'utilisé (comme les cartes), pas le restant.
- **Historique.** `claude::record` garde les relevés dans
  `%LOCALAPPDATA%\Ilot\claude-usage.json` (fenêtre en cours seulement ; un
  point par changement ou toutes les 15 min). `claude::watch` relève toutes
  les 5 min tant que l'addon `cusage` est activé. Le jeton WSL n'est cherché
  que si celui de Windows ne sert pas (évite `wsl.exe` toutes les 5 min).
  `iso_ms` convertit `resets_at` (test `date_iso`).
- **Pièges.** Police d'icônes en sous-ensemble (`data_usage` absente, noté
  dans `CLAUDE.md`). Une propriété `data` sur un `Item` masque ses enfants
  (onglet vide) : renommée `usage`.
- **Vérifié.** Point d'accès testé avec `curl` (session 47 %, semaine 40 %).
  Build complet OK, clippy sans avertissement dans `claude.rs`, pas d'erreur
  QML au démarrage.

### 2026-10-24 : Apex, plus de minuteur ni de fausse « Partie trouvée »

- **Constat (utilisateur).** Dans Apex, un minuteur apparaissait sans
  recherche lancée, et parfois « Partie trouvée » sans recherche. Cause :
  hors Valorant, l'îlot ne sait pas si on est en file. Il prenait « autre
  fenêtre au premier plan » pour « en attente » (minuteur), et une lecture
  disque > 25 Mo/s pendant 2 s pour « carte en chargement » ; Apex lit autant
  dans le lobby.
- **Choix de l'utilisateur.** Minuteur retiré hors du jeu (Valorant garde son
  vrai temps de file). Détection : clignotement de la fenêtre seulement.
- **`src/activity.rs`.** `MatchWatch` ne garde que `HSHELL_FLASH` ; retrait de
  `read_bytes`, `LOAD_RATE` et des imports devenus inutiles.
- **`Watch.qml`.** La pilule et l'aperçu n'affichent plus « En attente
  depuis » ; le minuteur QML ne passe plus à 1 s hors du jeu.
- **Vérifié.** Build complet, `cargo test` 27/27, clippy sans nouvel
  avertissement, aucune erreur QML au démarrage. **Pas testé en jeu** : reste
  à voir si Apex fait clignoter sa fenêtre quand la partie est trouvée (sinon,
  plus d'alerte pour Apex).

### 2026-10-24 : hooks Claude Code aussi pour Claude lancé dans WSL

- **Constat.** `ilot.exe --claude` marche déjà depuis WSL : l'interop lance
  l'exe Windows, le JSON passe par stdin, l'événement arrive dans l'îlot
  (≈ 70 ms). Il manquait seulement les hooks dans le `~/.claude/settings.json`
  **côté Linux**, que Claude Code dans WSL lit à la place de celui de Windows.
- **`src/claude.rs`.** Le bouton « Installer » / « Retirer » traite aussi les
  distributions WSL (`wsl.exe --list --quiet`, sans `docker-desktop*`) : pour
  chaque `\\wsl.localhost\<distro>\home\*\.claude` (et `/root`) existant,
  mêmes hooks avec la commande `'/mnt/c/.../ilot.exe' --claude`. L'état ne
  regarde que les distributions déjà démarrées (`--running`), pour ne pas
  réveiller WSL en ouvrant les réglages. Libellé : « (Windows et WSL) ».
- **Vérifié.** `cargo test` : nouveau test `chemin_wsl`. Clippy sans
  avertissement dans `claude.rs`. Build complet OK. Détection testée : seul
  `Ubuntu/home/tidic/.claude` est trouvé, état « pas installé » tant que WSL
  n'a pas les hooks.

### 2026-10-23 (suite) : variantes choisies dans l'atelier, intégrées

Page de variantes `docs/dev/maquettes/atelier.html`, aux dimensions réelles
de l'îlot. Choix de l'utilisateur :
- pilule repliée B ;
- pilule survolée A ;
- widget de l'accueil C ;
- onglet Média A ;
- molette C.

- **Pilule repliée** (`Pill.qml`) :
  - plus d'égaliseur `Eq` (fichier gardé, il ne sert plus) ;
  - disque de 18 dans un anneau de progression de 24, dessiné avec un Shape
    de deux `PathAngleArc` ;
  - Timer de 2 s, actif seulement en replié pendant la lecture ;
  - largeur avec média : 183 (avant 200).
- **Molette** : option `cfg.player_wheel`, désactivée par défaut, dans
  Réglages > Lecteur. Pendant la lecture, la molette règle le volume de l'appli
  qui joue (`app_volume_get` / `app_volume_set`, pas de 4 %), sinon le volume
  général.
- **Accueil** (`HomePage.qml`) : la carte musique est refaite d'après la
  maquette. Fond pochette floutée, pochette 198, titre qui défile, PlayBtn,
  précédent / suivant, SeekBar. L'ancien disque, ses 48 bras et `VizBars` sont
  retirés (`VizBars.qml` gardé, il ne sert plus).
- **Onglet Média** : tailles alignées sur la variante A, à 708×459 (pochette
  156, colonne 340, boutons 44 / 58 / 44 dans `MediaControls` big), lueur sur
  la ligne de paroles active.
- **`Ilot.updateViz`** : la capture du son ne tourne plus que si quelqu'un la
  lit (compagnon, fond « aurore », onglet Média).

Vérifié :
- compilé et installé ;
- journal Qt vide au lancement ;
- relu par l'agent `relecteur`, remarques appliquées.

Non vérifié : le rendu à l'écran, aucun survol ni ouverture n'a été fait en
automatique. Publié en 0.4.16.

### 2026-10-23 : refonte du lecteur de musique (style Swiftify)

Plan : `docs/dev/PLAN-MEDIA.md`. Maquette validée par l'utilisateur :
`docs/dev/maquettes/media.html` (à ouvrir dans un navigateur). Swiftify, c'est
https://github.com/swiftify-org/swiftify, un lecteur Spotify en Qt/QML + Rust,
sans licence : on reprend les valeurs, pas le code.

- **Survol de la pilule** (`Pill.qml`, 460×76 dans `Ilot.sizeFor`) : pochette,
  titre, artiste, barre de progression cliquable, précédent / lecture /
  suivant. Rien de tout ça n'ouvre le panneau. Le clic ailleurs l'ouvre comme
  avant.
- **Nouveaux composants** :
  - `SeekBar.qml` : barre ondulée (`shaders/wave.frag`), qui s'épaissit au
    survol, avec poignée et bulle de temps. Le seek part au relâchement, et
    pas de seek si la piste a changé pendant le glisser.
  - `PlayBtn.qml` : bouton « cookie » festonné (`shaders/cookie.frag`), qui
    tourne en lecture. Blanc avec une lueur colorée dans l'onglet Média.
- **Onglet Média** (`MediaPage.qml`) :
  - disposition en colonne, paroles à droite, ou côte à côte, paroles en
    bandeau ;
  - pochette festonnée (`shaders/scallop.frag`) entourée d'un anneau de
    spectre (`shaders/ring.frag`) ;
  - halo flou ; pochette réduite et assombrie en pause ;
  - titre qui défile ;
  - fond pochette floutée qui dérive lentement ;
  - pastilles « Paroles » / « Playlists » ; plus de `VizBars` dans la page.
- **Accueil** : la carte musique gagne la barre de progression et la couleur
  du lecteur.
- **`Ilot.qml`** :
  - `seekDrag` / `setSeekDrag` : l'îlot ne se replie pas pendant un glisser,
    et se replie au relâchement hors de l'îlot ;
  - `seek()` relit `media_get` (tout de suite si refus, 1,5 s après sinon) ;
  - `playerPal` : couleur du lecteur ;
  - `artColor()` tourne aussi quand le lecteur suit la pochette.
- **Réglages > Apparence > Lecteur de musique**, en `cfg.player_*` : couleur
  (pochette, thème ou pastille), barre ondulée ou plate, bouton festonné ou
  rond, bouton de l'onglet Média blanc ou en couleur, pochette, disposition,
  glisser la pochette pour changer de titre (désactivé par défaut).
- **Rust `media.rs`** :
  - `media_action` renvoie le booléen de l'appli ;
  - `MediaInfo` gagne `can_seek`, `can_next` et `can_prev`, qui valent vrai
    si la lecture échoue.
- `M3Slider` gagne `accent` et `trackColor` (valeurs par défaut inchangées).

Vérifié :
- `qtuild.cmd`, `install.ps1` (installée et relancée), `cargo clippy` (pas
  de nouvel avertissement), `cargo test` (26 ok).
- Pas d'erreur de qmllint sur les fichiers touchés.
- Journal Qt sans erreur au lancement.
- Capture réelle de la pilule survolée : pochette, barre, 3 boutons, Discord.
- Maquette testée dans Chromium (Playwright) : glisser hors de l'îlot,
  boutons sans ouverture, resynchro, direct.
- Deux relectures par l'agent `relecteur`, remarques appliquées.

Non vérifié (à tester à la main) :
- glisser la barre puis relâcher hors de l'îlot dans la vraie appli ;
- seek dans Spotify et dans un navigateur ;
- onglet Média ouvert, paroles, pochette festonnée et anneau ;
- thème clair, tailles de pilule S et L ;
- CPU en survol et onglet ouvert (l'ondulation et la dérive du fond tournent
  tant qu'ils sont visibles).

Non commité.

### 2026-10-20 : « Fin de tâche » dans le menu clic droit de la barre

- `BarContent.qml` : entrée « Fin de tâche », sans confirmation comme la
  barre des tâches Windows. Message « Fin de tâche refusée » s'il y a un refus.
- `src/bar.rs` `task_end(ids)` : tue le processus de chaque fenêtre (pid
  dédoublonné). Pour une UWP (ApplicationFrameHost), il vise le pid d'une
  fenêtre enfant ; une UWP réduite compte comme refusée. Le nom est lu sur le
  handle qui sert à terminer. Sont refusés : l'îlot, `explorer` et
  `tasks::PROTECTED` (devenu `pub(crate)`). `exe_of` est découpé en
  `exe_of_pid` / `image_name`.
- Piège : `qt/fonts/MaterialSymbolsRounded.ttf` est un sous-ensemble
  (303 icônes). `dangerous` et `block` n'y sont pas : il faut vérifier les
  ligatures (fontTools, table GSUB) avant d'utiliser une nouvelle icône.
- Compilé, relu par un agent. Pas testé à la souris.

### 2026-10-20 : onglet Tâches regroupé comme Windows

Reprise du plan de la session du 19 (non commitée) : commit, puis rebase sur
`origin/main`. Deux autres sessions avaient publié les versions 0.4.12 à
0.4.14 entre-temps. Le seul conflit était dans `ETAT.md`. Travail fait par
4 agents en parallèle, puis un intégrateur.

- **ETW abandonné** (choix de l'utilisateur). Le groupe « Utilisateurs du
  journal de performances » (S-1-5-32-559) est actif sur le compte, mais
  sans admin les fournisseurs Kernel-Disk, Kernel-Network, Kernel-File et
  Kernel-Process répondent « Accès refusé ». Seul TCPIP passe. Disque et
  réseau par ligne restent donc comme avant.
- **`src/procgroup.rs`** (algorithme pur, 13 tests). Règles vérifiées par
  captures du Gestionnaire prises au même moment :
  - une app comprend le processus à fenêtre, ses descendants du **même exe**
    et son `conhost`. EpicWebHelper sous EpicGamesLauncher, et claude sous
    pwsh, ont leur propre ligne ;
  - appli du Store : tout le paquet (`ident_of` → `pkg:<famille>`).
    « Spotify Launcher » regroupe Spotify, le launcher et crashpad ;
  - arrière-plan : une ligne par arbre de même exe (`tree:<pid>:<ms>`),
    **sans** fusion par nom. Deux EpicWebHelper frères font deux lignes,
    comme chez Windows ;
  - un svchost par ligne (`svc:`), un csrss par ligne (`one:`).
- **`src/svc.rs`** : `services_by_pid()` (EnumServicesStatusExW, cache 5 s,
  ≈ 31 ms par relecture). Lignes « Hôte de service : X » ou « X +N », et
  services listés quand on déplie la ligne.
- **`tasks.rs`** :
  - statuts : Suspendu (threads lus dans `SystemProcessInformation`), Ne
    répond pas (`IsHungAppWindow`, sur la CoreWindow pour le Store), Mode
    efficacité (PowerThrottling, cache 5 s) ;
  - ligne « Interruptions système » ;
  - fenêtres du Store attribuées à la vraie appli ;
  - chemin illisible retenté toutes les 10 s, caches bornés à 512 ;
  - `task_kill(key, members)` revérifie l'heure de création sur le handle
    (`born_at`) avant `TerminateProcess`.
- **QML** :
  - le groupe est identifié par `key` ;
  - fin de tâche par `members`, refusée pour `svc:` et `sys:` ;
  - icône, chemin et bouclier propres à chaque sous-ligne ;
  - icône de statut avec info-bulle.
- **Vérifié** :
  - `cargo test` 26/26, clippy propre dans les fichiers touchés, qmllint
    sans nouvelle catégorie ;
  - `install.ps1` OK, journal Qt vide au démarrage ;
  - relu deux fois par `relecteur` : 3 corrections appliquées, le reste est
    dans le BACKLOG ;
  - les 10 premières lignes (triées par mémoire) sont identiques au
    Gestionnaire, dans le même ordre et à 0,7 Mo près : Zen 19, Spotify,
    Discord 6, EpicWebHelper, DWM, Everything, Claude Code, Defender,
    EpicGamesLauncher, Explorateur.
- **Coût** : `tasks_get` passe de 15 à 21-22 ms (la liste des services
  revient toutes les 5 s), seulement quand l'onglet est ouvert.
- **Incident** : la première version d'un test de l'intégrateur
  (`principal_seulement…`) pouvait tuer des `cmd.exe` du poste en
  arrière-plan. Le test a tourné 2 fois avant d'être corrigé. Il ne vise
  plus que ses propres pid.
- **Piège** : depuis le Bash de Claude Code, un heredoc Python qui contient
  des `\\` ou `\n` dans des chaînes Rust les abîme. Il faut passer par Edit
  ou par un script `.py` écrit avec Write.
- **Non vérifié** :
  - l'onglet affiché dans l'îlot (le clic simulé n'ouvre pas l'îlot) ;
  - le tri inversé, le menu clic droit, la fin de tâche à l'écran ;
  - « Ne répond pas » sur une vraie appli bloquée.

### 2026-10-20 : barre, aperçu qui se fermait, menu clic droit des applis

Retour d'usage : l'aperçu des fenêtres se fermait quand on descendait vite
de l'icône vers lui. Demande : un menu clic droit sur les applis de la barre.

- **Cause** : un même mouvement rapide fait entrer dans l'aperçu avant de
  quitter `tasksHover`. L'entrée arrête `hideTimer`, la sortie le relance, et
  l'aperçu se ferme sous la souris.
- `TaskPreview.qml` : `hideTimer` ne ferme plus si l'aperçu est survolé.
  `Ilot.previewOpen` et `hideBarLater` sont gérés par `BarContent` (aperçu
  ou menu ouvert).
- `BarContent.qml` : clic droit sur une appli. Un `CtxMenu` sous la barre,
  dans les zones cliquables, propose :
  - « Nouvelle fenêtre » : `app_launch` si l'AUMID est dans `Ilot.apps`,
    sinon la nouvelle commande `task_new` (lance l'exe) ;
  - « Fermer la/les fenêtre(s) ».

  Le menu se ferme 800 ms après que la souris a quitté le menu et les applis,
  ou quand l'appli n'a plus de fenêtre. Il garde la barre affichée en
  masquage auto.
- `src/bar.rs` `task_new(path)` + `lib.rs`.
- Compilé, qmllint sans nouvel avertissement, relu par un agent. Pas testé à
  la souris. Défaut connu, déjà présent pour l'aperçu : près de l'îlot, le
  menu peut passer sous lui.

### 2026-10-20 : alerte « partie trouvée » au lancement d'un jeu, son

Retour d'usage : l'assistant de jeu sonnait aussi au lancement du jeu, et
le carillon (bips `Beep`) ne plaisait pas.

- **Cause** : pendant le launcher et le chargement, la fenêtre du jeu n'est
  pas encore au premier plan. Le joueur est donc vu « hors du jeu ».
  `MatchWatch` prenait alors la lecture disque du chargement initial (ou un
  clignotement de fenêtre) pour une partie trouvée.
- `src/activity.rs` : `seen` retient l'id du jeu déjà vu au premier plan.
  La veille « partie trouvée » ne s'arme qu'après ça. `seen` est remis à zéro
  quand plus aucun jeu ne tourne.
- `Watch.qml` : partie trouvée et rappel Valorant jouent `Backend.bubble()`,
  le son de l'assistant Claude. `Backend::chime` est supprimé.
- Compilé (`build.cmd`), relu par un agent. Pas testé en jeu.
- Limites relevées à la relecture :
  - un jeu relancé en moins de 3 s garde `seen` ;
  - si `playing()` retient un processus sans fenêtre du dossier du jeu,
    l'alerte ne part jamais. Avant, ce cas donnait de fausses alertes.

### 2026-10-19 : gestionnaire des tâches, chiffres alignés sur Windows

Audit par deux agents (chiffres mesurés contre les compteurs Windows, et QML),
puis correctifs, relus par `relecteur`.

- **Ce qui était déjà juste** (mesuré) : mémoire = « Working Set - Private »
  pour les 259 processus, CPU brut, E/S, réseau total, GPU (max des moteurs).
- **CPU** (`src/tasks.rs`) : le coefficient turbo passe de « % Processor
  Performance » (moyenne qui compte les cœurs au repos) à
  Utility / Processor Time. Les lignes étaient 5 à 25 % sous l'en-tête ; la
  somme des lignes rejoint maintenant l'en-tête, à 0,6–1,6 % près, ce qui
  correspond aux interruptions et aux DPC.
- **Disque** : les compteurs d'E/S comptent aussi les tubes et le cache
  (exemple : zen.exe à 33 Mo/s pour un disque à 1 Mo/s). Ils sont ramenés au
  débit physique (`PhysicalDisk(_Total)\Disk Bytes/sec`). La somme est
  juste ; la répartition reste approximative (voir BACKLOG).
- **`MIN_GAP` 500 ms** entre deux relevés (clic sur un groupe, fin de tâche
  juste après le minuteur) : il remplace l'amorce de 300 ms et le `.max(0.2)`
  qui sous-évaluait les taux.
- **QML** (`TasksPage.qml`) : chevron à gauche de l'icône (il la recouvrait) ;
  tri sur les valeurs affichées (les lignes à « 0 % » ne s'échangent plus) ;
  second clic sur une colonne pour inverser le tri ; pas de réordonnancement
  pendant une confirmation ou avec le menu ouvert ; `tasks_stop` à la
  destruction de la page ; nettoyage d'`opened` ; message après 3 échecs ;
  mémoire toujours en Mo avec une décimale (« 1 523,5 Mo », espace
  insécable U+00A0 car Rubik n'a pas U+202F) ; plus de « 1000 k » ; cellule
  réseau par ligne non colorée ; colonnes mémoire et disque élargies.
- **Vérifié** : `cargo test` 6/6, clippy sans avertissement dans `tasks.rs`,
  `install.ps1` OK, journal QML vide au démarrage, `qmllint` sans nouvelle
  catégorie, `fmtMem` testé dans `qml.exe`. Sonde du relecteur (6 relevés
  sous charge) : CPU des lignes ≈ en-tête, disque = débit physique à
  ±0,02 Mo/s, aucune valeur aberrante.
- **Comparaison à l'écran** (captures simultanées des deux gestionnaires,
  îlot piloté par clics simulés) :
  - mémoire identique au dixième de Mo (Zen 1 172,6, Discord 445,8,
    Explorateur 178,6, Defender, ilot) ;
  - CPU total 12 % contre 11 %, Zen 4,5 % contre 4,0 % : l'îlot relève
    toutes les 2 s, Windows toutes les secondes ;
  - GPU total 36 % contre 36 %, disque 0 % contre 0 % ;
  - écarts de regroupement seulement : Everything et son service forment
    une seule ligne, RustDesk aussi, alors que Windows les sépare.
- **Trouvé à l'écran et corrigé** :
  - « 256 pro… » était coupé dans l'en-tête : le compte va maintenant à côté
    de « Programme » ;
  - Claude Code n'avait pas d'icône. Son updater renomme l'exe qui tourne
    (`claude.exe.old.<n>.<pid>`), et `QueryFullProcessImageNameW` renvoie ce
    nom sans `.exe`. On reprend alors le chemin NT d'origine, s'il finit par
    `.exe` et existe.
- **Rafraîchissement chaque seconde**, comme Windows (avant : 2 s). Coût
  mesuré sur 20 s, onglet ouvert : 12 % d'un cœur à 2 s, 19,7 % à 1 s
  (1,0 → 1,6 % du total, 12 cœurs). Rien quand l'onglet est fermé.
- **CPU : mauvais compteur, partout.** Retour de l'utilisateur : tout
  colle sauf le CPU. Une sonde horodatée (`% Processor Utility`, `Time`,
  `Performance`, `GetSystemTimes`, sysinfo) a été croisée avec des captures
  du Gestionnaire prises à la même heure. Résultat : le Gestionnaire (onglet
  Processus) suit **`% Processor Time`**, pas `Utility`, qui est ~12-25 %
  plus haut à cause du turbo (exemple : 18 % au Gestionnaire, Time 18-23,
  Utility 25-35). Corrigé :
  - `system.rs` (accueil, barre, îlot en jeu), `activity.rs` (bilan de
    session de jeu) et l'en-tête de `tasks.rs` lisent
    `\Processor Information(_Total)\% Processor Time` ;
  - lignes de `tasks.rs` : temps CPU brut / (durée × cœurs), sans le
    facteur turbo ;
  - premier relevé après l'amorce sur 1 s (`FIRST_GAP`) : sur 500 ms, il
    tombait sur le pic d'ouverture de l'îlot (jusqu'à 45 % affichés).
  - Vérifié : 12 paires de captures prises au même instant par un seul
    processus PowerShell (îlot 8-12 %, moyenne 9,7 ; Gestionnaire 8-13 %,
    moyenne 10,7), et accueil 15 % contre 16 %.
  - Piège de mesure : lancer un PowerShell par capture crée des pics de
    20-30 % de CPU qui faussent la comparaison. Il faut capturer depuis un
    seul processus qui tourne en boucle. Autre piège : quand le Gestionnaire
    (lancé en admin) a le focus, Windows bloque les clics simulés
    (`mouse_event`). Il faut d'abord activer une autre fenêtre
    (`WScript.Shell.AppActivate`).
- **Non vérifié** : tri inversé, menu clic droit et fin de tâche à l'écran.

### 2026-10-19 : survol et infobulles du panneau (après 0.4.12)

Retour d'usage : aucune infobulle (boutons de session, onglets…), y compris
après 0.4.12. Diagnostic par `console.log` temporaires et `ILOT_QT_LOG`. La
fenêtre d'infobulle s'affichait bien (test forcé au démarrage), mais les
boutons du panneau ne recevaient jamais le survol. **Cause** : `hoverZone`
(`Main.qml`), un `Item` en z 1000 qui couvre tout l'îlot, panneau ouvert
compris, portait un `HoverHandler`. Il prenait le survol à tous les boutons
du panneau : pas d'info-bulle, pas de surbrillance. Un bouton survolé avant
que la zone grandisse ne voyait jamais la souris partir, d'où les
infobulles bloquées.

- `Main.qml` : le survol de l'îlot est détecté par un `HoverHandler` sur
  `root` (ancêtre de tout, il ne bloque personne) et un test du point dans
  `hoverZone`. `hoverZone` ne garde que sa géométrie (`updateHit`).
- `TipWindow.qml` : placée à chaque `Ilot.tipChanged`, puis `raise()`.
- `Ilot.qml` (`setMode`) : `tip = null` à chaque changement d'état.
- **Vérifié par l'utilisateur** : survol et infobulles dans le panneau, la
  pilule grandit toujours au survol. Le simulateur de souris en PowerShell
  est bloqué par l'antivirus : ne pas réessayer (mémoire).

### 2026-10-18 : optimisations (pistes 7, 11, 13 à 16 de `perf-pistes.md`)

- **Visualiseur de l'onglet Média** : un seul `ShaderEffect`
  (`qt/shaders/vizbars.frag`) remplace les 48 `Rectangle`, qui refaisaient
  chacun leur `Gradient` en JS à chaque trame. Les 24 niveaux passent en 6
  `vector4d`. Le dégradé est interpolé en prémultiplié, comme avant. Les
  barres de l'accueil (24, couleur unie) ne changent pas. Les **3 bandes
  repliées ne sont pas faites** (voir `BACKLOG.md`). Le 15 trames/s replié
  existait déjà.
- **Verr. Maj** : quand le crochet clavier de `winkey` tourne, il réveille le
  relevé (`events::CAPS`) au relâchement de Verr. Maj et à l'appui sur Maj.
  Le relevé relit alors l'état à 20, 150 et 400 ms, avec un relevé de
  sécurité toutes les 2 s. Sans crochet, on garde le sondage à 120 ms. La
  luminosité, le registre, le presse-papiers et Steam étaient **déjà** passés
  en événements. Le tube Discord en vocal (60 ms) reste à faire
  (`BACKLOG.md`).
- **Pages déchargées** (`Panel.qml`) : après 5 min de panneau fermé, les
  pages autres qu'Accueil, Média, Applications, Presse-papiers et Assistant
  sont déchargées, sauf l'onglet en cours, puis `gc()` est appelé. Ajout
  d'`Api.unlisten`, utilisé par Réglages et Soundboard. Mail et Contrôles
  remettent `Ilot.overlay` à zéro quand ils sont détruits.
- **Images** : `IlotImages::requestImage` décode avec
  `QImageReader::setScaledSize`. La qualité JPEG reste par défaut, sans la
  réduction DCT rapide, qui demande une qualité inférieure à 50.
- **Couleur du thème** : la commande `theme_source` (`src/theme.rs`,
  crate `material-colors` 0.4.2, car la 0.5 demande rustc 1.97) remplace
  `Backend::imagePixels`, le `WorkerScript` et `quant.mjs` (supprimé).
  L'algorithme est le même : QuantizerCelebi à 128 couleurs puis Score, sur
  l'image réduite à 128 px (fond) ou 64 px (pochette).
- **`opt-level = 3`** : la DLL passe de 9,0 à 12,2 Mo.
- **Propriétés QML typées : non fait.** Le singleton `Ilot` porte le nom du
  module, donc les outils ne voient pas ses membres (`BACKLOG.md`).
- **Vérifié** : `cargo test` 6/6, clippy sans nouvel avertissement (56,
  comme avant), Rust, C++, QML et shader compilés. Relu par un agent
  généraliste, ses remarques sont appliquées : dégradé prémultiplié, bord
  du shader en `fwidth`, Maj et relevés multiples pour Verr. Maj, overlay de
  Mail et de Contrôles. Compilé, lancé sur l'onglet Média sans erreur
  QML ni shader au journal, installé et publié en 0.4.12. **À
  regarder à l'usage** : le rendu du visualiseur de l'onglet Média, la
  couleur du thème après un changement de fond (elle doit être identique),
  et Verr. Maj.

### 2026-10-18 : infobulles

- Ajout de `tip:` sur les boutons-icônes qui n'en avaient pas : flèches du
  calendrier, retour et fermeture des panneaux, contrôles média (îlot et
  pastille), minuteur (Pause, Reprendre ou Démarrer), volume de l'accueil,
  chevron des tuiles de contrôle, connexion Wi-Fi. Les pastilles de couleur
  des réglages n'en ont pas.
- Barre : le survol d'une icône de la zone de notification n'envoie plus
  `WM_MOUSEMOVE` à l'appli (`Tray.click(..., "hover")`). Certaines applis
  ouvraient leur propre infobulle, qui ne se fermait jamais. Notre infobulle
  affiche déjà `modelData.tip`. La branche `"hover"` de `Tray::click` n'est
  plus appelée.
- **Vérifié** : qmllint ne signale rien de nouveau, relu par un agent
  généraliste (`relecteur` indisponible), sa remarque sur le minuteur est
  appliquée. Compilé et publié avec la 0.4.12.

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
