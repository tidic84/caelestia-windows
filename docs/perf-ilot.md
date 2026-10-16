# Consommation de l'îlot : mesures, corrections et comparaison Qt

Mesures faites le 16/10/2026 sur la même machine (Windows 11, écran à 150 %).
Trois versions sont comparées :

- **base** : `main` (0.1.3) ;
- **perf** : la branche `perf-ilot` (ce document) ;
- **qt** : le prototype Qt Quick / QML de la branche `qt-qml-proto` (`qt/`).

## Méthode

Pour chaque version, l'îlot est lancé seul (une instance), puis on attend
20 s avant de mesurer 30 s pendant que personne n'y touche :

- **CPU** : somme du temps processeur de tout l'arbre de processus (`ilot.exe`
  plus tous les `msedgewebview2` qu'il lance), en % d'un cœur ;
- **RAM** : mémoire privée, sommée sur le même arbre ;
- **GPU** : compteur « GPU Engine » de Windows pour ces processus.

Pour avoir un média sans bruit, on lit un WAV de silence dans le Lecteur
multimédia de Windows, ce qui crée une vraie session GSMTC. Le silence ne
produit aucune trame de visualiseur. Le visualiseur est donc simulé à
30 trames/s par le backend : `ILOT_SIM_VIZ=1` côté Rust, `--sim-viz` côté Qt.
La version base ne connaît pas cette option ; dans ses scénarios 3 et 5, il
n'y a donc pas de visualiseur.

Les scripts `measure.ps1`, `cdp.mjs` et `suite2.ps1` ne sont pas dans le
dépôt (ils sont restés dans le dossier de travail). Les chiffres varient d'une
série à l'autre : au repos, la base a donné 4,4 %, 4,9 % puis 8,0 % selon les
séries. Seuls les ordres de grandeur sont significatifs.

## Résultats

CPU en % d'un cœur, RAM privée totale. Sauf pour le scénario 5, l'îlot est
replié.

| Scénario | base | perf | qt |
|---|---|---|---|
| 1. Repos, aucun média | 8,0 % · 244 Mo | **1,2 %** · 260 Mo | **0,5 %** · 85 Mo |
| 2. Média en lecture | 22,0 % · 240 Mo | **2,0 %** · 247 Mo | **0,5 %** · 87 Mo |
| 4. Média en pause | 11,7 % · 241 Mo | **1,3 %** · 246 Mo | **0,8 %** · 87 Mo |
| 3. Lecture + visualiseur 30 i/s | (pas de simulation) | 29,6 % · 250 Mo | **9,2 %** · 85 Mo |
| 5. Panneau ouvert (accueil), lecture + visualiseur | 27,8 %¹ · 314 Mo | 34,4 % · 321 Mo | **10,6 %** · 89 Mo |
| Processus | 7 | 7 | 1 |
| Taille à distribuer | 11,7 Mo² | 11,7 Mo² | 40,2 Mo (57 fichiers) |

¹ Sans visualiseur : la base ignore `ILOT_SIM_VIZ`.
² Sans WebView2, déjà présent dans Windows.

