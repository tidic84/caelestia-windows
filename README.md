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
| **Îlot replié** | Heure ; pochette qui tourne et égaliseur quand de la musique joue |
| **Survol** | Titre, artiste, progression, lecture/pause |
| **Accueil** | Horloge, calendrier, lecteur, CPU / RAM / disque / batterie, volume, verrouiller · veille · déconnexion · redémarrer · éteindre (second clic pour confirmer) |
| **Média** | Lecteur complet avec avance dans le morceau. Fonctionne avec tout ce que Windows voit (Spotify, navigateurs…) |
| **Apps** | Toutes les applis du menu Démarrer (classiques et Store) avec icônes, recherche, navigation clavier. **Ctrl+Alt+Espace** l'ouvre directement |
| **Presse-papiers** | Les 40 derniers textes copiés, un clic pour recopier |
| **Fonds** | Vos images de `Images\Wallpapers` + celles de Windows ; choisir un fond recalcule la palette |

Autres comportements :
- hors de l'îlot, les clics passent aux fenêtres en dessous ;
- l'îlot se cache quand un jeu ou une vidéo est en plein écran ;
- une icône dans la zone de notification permet de recharger ou de quitter.

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

Onglets : `home`, `media`, `apps`, `clips`, `walls` ; `?peek=1` montre l'état survolé.

## Comment ça marche

- **Tauri 2** : une fenêtre transparente, toujours au premier plan, de taille fixe.
  Un thread Rust suit le curseur et ne rend la fenêtre cliquable que lorsqu'il
  est au-dessus de la zone de l'îlot (signalée par l'interface).
- **Média** : `GlobalSystemMediaTransportControls` (WinRT).
- **Volume** : Core Audio (`IAudioEndpointVolume`).
- **Apps** : dossier virtuel `shell:AppsFolder`, icônes via `IShellItemImageFactory`.
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
