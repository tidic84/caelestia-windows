# Prototype Qt Quick / QML de l'îlot

Ce prototype sert à **mesurer** ce que coûterait l'îlot réécrit en Qt 6 / QML,
face à la version Tauri + WebView2. Ce n'est pas un remplaçant : il ne
reprend qu'une partie de l'interface.

## Ce qu'il reprend

- Fenêtre transparente, sans bordure, toujours au-dessus, en haut de l'écran
  principal. Seule la zone de l'îlot reçoit la souris : un masque de fenêtre
  remplace le suivi du curseur toutes les 25 ms (`track_cursor`).
- Masquage quand une appli passe en plein écran (même règle que
  `fullscreen_foreground`).
- La pilule repliée (heure, pochette qui tourne, égaliseur), son survol
  (titre, artiste, progression) et ses coins concaves.
- Le panneau déplié :
  - onglet **Accueil** : horloge, calendrier, jauges CPU / RAM / C:, lecteur
    avec disque qui tourne et visualiseur ;
  - onglet **Média** : pochette floutée en fond (`MultiEffect`), grande
    pochette, progression, visualiseur.
- Les backends :
  - lecteur GSMTC en C++/WinRT, piloté par événements comme `media.rs` ;
  - CPU, RAM et disque relevés toutes les 2 s ;
  - visualiseur en capture WASAPI loopback (FFT, 24 bandes, ~30 trames/s), le
    même calcul que `audio.rs`.

Le reste n'y est pas : lanceur, barre, notifications, presse-papiers, fonds,
Material You, réglages, mail, etc.

## Compiler

Il faut Qt 6.5 ou plus (testé avec 6.9.3 `msvc2022_64`, installé avec
`aqtinstall`) et Visual Studio Build Tools 2022, qui fournit MSVC, CMake et
Ninja.

```bat
set QTDIR=C:\Qt\6.9.3\msvc2022_64
qt\build.cmd
```

Le script lance `windeployqt`, si bien que `qt\build` contient un exécutable
autonome avec ses DLL Qt.

## Options

| Option / variable | Effet |
|---|---|
| `--open` | ouvre le panneau au démarrage |
| `--sim-viz` | visualiseur alimenté par des bandes aléatoires à 30 i/s au lieu du son (mesures sans musique) |
| `ILOT_QT_LOG=<fichier>` | messages Qt / QML dans un fichier (l'appli n'a pas de console) |
| `ILOT_QT_SHOT=<fichier.png>` | capture de la fenêtre après 4 s (une capture d'écran GDI ne voit pas cette fenêtre à jour) |

## Mesures

Les résultats comparés aux deux versions Tauri sont dans
`docs/perf-ilot.md`, sur la branche `perf-ilot`.
