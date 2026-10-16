# Caelestia for Windows

**Un îlot façon [caelestia-dots](https://github.com/caelestia-dots/shell), mais pour Windows.**

Une pilule discrète en haut de l'écran, collée au bord comme les tiroirs de
Caelestia. Survolez-la pour voir le morceau en cours, cliquez ou faites défiler
pour ouvrir le panneau. Les couleurs suivent votre fond d'écran (Material You).

> Projet indépendant, non affilié à Caelestia. Aucun code de Caelestia n'est
> repris : seul le style s'en inspire.

<p align="center">
  <img src="docs/accueil.png" alt="Onglet Accueil" width="49%">
  <img src="docs/media.png" alt="Onglet Média" width="49%">
  <img src="docs/fonds.png" alt="Onglet Fonds d'écran" width="49%">
  <img src="docs/apps.png" alt="Onglet Apps" width="49%">
</p>

## Fonctionnalités

Le panneau garde les onglets **essentiels** : Accueil, Média, Contrôles, Apps
et Réglages. Les autres sont des **addons** à activer dans Réglages › Addons
(Mail, PC, Soundboard, Tâches, Presse-papiers, Assistant, Fonds) : un addon
désactivé n'a ni onglet ni travail en arrière-plan (relevé des mails, état des
services, moteur de la soundboard).