Pour le visualiseur, une première série simulait les trames depuis la page
(`emit('viz')` en JS, qui fait l'aller-retour page → Rust → page). Elle donne
**83 %** pour la base et **45 %** puis **74 %** pour perf selon les séries. Le
coût de la simulation elle-même entre dans la mesure et elle varie trop :
mieux vaut se fier au scénario 3, simulé côté backend.

Profil du renderer (CDP, port de debug de WebView2), média en lecture, îlot
replié :

| | base | perf |
|---|---|---|
| Mises en page / s | 57 | 0,1 |
| Recalculs de style / s | 57 | 0,1 |
| Tas JS | 4,1 Mo | 2,0 Mo |
| Animations actives | `width` (barre de progression), 3 × `stroke-dashoffset` (jauges), `spin` (disque, panneau fermé) | aucune hors de vue |

## Ce qui coûtait

1. **Suivi du curseur et des écrans (Rust, ~5 à 8 % d'un cœur)**.
   `track_cursor` et `screens::watch` appelaient toutes les 25 ms
   `outer_position()`, `outer_size()` et `scale_factor()`. Dans Tauri, ces
   accesseurs envoient un message à la boucle principale et attendent sa
   réponse : la boucle était réveillée environ 120 fois par seconde. En plus,
   `place()` recalculait la position toutes les 2 s, ce qui listait les écrans
   par le même chemin.
2. **Lecteur** : le gestionnaire GSMTC était redemandé toutes les 500 ms (un
   appel asynchrone inter-processus). Pendant la lecture, `media` était
   réémis toutes les 500 ms puisque la position change, ce qui faisait
   repasser tout `applyMedia` dans la page.
3. **Animations invisibles**. Le panneau replié est seulement transparent
   (`opacity: 0`) : le disque y tournait en permanence. Sans visualiseur, la
   barre de progression du survol avait une transition `width` relancée
   toutes les 500 ms, et l'égaliseur animait `height`. Résultat : une mise en
   page et un recalcul de style à chaque image, à 57 images/s, même îlot
   replié.
4. **Minuteries JS** : l'horloge réécrivait le DOM chaque seconde, et les
   jauges du panneau (avec leur transition SVG) toutes les 2 s, même
   invisibles.
5. **Images en base64**. Les icônes, pochettes, fonds, aperçus et
   presse-papiers passaient en data URL : elles restaient en mémoire dans le
   tas JS, dans le DOM et dans chaque message IPC.

## Corrections (branche `perf-ilot`)

- `geom()` (main.rs) lit la position, la taille et le DPI d'une fenêtre par
  Win32 (`GetWindowRect`, `GetDpiForWindow`), sans passer par la boucle
  principale. Le test de zone n'est refait que si le curseur, la fenêtre ou
  les zones ont bougé (`HIT_GEN`). La fenêtre n'est replacée que si
  l'empreinte des écrans change (`monitors_sig`, `EnumDisplayMonitors`).
- `events.rs` : des hooks WinEvent (création, destruction, affichage, titre,
  bureau virtuel, réduction, premier plan) réveillent `bar::watch`, au plus
  une fois toutes les 250 ms, avec un relevé de secours toutes les 3 s.
- `media.rs` : le gestionnaire est créé une fois, la boucle est réveillée par
  les événements de la session (avec un relevé toutes les 1 s en lecture,
  5 s sinon), et `media` n'est réémis que si autre chose que la position
  change (ou si la position saute de plus de 1,5 s).
- `img.rs` : protocole `ilot` (`http://ilot.localhost/<clé>.<ext>`). Les
  miniatures déjà en cache sur le disque sont servies depuis le fichier. Les
  aperçus de fenêtres et le presse-papiers passent par des files bornées.
- Interface : les animations sont en pause dans ce qui ne se voit pas
  (`animation-play-state`). L'égaliseur et la barre de progression utilisent
  `transform` (pas de mise en page). L'horloge ne touche le DOM qu'au
  changement de minute, les jauges seulement quand l'accueil est affiché.

Le curseur reste sondé toutes les 25 ms, mais chaque passage ne fait plus que
deux appels système. Un hook souris bas niveau serait appelé à chaque
déplacement de la souris dans tout le système (jusqu'à 1000 fois par seconde
avec une souris de jeu) et ajouterait de la latence dans les jeux.

## Ce qui reste

- **Le visualiseur.** À 30 trames/s, chaque trame passe par l'IPC, est
  analysée en JSON et appliquée au DOM ; la version perf coûte encore
  ~30 % d'un cœur avec. Pistes : envoyer moins de trames quand l'îlot est
  replié (l'égaliseur n'a que 3 barres), ou passer les bandes en binaire.
- **Le plancher de RAM de WebView2** : 7 processus et ~250 Mo, quoi qu'on
  fasse.

## Qt Quick / QML

Le prototype (`qt/`, branche `qt-qml-proto`) reprend la fenêtre et son
masquage, la pilule, le panneau Accueil / Média, le lecteur, les jauges et le
visualiseur. Il ne reprend pas le reste (lanceur, barre, notifications…).
Ses chiffres sont donc un plancher : une réécriture complète ajouterait du
code et des images, mais pas un navigateur.

- **RAM : environ 3 fois moins** (85 à 90 Mo contre 245 à 320 Mo), en un seul
  processus.
- **Au repos : le même ordre de grandeur que perf** (0,5 % contre 1,2 %). Une
  fois les sondages corrigés, il reste peu à gagner.
- **Visualiseur : environ 3 fois moins** (9 % contre 30 %). Pas d'IPC ni de
  JSON, et le scene graph ne redessine que les rectangles qui bougent.
- Même en QML, il faut faire attention aux animations invisibles. La première
  version du prototype consommait 4 à 10 % au repos pour trois raisons : un
  `Behavior` des jauges s'animait panneau fermé, la pochette tournait sans
  pochette, et l'égaliseur était animé côté interface plutôt que par un
  `Animator` sur le thread de rendu.
- **Démarrage** : 230 ms jusqu'à la première fenêtre visible pour Qt. La
  mesure équivalente côté Tauri n'est pas fiable (elle voit une fenêtre
  avant que la page soit chargée).
- **Coût** : il faut réécrire environ 3 400 lignes de JS, 885 de CSS et
  636 de HTML, porter le backend Rust en C++ (ou via cxx-qt), et distribuer
  40 Mo de DLL Qt.

**Conclusion** : les corrections de `perf-ilot` font passer l'îlot replié de
8 à 22 % d'un cœur à 1 à 2 %, sans réécriture. Qt ne vaut le coup que si la
RAM (−160 à −230 Mo) ou le visualiseur toujours actif comptent vraiment.
