# Interface Qt Quick / QML de l'îlot

L'îlot complet : pilule (repliée, survol, activités), panneau et ses dix
onglets, barre façon Waybar sur l'écran de l'îlot et sur les autres écrans,
info-bulles, icône de la zone de notification, Ctrl+Alt+Espace. Tout ce qui
parle à Windows reste dans le cœur Rust (`../src`, `ilot_core.dll`).

## Organisation

- `src/` (C++)
  - `core.h` : fonctions du cœur Rust (`ilot_invoke`, `ilot_start`...) ;
  - `backend.*` : commandes sur un thread à part, événements, images
    `image://ilot/...`, pixels pour la couleur du thème ;
  - `winctl.*` (type QML `WinCtl`) : zones cliquables (masque de la fenêtre),
    bande du haut de l'écran, plein écran, clavier ;
  - `shell.*` : fenêtres (îlot, barres des autres écrans), placement,
    réservation du haut de l'écran, zone de notification, raccourci.
- `qml/`
  - singletons : `Theme` (palette Material You, polices, courbes), `Api`
    (`invoke` et `listen`, comme Tauri), `Ilot` (état et logique communs,
    ce que faisait `app.js`) ;
  - fenêtres : `Main` (îlot), `Bar` (autres écrans), `TipWindow` ;
  - îlot : `Island`, `Pill`, `Panel` et une page par onglet (`HomePage`,
    `MediaPage`, `CtrlPage`, `AppsPage`, `MailPage`, `PcPage`, `TasksPage`,
    `ClipsPage`, `WallsPage`, `SettingsPage`) ;
  - modules JavaScript repris de l'interface web : `mcu.mjs`
    (material-color-utilities), `calc.mjs`, `emoji.mjs`, `ical.mjs`.
- `shaders/round.frag` : images aux coins arrondis, sans calque.
- `fonts/` : Rubik (graisses 300 à 700) et Material Symbols Rounded, les
  mêmes polices que l'interface web, converties de WOFF2 en TTF (fontTools :
  instances statiques des polices variables ; sous-ensembles latin et
  latin étendu de Rubik fusionnés).

## Différences avec l'interface web

- Le corps d'un mail est affiché en texte riche Qt : pas d'images distantes ni
  de mise en page CSS avancée.
- La couleur source du thème est calculée sur la miniature du fond réduite à
  128 px (la quantification en JavaScript est bien plus lente que dans un
  navigateur) : la teinte est la même, la nuance peut légèrement varier.

Compilation : voir le README à la racine.