| Onglet | Contenu |
|---|---|
| **Barre** | Façon Waybar, l'îlot au centre : lanceur, bureaux virtuels (clic ou molette), fenêtres ouvertes, regroupées par appli (clic : activer / réduire ou fenêtre suivante, clic molette : fermer ; au survol, aperçu de chaque fenêtre pour choisir ou fermer), applications en arrière-plan (zone de notification, dépliée par la flèche ; clic, clic droit et double clic transmis à l'appli), CPU / RAM, Wi-Fi, Bluetooth, volume (molette), batterie, notifications, date. Le haut de l'écran est réservé (les fenêtres maximisées s'arrêtent dessous) et la barre des tâches Windows peut être masquée, sur tous les écrans. Les autres écrans ont aussi leur barre, avec l'heure au centre ; ses boutons ouvrent l'îlot sur son écran. Options : îlots séparés (sans fond, chaque groupe flotte seul), fenêtres ouvertes affichées ou non, masquage automatique (la barre apparaît quand la souris touche le haut de l'écran) |
| **Îlot replié** | Heure (classique, à volets, à aiguilles, néon, pixel) ; pochette qui tourne et égaliseur qui suit vraiment le son ; icônes caféine, ne pas déranger et minuteur en cours ; **compagnon** (blob, chat ou fantôme) qui danse sur la musique, met un casque en jeu, transpire si le GPU chauffe, dort la nuit et part se promener au-dessus de la barre des tâches quand vous ne faites rien ; activité en cours (mise à jour Steam, jeu, température du GPU) ; micro Discord en vocal ; minuteur d'extinction ; voyant caméra (vert) / micro (orange). Molette : volume (Maj + molette : appli au premier plan), clic molette : lecture / pause |
| **Survol** | Titre, artiste, progression, lecture/pause ; sinon l'activité en cours, ou la date et la météo ; boutons micro et sourdine Discord |
| **Accueil** | Profil (avatar Windows, durée d'allumage), météo, horloge, calendrier avec vos agendas iCal (clic sur un jour : ses événements), lecteur avec visualiseur (barres en cercle autour du disque), CPU / RAM / batterie et tous les disques, volume (jusqu'à 200 % avec [Equalizer APO](https://sourceforge.net/projects/equalizerapo/)), verrouiller · veille · déconnexion · redémarrer · éteindre (second clic pour confirmer) |
| **Média** | Lecteur complet avec avance dans le morceau, visualiseur audio, **paroles synchronisées** ([LRCLIB](https://lrclib.net), puis NetEase ; clic sur une ligne pour y aller), volume de l'appli qui joue, pochette inclinable en 3D. Fonctionne avec tout ce que Windows voit (Spotify, navigateurs…) |
| **Contrôles** | Wi-Fi (réseaux, connexion avec mot de passe), Bluetooth, caféine (empêche la veille), ne pas déranger, mode sombre, minuteur / Pomodoro, luminosité, sortie audio, volume par application avec profils « Jeu » et « Chill », centre de notifications |
| **Apps** | Toutes les applis du menu Démarrer avec icônes, recherche, navigation clavier. Préfixes : `>` commandes (fond au hasard, variantes de couleurs, minuteur, Wi-Fi, session…), `=` calculatrice, `:` emoji, `?` recherche web. Un calcul tapé directement s'affiche aussi. **Ctrl+Alt+Espace** ouvre le lanceur, ainsi que la touche Windows seule si le réglage est activé (la touche est alors remappée au niveau du pilote clavier pour que Windows n'ouvre plus le menu Démarrer : droits administrateur et redémarrage requis ; les raccourcis Win+… restent ceux de Windows, Ctrl+Échap ouvre le menu Démarrer). **Dossiers** (clic droit sur une appli, ou glisser une appli sur un dossier), fichiers et raccourcis déposés depuis l'Explorateur, applis masquées (clic droit sur « Toutes » pour les réafficher), tri par nom ou date d'ajout. **Launcher** de jeux : Steam, Epic Games, Ubisoft Connect et GOG avec jaquettes, plus les jeux ajoutés à la main |
| **Mail** (addon) | Comptes IMAP (Gmail, Yahoo, iCloud, Orange…) avec mot de passe d'application chiffré (DPAPI), boîte de réception de chaque compte, lecture du message ; nombre de non-lus sur l'onglet et dans la pilule |
| **PC** (addon) | Discord : micro, sourdine, volume de chaque personne du salon et de son propre micro (RPC, avec une application Discord à soi ; sinon mélangeur Windows). **État des services** (Discord, Steam, EA, Spotify, Epic, Roblox, Claude : page officielle + temps de réponse depuis le PC), **santé du PC** (place et état des disques, pilote NVIDIA à jour, nettoyage des temporaires, caches de shaders, miniatures et corbeille), **extinction programmée** (dans 30 min, 1 h, 2 h, à une heure, à la fin du média ou des mises à jour Steam), logiciels du PC (MSI Center, Armoury Crate, G HUB), mode d'alimentation de Windows 11, convertisseur de sensibilité entre jeux |
| **Soundboard** (addon) | Sons joués dans le vocal Discord par un micro virtuel (VB-CABLE, Steam Streaming Microphone, Voicemod…) avec votre vrai micro ; mp3, wav, ogg, flac, m4a (bouton Ajouter ou glisser-déposer) ; volume et couleur par son, un son à la fois ou superposés |
| **Tâches** (addon) | Gestionnaire des tâches : programmes regroupés avec CPU (en « utilité », comme Windows), mémoire privée, disque, GPU et connexions réseau (colonnes colorées selon la charge), sections Applications / arrière-plan / Windows, tri, filtre, fin de tâche (processus Windows protégés) |
| **Presse-papiers** (addon) | Les 40 derniers textes et images copiés, un clic pour recopier ; bloc-notes enregistré automatiquement |
| **Assistant** (addon) | **Traduction** (17 langues, détection automatique), **sous-titres en direct** de tout le son du PC traduits en français (Live Captions de Windows, bandeau en bas de l'écran), questions envoyées à l'application **Claude** (discussion ou Cowork, raccourcis Résumer / Expliquer / Corriger… avec le dernier texte copié) |
| **Fonds** (addon) | Vos images de `Images\Wallpapers` + celles de Windows ; choisir un fond recalcule la palette. Avec **Wallpaper Engine**, un second onglet liste vos fonds WE. Bouton « Au hasard » |
| **Réglages** (⚙) | En onglets. **Général** : démarrage avec Windows, touche Windows, écran de l'îlot, notifications et indicateurs, sauvegarde / restauration des réglages. **Barre**. **Apparence** : thèmes prêts, couleur (fond d'écran, pochette en cours ou couleur choisie), clair / sombre / auto / selon l'heure / lever et coucher du soleil, variante Material You (Tonal Spot, Vibrant, Expressive…), accent et mode appliqués à Windows, fond de l'îlot (opaque, noir, translucide, acrylique, aurore boréale), contour, forme, animations, rotation automatique des fonds. **Pilule** : taille, horloge, compagnon, activités, Discord, voyant, météo animée. **Jeu et absence**. **Accessibilité** : taille du texte, contraste, mouvements, couleurs pour daltoniens. **Météo et agenda** : ville, agendas iCal. **Raccourcis** clavier globaux pour chaque onglet et action. **Addons**. **Mises à jour** : version, recherche, téléchargement, installation, mode automatique et notes de version |

La pilule s'agrandit aussi un instant pour signaler :
- un changement de volume ou de luminosité (OSD) ;
- une notification Windows, un nouveau mail ;
- une mise à jour Steam terminée (bouton Jouer), une **partie trouvée** pendant que vous attendez hors du jeu (carillon, îlot qui clignote, clic pour y retourner), le bilan de la session de jeu ;
- une appli qui allume la caméra, un service en panne ou de retour, un disque presque plein, une demande **Quick Share** (Accepter / Refuser directement dans la pilule, avec le code de vérification), un fichier reçu, l'extinction programmée dans une minute ;
- un appareil Bluetooth connecté ou déconnecté ;
- une image copiée (capture d'écran) ;
- le chargeur branché ou débranché ;
- Verr. Maj ;
- la fin du minuteur.

Autres comportements :
- en haut à droite du panneau : **agrandir** (presque tout l'écran), **verrouiller** (l'îlot reste ouvert quand la souris sort) et **quitter l'îlot** (second clic pour confirmer ; aussi la commande `>quitter` du lanceur) ; en haut à gauche : **Quick Share** (voir plus bas) ;
- fichiers déposés sur l'onglet Apps : conversion PNG ↔ JPG, réduction à 1920 px, compression .zip, copie pour Discord, envoi avec Quick Share, ou rangement dans un dossier ; la Corbeille, Ce PC… s'ajoutent comme emplacements ;
- **Quick Share** (le partage de Google des téléphones Android) : glisser des fichiers sur l'îlot allume le bouton Quick Share en haut à gauche ; les garder 200 ms dessus (ou les y lâcher) ouvre Quick Share. Appareils à proximité (clic, ou fichiers lâchés directement sur l'appareil), texte ou lien à envoyer, progression et annulation, **QR code** à scanner avec l'appareil photo du téléphone (envoi sans confirmation), réception avec code de vérification (fichiers dans Téléchargements, texte dans le presse-papiers, liens, mots de passe Wi-Fi), nom du PC et visibilité (visible, 10 minutes, masqué) ;
- **mode jeu** (jeu du Launcher lancé) : mode Performances, notifications en silence, profil de volume « Jeu », rétablis à la fermeture ;
- **mode absent** (10 min sans clavier ni souris) : la musique se met en pause et les notifications attendent votre retour (récapitulatif) ;
- calendrier : une **note** par jour (clic sur un jour) ;
- Média : **playlists** favorites (liens Spotify, Deezer, YouTube) ;
- Réglages › Apparence : **fond de l'îlot** (et de la barre) opaque, translucide ou fond d'écran flouté ;
- hors de l'îlot, les clics passent aux fenêtres en dessous ;
- l'îlot se cache quand un jeu ou une vidéo est en plein écran ;
- une icône dans la zone de notification permet d'ouvrir les réglages, de recharger ou de quitter.

### Notes techniques

- **Notifications** : l'API officielle exige une appli empaquetée (MSIX). L'îlot lit donc, en lecture seule, la base du centre de notifications (`%LOCALAPPDATA%\Microsoft\Windows\Notifications\wpndatabase.db`). Les notifications Windows doivent être activées. « Effacer » ne les masque que dans l'îlot.
- **Sortie audio** : changée via `IPolicyConfig`, l'interface (non documentée) qu'utilise le panneau Son de Windows.
- **Luminosité** : WMI pour l'écran d'un portable, DDC/CI pour un écran externe (s'il le permet).
- **Visualiseur** : capture « loopback » WASAPI de la sortie par défaut + FFT, uniquement quand de la musique joue.
- **Agenda** : adresse iCal secrète (Google Agenda : Paramètres › Intégrer l'agenda ; Outlook : Publier un calendrier). Les événements récurrents sont gérés.
- **Météo** : [Open-Meteo](https://open-meteo.com), sans clé.
- **Mail** : IMAP en TLS ; les mots de passe sont chiffrés avec DPAPI (déchiffrables seulement par la session Windows) dans `%LOCALAPPDATA%\Ilot\mail.json`.
- **Discord** : RPC local (`\\.\pipe\discord-ipc-0`), avec une application créée sur le portail développeurs Discord (redirection `http://localhost`) ; jetons chiffrés avec DPAPI.
- **Tâches** : compteurs de performance de Windows (PDH : `% Processor Utility`, `GPU Engine`, `PhysicalDisk`) comme le Gestionnaire des tâches, `sysinfo` pour la liste des processus, mémoire privée par `GetProcessMemoryInfo` ; connexions TCP par processus via `GetExtendedTcpTable` (le débit réseau par processus demanderait ETW et des droits administrateur).
- **Activités** : journal de Steam (`logs\content_log.txt`) et manifestes `appmanifest_*.acf` pour les mises à jour ; `nvidia-smi` pour la charge et la température du GPU ; partie trouvée : fenêtre du jeu qui clignote (crochet Shell) ou lecture disque soutenue (chargement de la carte).
- **Voyant caméra / micro** : registre `CapabilityAccessManager\ConsentStore`, comme l'icône de la barre des tâches.
- **Soundboard** : sons décodés par [symphonia](https://github.com/pdeljanov/Symphonia) en 48 kHz stéréo ; le moteur WASAPI mélange le vrai micro et les sons dans la sortie du câble virtuel, et les rejoue dans votre casque.
- **Sous-titres en direct** : Live Captions de Windows 11 (`LiveCaptions.exe`), lu par UI Automation (sa fenêtre est rendue invisible), traduit par le service de traduction de Google.
- **Volume au-delà de 100 %** : préampli d'Equalizer APO (`config.txt` géré par l'îlot, l'ancien est gardé dans `config.ilot-backup.txt`).
- **Raccourcis clavier** : `RegisterHotKey` ; les actions de lecture ne prennent pas le clavier du jeu en cours.
- **Dossiers, notes, playlists** : petits fichiers JSON dans `%LOCALAPPDATA%\Ilot`.
- **Quick Share** : protocole de Google (non documenté) réimplémenté en Rust d'après [NearDrop](https://github.com/grishka/NearDrop) (domaine public) et les définitions protobuf de [google/nearby](https://github.com/google/nearby) (Apache 2.0) : annonce et recherche mDNS (`_FC9F5ED42C8A._tcp`), échange de clés UKEY2 (P-256), messages chiffrés AES-256-CBC + HMAC-SHA256. Wi-Fi local uniquement (le PC et le téléphone sur le même réseau) : pas de Bluetooth classique ni de Wi-Fi Direct. Une annonce Bluetooth LE (service `0xFE2C`) réveille les téléphones Android pour qu'ils apparaissent ; sans Bluetooth, ouvrir Quick Share sur le téléphone ou scanner le QR code. Windows demande d'autoriser l'îlot dans le pare-feu au premier lancement (réseaux privés).
- **Accent Windows** : écrit dans le registre (`AccentPalette`, `AccentColor`…) et désactive la couleur automatique de Windows.

## Wallpaper Engine

Si [Wallpaper Engine](https://store.steampowered.com/app/431960/) est installé,
il est détecté automatiquement (toutes les bibliothèques Steam sont parcourues) :

- l'onglet **Fonds** propose « Windows / Wallpaper Engine » et liste vos fonds
  du Workshop, vos projets et ceux fournis avec WE, avec leur aperçu ;
- un clic applique le fond via la commande officielle
  `wallpaper32.exe -control openWallpaper` (écran 0) ;
- quand WE tourne, la palette suit le fond WE affiché, et non le fond Windows
  qu'il recouvre. Si vous changez de fond dans WE, l'îlot se recolore tout seul.

## Installation

Téléchargez `ilot-<version>-win64.zip` dans les
[versions publiées](https://github.com/tidic84/caelestia-windows/releases),
décompressez-le dans `%LOCALAPPDATA%\Programs\Ilot` (ou ailleurs, tant que le
dossier vous appartient) et lancez `ilot.exe`. Sinon, `install.ps1` compile
(voir plus bas), copie l'îlot dans `%LOCALAPPDATA%\Programs\Ilot` et l'ajoute
au démarrage.

## Mises à jour et notes de version

L'îlot cherche une nouvelle version au démarrage puis toutes les 6 h
(API Releases de GitHub). Dans Réglages › Mises à jour :

- **Télécharger et installer** : l'archive est téléchargée en arrière-plan,
  puis installée après 10 min sans clavier ni souris (hors jeu) ou au
  lancement suivant ;
- **Prévenir seulement** (par défaut) : la pilule annonce la version, un clic
  ouvre ses notes ; boutons Télécharger puis Installer et redémarrer ;
- **Ne pas vérifier** : seulement avec le bouton Rechercher.

L'installation est faite par un petit script PowerShell : il attend la fin de
l'îlot, vérifie la somme SHA-256 de l'archive (donnée par GitHub), copie les
fichiers par-dessus l'installation et relance l'îlot. Les fichiers de travail
sont dans `%LOCALAPPDATA%\Ilot\update` (compte rendu dans `update.log`).

Les notes de version viennent de [`CHANGELOG.md`](CHANGELOG.md), embarqué dans
l'îlot ; après une mise à jour, la pilule propose de les lire.

**Publier une version** : mettre à jour `version` dans `Cargo.toml`, ajouter sa
section `## <version> — <date>` en haut de `CHANGELOG.md`, puis pousser le tag
`v<version>`. Le workflow `.github/workflows/release.yml` compile l'îlot, crée
`ilot-<version>-win64.zip` et la version GitHub avec ces notes.

## Compiler

Prérequis :
- [Rust](https://rustup.rs) (1.89 ou plus) ;
- Visual Studio Build Tools 2022 (MSVC, CMake, Ninja) ;
- Qt 6.9 pour MSVC 2022, avec le module Qt Shader Tools (par exemple avec
  `aqtinstall` : `aqt install-qt windows desktop 6.9.3 win64_msvc2022_64 -m qtshadertools`).

```bat
set QTDIR=C:\Qt\6.9.3\msvc2022_64
qt\build.cmd
```

Le script compile le cœur Rust (`cargo build --release`), puis l'interface
(CMake), et copie les DLL de Qt : `qt\build\ilot.exe` se lance tel quel.

`.cargo/config.toml` demande à Cargo de choisir des versions de dépendances
compatibles avec la toolchain installée.

Options utiles pour travailler l'interface :
- `ilot.exe --open <onglet>` ouvre le panneau au démarrage (`home`, `media`,
  `ctrl`, `apps`, `settings`, et pour les addons activés `mail`, `pc`,
  `sounds`, `tasks`, `clips`, `assist`, `walls`) ;
- `ILOT_QT_LOG=<fichier>` écrit les messages de Qt et du QML dans un fichier ;
- `ILOT_QT_SHOT=<fichier.png>` capture la fenêtre de l'îlot après
  `ILOT_QT_SHOT_DELAY` ms (4000 par défaut), puis quitte si `ILOT_QT_SHOT_QUIT` est défini.

`ilot.exe --check-update rapport.txt` écrit la dernière version publiée et les
notes de version embarquées.

`ilot.exe --check-all rapport.txt` écrit un diagnostic des modules système (audio, réseau,
notifications, visualiseur, HTTP) sans lancer l'interface.

## Comment ça marche

- **Deux parties** : le cœur en Rust (`src/`, compilé en `ilot_core.dll`) parle
  à Windows ; l'interface est en Qt Quick / QML (`qt/`). L'interface appelle les
  commandes du cœur (`ilot_invoke`, sur un thread à part) et reçoit ses
  événements ; les images (icônes, pochettes, fonds) passent par
  `image://ilot/…` sans copie en base64.
- **Fenêtre** : transparente, toujours au premier plan. Un masque de fenêtre
  limite la souris aux zones de l'îlot et de la barre : ailleurs, les clics
  passent aux fenêtres dessous.
- **Média** : `GlobalSystemMediaTransportControls` (WinRT), suivi par événements.
- **Barre** : zone réservée via `SHAppBarMessage` (AppBar) ; bureaux virtuels lus dans le registre (`VirtualDesktopIDs`), changés par Ctrl+Win+←/→ faute d'API publique. Sur les autres écrans, une fenêtre par écran (`qt/qml/Bar.qml`) partage l'état et le thème de l'îlot. La barre des tâches Windows (principale et secondaires) est passée en masquage automatique puis cachée, et tout est rétabli en quittant l'îlot (si l'îlot plante, redémarrer l'Explorateur la fait revenir).
- **Volume** : Core Audio (`IAudioEndpointVolume`).
- **Apps** : dossier virtuel `shell:AppsFolder`, icônes via `IShellItemImageFactory`.
- **Wallpaper Engine** : lecture de `config.json` et des `project.json`, application via sa ligne de commande.
- **Fonds** : `IDesktopWallpaper`, miniatures mises en cache dans `%LOCALAPPDATA%\Ilot\thumbs`.
- **Couleurs** : [material-color-utilities](https://github.com/material-foundation/material-color-utilities),
  schéma *Tonal Spot* sombre par défaut, calculé à partir du fond d'écran ; la
  palette s'anime lors d'un changement.

## Composants tiers

- Qt 6 (Qt Quick, Qt Quick Shapes, Qt Quick Effects) — LGPL v3, © The Qt Company
- material-color-utilities (`qt/qml/mcu.mjs`) — Apache 2.0, © Google
- Material Symbols Rounded (sous-ensemble, `qt/fonts`) — Apache 2.0, © Google
- Rubik (`qt/fonts`) — SIL Open Font License 1.1

## Licence

MIT — voir [LICENSE](LICENSE).
