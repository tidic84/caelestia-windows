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

| Onglet | Contenu |
|---|---|
| **Îlot replié** | Heure ; pochette qui tourne et égaliseur qui suit vraiment le son ; icônes caféine, ne pas déranger et minuteur en cours |
| **Survol** | Titre, artiste, progression, lecture/pause ; sinon date et météo |
| **Accueil** | Profil (avatar Windows, durée d'allumage), météo, horloge, calendrier avec vos agendas iCal (clic sur un jour : ses événements), lecteur avec visualiseur, CPU / RAM / disque / batterie, volume, verrouiller · veille · déconnexion · redémarrer · éteindre (second clic pour confirmer) |
| **Média** | Lecteur complet avec avance dans le morceau et visualiseur audio. Fonctionne avec tout ce que Windows voit (Spotify, navigateurs…) |
| **Contrôles** | Wi-Fi (réseaux, connexion avec mot de passe), Bluetooth, caféine (empêche la veille), ne pas déranger, mode sombre, minuteur / Pomodoro, luminosité, sortie audio, volume par application, centre de notifications |
| **Apps** | Toutes les applis du menu Démarrer avec icônes, recherche, navigation clavier. Préfixes : `>` commandes (fond au hasard, variantes de couleurs, minuteur, Wi-Fi, session…), `=` calculatrice, `:` emoji, `?` recherche web. Un calcul tapé directement s'affiche aussi. **Ctrl+Alt+Espace** ouvre le lanceur. **Dossiers** (clic droit sur une appli, ou glisser une appli sur un dossier), fichiers et raccourcis déposés depuis l'Explorateur, applis masquées (clic droit sur « Toutes » pour les réafficher), tri par nom ou date d'ajout. **Launcher** de jeux : Steam, Epic Games, Ubisoft Connect et GOG avec jaquettes, plus les jeux ajoutés à la main |
| **Mail** | Comptes IMAP (Gmail, Yahoo, iCloud, Orange…) avec mot de passe d'application chiffré (DPAPI), boîte de réception de chaque compte, lecture du message ; nombre de non-lus sur l'onglet et dans la pilule |
| **PC** | Discord : micro, sourdine, volume de chaque personne du salon et de son propre micro (RPC, avec une application Discord à soi ; sinon mélangeur Windows). Logiciels du PC (MSI Center, Armoury Crate, G HUB) et mode d'alimentation de Windows 11 |
| **Tâches** | Gestionnaire des tâches : programmes regroupés avec CPU, mémoire, disque et connexions réseau (colonnes colorées selon la charge), tri, filtre, fin de tâche (processus Windows protégés) |
| **Presse-papiers** | Les 40 derniers textes et images copiés, un clic pour recopier ; bloc-notes enregistré automatiquement |
| **Fonds** | Vos images de `Images\Wallpapers` + celles de Windows ; choisir un fond recalcule la palette. Avec **Wallpaper Engine**, un second onglet liste vos fonds WE. Bouton « Au hasard » |
| **Réglages** (⚙) | Démarrage avec Windows, écran de l'îlot, mode clair / sombre / auto, variante Material You (Tonal Spot, Vibrant, Expressive…), accent et mode appliqués à Windows, ville de la météo, agendas iCal, rotation automatique des fonds, notifications et indicateurs |

La pilule s'agrandit aussi un instant pour signaler :
- un changement de volume ou de luminosité (OSD) ;
- une notification Windows ;
- un appareil Bluetooth connecté ou déconnecté ;
- une image copiée (capture d'écran) ;
- le chargeur branché ou débranché ;
- Verr. Maj ;
- la fin du minuteur.

Autres comportements :
- en haut à droite du panneau : **agrandir** (presque tout l'écran) et **verrouiller** (l'îlot reste ouvert quand la souris sort) ;
- calendrier : une **note** par jour (clic sur un jour) ;
- Média : **playlists** favorites (liens Spotify, Deezer, YouTube) ;
- Réglages › Apparence : **fond de l'îlot** opaque, translucide ou fond d'écran flouté ;
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
- **Tâches** : `sysinfo` pour CPU / mémoire / disque ; connexions TCP par processus via `GetExtendedTcpTable` (le débit réseau par processus demanderait ETW et des droits administrateur).
- **Dossiers, notes, playlists** : petits fichiers JSON dans `%LOCALAPPDATA%\Ilot`.
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

Pas encore de version publiée : il faut compiler (voir plus bas), puis lancer
`target\release\ilot.exe`.

## Compiler

Prérequis : Windows 10/11 avec WebView2 (déjà présent sur Windows 11), et
[Rust](https://rustup.rs). Pas de Node ni de npm : l'interface est du HTML/CSS/JS
statique dans `ui/`.

```powershell
cargo build --release
```

Le projet compile avec Rust 1.89 : `.cargo/config.toml` demande à Cargo de
choisir des versions de dépendances compatibles avec la toolchain installée.

Pour travailler l'interface sans lancer l'application, servez le dossier `ui/` et
ouvrez `preview.html`, qui simule le backend avec des données factices :

```powershell
cd ui; python -m http.server 8765   # puis http://localhost:8765/preview.html?tab=home
```

Onglets : `home`, `media`, `ctrl`, `apps`, `clips`, `walls`, `settings`. Autres paramètres :
`peek=1` (état survolé), `act=osd|notif|bt|shot|caps` (activité), `q=>v` (texte du lanceur),
`sheet=wifi|out|timer`, `day=1` (événements du jour), `light=1` (mode clair).

`ilot.exe --check-all rapport.txt` écrit un diagnostic des modules système (audio, réseau,
notifications, visualiseur, HTTP) sans lancer l'interface.

## Comment ça marche

- **Tauri 2** : une fenêtre transparente, toujours au premier plan, de taille fixe.
  Un thread Rust suit le curseur et ne rend la fenêtre cliquable que lorsqu'il
  est au-dessus de la zone de l'îlot (signalée par l'interface).
- **Média** : `GlobalSystemMediaTransportControls` (WinRT).
- **Volume** : Core Audio (`IAudioEndpointVolume`).
- **Apps** : dossier virtuel `shell:AppsFolder`, icônes via `IShellItemImageFactory`.
- **Wallpaper Engine** : lecture de `config.json` et des `project.json`, application via sa ligne de commande.
- **Fonds** : `IDesktopWallpaper`, miniatures mises en cache dans `%LOCALAPPDATA%\Ilot\thumbs`.
- **Couleurs** : [material-color-utilities](https://github.com/material-foundation/material-color-utilities),
  schéma *Tonal Spot* sombre ; les couleurs CSS sont des propriétés enregistrées
  (`@property`), donc la palette s'anime lors d'un changement.

## Composants tiers

Inclus dans `ui/vendor/` :
- material-color-utilities — Apache 2.0, © Google
- Material Symbols Rounded (sous-ensemble) — Apache 2.0, © Google
- Rubik — SIL Open Font License 1.1

## Licence

MIT — voir [LICENSE](LICENSE).
