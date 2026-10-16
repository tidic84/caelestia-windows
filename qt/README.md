# Interface Qt Quick / QML de l'îlot

L'îlot complet : pilule (repliée, survol, activités), panneau et ses
onglets (essentiels + addons, `Ilot.catalog`), barre façon Waybar sur l'écran de l'îlot et sur les autres écrans,
info-bulles, bandeau des sous-titres, compagnon baladeur, icône de la zone
de notification, Ctrl+Alt+Espace. Tout ce qui
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
  - singletons : `Theme` (palette Material You, polices, courbes,
    accessibilité), `Api` (`invoke` et `listen`, comme Tauri), `Ilot` (état
    et logique communs, ce que faisait `app.js`, dont le catalogue des
    onglets : essentiels et addons), `Watch` (ce qui est
    surveillé hors des pages : file des notifications, activités en cours,
    mode jeu, mode absent, partie trouvée, extinction programmée, voyant
    caméra / micro, services, partage, sous-titres, raccourcis, mises à
    jour, compagnon) ;
  - fenêtres : `Main` (îlot), `Bar` (autres écrans), `TipWindow`,
    `Captions` (sous-titres en direct), `PetWindow` (promenade du compagnon) ;
  - îlot : `Island` (avec `Aurora`, `WxFx`), `Pill` (avec `Pet`,
    `PillClock`), `Panel`, `QuickShare` et une page par onglet (`HomePage`,
    `MediaPage`, `CtrlPage`, `AppsPage`, `MailPage`, `PcPage` et ses cartes
    `ServicesCard`, `HealthCard`, `ShutdownCard`, `SensCard`, `SoundsPage`,
    `TasksPage`, `ClipsPage`, `AssistPage`, `WallsPage`, `SettingsPage`) ;
  - modules JavaScript repris de l'interface web : `mcu.mjs`
    (material-color-utilities), `calc.mjs`, `emoji.mjs`, `ical.mjs`.
- `shaders/round.frag` : images aux coins arrondis, sans calque.
- `fonts/` : Rubik (graisses 300 à 700) et Material Symbols Rounded, les
  mêmes polices que l'interface web, converties de WOFF2 en TTF (fontTools :
  instances statiques des polices variables ; sous-ensembles latin et
  latin étendu de Rubik fusionnés). Material Symbols ne garde que les icônes
  dont le nom apparaît dans `qml/` : une nouvelle icône demande de refaire le
  sous-ensemble à partir de la police complète (FILL 0, GRAD 0, opsz 24,
  wght 400), sinon son nom s'affiche en lettres.

## Différences avec l'interface web

Les ajouts de la branche `ilot-ajouts-romain` (santé du PC, services,
soundboard, sous-titres, compagnon, accessibilité…) ont été portés depuis
l'ancienne interface web ; quelques choix diffèrent :

- Traduction et Claude partagent l'onglet **Assistant**.
- **Ajouter un addon** : une entrée dans `Ilot.catalog` (id, icône, nom,
  description, page QML) ; il apparaît dans Réglages › Addons. Ses relevés en
  arrière-plan côté Rust se règlent sur `settings::addon_on(app, "<id>")`.
- Les sons de la soundboard sont décodés par le cœur Rust (symphonia) et non
  plus par le navigateur : mp3, wav, ogg (Vorbis), flac et m4a ; l'Opus n'est
  pas pris en charge.
- La position « en bas de l'écran » de l'îlot n'est pas reprise : la forme de
  l'îlot, la barre et la réservation du haut de l'écran sont pensées pour le
  haut. L'écran de l'îlot se choisit toujours dans Réglages.
- La météo utilise la ville choisie dans Réglages (pas de position par IP).
- Les réglages de l'interface (apparence, pilule, accessibilité...) sont
  dans `settings.json` avec les autres ; l'extinction programmée, les paroles
  et le convertisseur de sensibilité sont gardés dans `ui.json`.

- Le corps d'un mail est affiché en texte riche Qt : pas d'images distantes ni
  de mise en page CSS avancée.
- La couleur source du thème est calculée sur la miniature du fond réduite à
  128 px (la quantification en JavaScript est bien plus lente que dans un
  navigateur) : la teinte est la même, la nuance peut légèrement varier.

Compilation : voir le README à la racine.
