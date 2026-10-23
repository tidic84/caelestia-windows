# Plan : refonte de l'interface Média (style « Swiftify »)

Statut : **codé et installé le 2026-10-23**, d'après la maquette validée.
Le détail et ce qui reste à tester sont dans `ETAT.md`.

## Ce qu'on veut

1. **Refaire l'interface Média** dans le style des lecteurs « notch » de macOS.
   « Swiftify » n'existe pas comme produit ; les références les plus proches
   sont boring.notch et PlayNotch (voir « Références » en bas).
2. **Contrôler la musique au seul survol**, sans ouvrir le panneau : dans le
   peek (la pilule survolée), pouvoir passer au titre suivant ou précédent, et
   pas seulement mettre en pause. Se déplacer dans le titre aussi.

Règles du projet : changements essentiels, rien de cassé, pas de refonte hors
média, Rust seulement si l'usage le demande, compilation + relecteur.

## État actuel (relevé du 2026-10-23)

| Zone | Fichier | Aujourd'hui |
|---|---|---|
| Replié | `Pill.qml:40-130` | pochette ronde 18 px qui tourne + `Eq`. 200×30 |
| Peek (survol) | `Pill.qml:335-401` | pochette 46 px, titre, artiste, barre 3 px **non cliquable**, un seul bouton lecture/pause. 420×66 (`Ilot.qml` `sizeFor`) |
| Accueil | `HomePage.qml:472-571` | disque + visualiseur circulaire + `MediaControls`, pas de progression |
| Onglet Média | `MediaPage.qml` | fond pochette floutée, pochette 260 px inclinée 3D, titre/artiste/album, `M3Slider` de seek (envoi au relâchement), `MediaControls big`, volume appli, paroles, playlists |
| Rust | `src/media.rs` | GSMTC, session courante seulement. `media_action` : `toggle`, `next`, `prev`, `seek` (secondes). Pas de shuffle/repeat, pas de capacités (`Controls()`) |

Gestes actuels sur la pilule : clic gauche = ouvrir le panneau, clic molette
= lecture/pause, molette = volume (Maj = appli au premier plan).

**Défaut trouvé pendant le relevé** : `Ilot.seek()` met à jour la position
dans QML sans attendre de réponse. Si l'appli refuse le seek (certaines
applis, souvent les navigateurs selon le site), Rust ne réémet rien : il
compare au *dernier état qu'il a lui-même émis* (`media.rs:234-235`), pas à
la position locale du QML, et `media_get` n'est appelé qu'au démarrage. La
barre reste donc fausse jusqu'au prochain changement (titre, pause, appli,
durée) ou jusqu'à une dérive de plus de 1,5 s côté appli.

## Proposition

### Étape 1 : composant `SeekBar.qml` (nouveau, partagé)

Une barre de progression interactive unique, utilisée dans le peek et dans
l'onglet Média (elle remplace le `M3Slider` de seek ; `M3Slider` reste pour
le volume).

- Piste fine (3 px dans le peek, 5 px dans l'onglet), qui **s'épaissit au
  survol** (×1,8) avec une animation courte. Pas de poignée au repos ; une
  poignée ronde apparaît au survol.
- **Zone de prise** plus haute que la piste (≥ 20 px), pour ne pas avoir à
  viser 3 px.
- **Bulle de temps** pendant le survol et le glissé. Attention : la fenêtre
  est découpée par `setMask`, donc rien ne peut dépasser de l'îlot. Dans le
  peek (collé en haut de l'écran), la bulle s'affiche *dans* l'îlot, par-dessus
  le titre ; dans l'onglet Média, au-dessus de la barre.
- Clic = saut immédiat. Glisser = aperçu seulement, **envoi au relâchement**.
  Pendant le glissé, la position venant de Rust n'écrase pas la barre
  (même principe que le `Binding when: !dragging` actuel), et l'animation de
  500 ms du remplissage est coupée (sinon la barre suit en retard).
- Saisie par un `MouseArea` avec `preventStealing: true` (même schéma que
  `M3Slider`), pas un `DragHandler` seul : sinon le `MouseArea` de la pilule
  prend le clic et ouvre le panneau. Pas de `onWheel` : la molette doit rester
  le volume.
- Désactivée (non interactive, aspect normal) si `duration` vaut 0 (radio,
  live) ou si l'appli interdit le seek (`can_seek`, étape 4).
- Remplissage par `Scale` (pas de mise en page), comme la barre actuelle du
  peek, pour garder les perfs.
- Composant à part plutôt qu'une extension de `M3Slider`, qui sert à 7 autres
  curseurs (volume, luminosité…) qu'on ne veut pas toucher.

### Étape 2 : peek « contrôles au survol »

Nouvelle disposition du peek avec média (Discord reste à droite s'il est
affiché) :

```
┌─────────────────────────────────────────────────────────┐
│ [pochette]  Titre du morceau…            ⏮   ⏯   ⏭      │
│   52 px     Artiste                                      │
│             1:12 ━━━━━━━━━●──────────────── -2:31        │
└─────────────────────────────────────────────────────────┘
```

- Boutons **précédent / lecture-pause / suivant** : trois `IconBtn` de 36 px
  (`MediaControls` n'a pas de version compacte), grisés si l'appli ne les
  permet pas (`can_next` / `can_prev`, étape 4).
- `SeekBar` avec temps écoulé et restant.
- Taille : ~460×76 au lieu de 420×66 (à ajuster à l'œil) dans
  `Ilot.sizeFor()` ; les +70 de Discord restent. Tout le reste (zone de
  survol, zones cliquables, acrylique, rayon) suit `Ilot.size`. Seule la
  largeur de la colonne titre est codée en dur pour un bouton
  (`Pill.qml:354`) : à recalculer.
- **Le clic sur les boutons et la barre n'ouvre pas le panneau** (déjà le cas
  pour le bouton pause actuel, `Btn.qml` prend le clic) ; le clic sur le
  reste du peek ouvre toujours le panneau.
- **Ne pas replier pendant un glissé** : aujourd'hui, sortir du peek replie
  au bout de 120 ms, ce qui masquerait la barre et annulerait le seek. Aucun
  verrou existant ne convient (`locked` et `pinned` concernent le panneau
  ouvert). Nouvel état `Ilot.seekDrag` testé dans `setHovered` : on continue
  d'enregistrer `hovered`, mais on ne replie pas ; **au relâchement, si la
  souris n'est plus sur l'îlot, on relance le repli** (sinon le peek resterait
  ouvert, car rien ne redéclenche le survol).
- Après « suivant », petit retour visuel immédiat (le titre fond). Pas pour
  « précédent » : beaucoup d'applis reviennent au début du même morceau.

**Gestes en plus, à choisir ensemble** (aucun n'est obligatoire) :
- A. **Glisser horizontalement sur la pochette** du peek : gauche = suivant,
  droite = précédent. Naturel, mais à distinguer d'un simple clic (seuil de
  ~30 px).
- B. ~~Molette horizontale~~ : écarté. Elle règle déjà le volume
  (`Pill.qml:33`), et un défilement en diagonale ferait les deux.
- C. Rien de plus : les boutons suffisent.

Ma recommandation : boutons + C pour commencer, A en option si ça manque.

### Étape 3 : onglet Média, style notch

Garder la structure (pochette à gauche, infos à droite, paroles, playlists,
volume) et changer le rendu :

- **Halo** : copie floue et colorée de la pochette derrière elle (au lieu de
  l'ombre noire actuelle), seulement en lecture.
- **Pause visible** : en pause, la pochette se réduit (0,9) et s'assombrit ;
  elle revient en lecture. Animation ressort.
- **Couleur de la pochette** : artiste et remplissage de la barre teintés par
  la couleur extraite de la pochette, avec une luminosité minimale pour
  rester lisible. Attention : `Ilot.artColor()` ne calcule rien si le thème
  n'est pas « Pochette » (`Ilot.qml:994`) et `artArgb` est un entier ARGB
  brut. Il faut donc lever cette condition (un appel `theme_source` de plus
  par morceau, déjà fait en thème Pochette) et convertir la couleur. En thème
  « Pochette », `Theme.primary` en découle déjà : on l'utilise directement.
- **Typo** : titre plus gros, marquee (défilement) si trop long au lieu de 2
  lignes coupées (pas de composant marquee dans le dépôt : `Marquee.qml` à
  créer, défilement seulement si `page.shown`) ; album plus discret.
- `SeekBar` (étape 1) + temps écoulé / **restant** (`-2:31`).
- Boutons : prev / lecture-pause (plus gros, plein) / next, mieux espacés.
- L'inclinaison 3D au survol est gardée (elle est déjà réussie), à revoir
  ensemble si elle jure avec le halo.
- Respecter `Theme.reduced` (animations réduites) et le réglage `media_bg`.
- **Perf** : l'onglet Média reste chargé en mémoire (`Panel.qml:352`, `keep`).
  Le halo (un 2e flou `MultiEffect`), le marquee et l'animation de pause
  doivent s'arrêter quand `page.shown` est faux.

Pas touché : accueil (`HomePage.qml`), pilule repliée, visualiseur, paroles,
playlists. On pourra y revenir après.

### Étape 4 (Rust, petite) : seek fiable

Justifiée par l'usage (défaut ci-dessus) :

- **Resynchro après chaque seek** (QML seul) : ~1 s après un seek, relancer
  `media_get` et appliquer le résultat, que l'appli ait accepté ou non.
  Couvre aussi les applis qui répondent « oui » sans bouger.
- `media_action` renvoie le booléen des `Try*Async` (`crate::wait` renvoie
  déjà `Result<bool>`) ; utile pour un retour d'erreur, facultatif. Personne
  ne lit le retour actuel (vérifié : `Watch.qml:51`, `:1069-1071`,
  `Ilot.qml:471`, `MediaControls.qml`).
- `MediaInfo` gagne `can_seek`, `can_next`, `can_prev`, lus dans
  `GetPlaybackInfo()?.Controls()?` (`IsPlaybackPositionEnabled`,
  `IsNextEnabled`, `IsPreviousEnabled`). `GetPlaybackInfo()` est déjà appelé
  (`media.rs:94`) et la feature `Media_Control` est active. Sérialisé en
  snake_case → `Ilot.media.can_seek`. Côté QML, tester `!== false` (ou
  ajouter les champs à l'objet par défaut, `Ilot.qml:445`) pour ne pas tout
  désactiver quand le champ manque.
- Ces trois champs entrent dans `same_but_position` (`media.rs:146`) pour
  être réémis quand ils changent.

### Hors plan (à décider plus tard)

- Aléatoire / répétition (`IsShuffleActive`, `AutoRepeatMode` dans GSMTC) :
  demande du Rust en plus.
- Choisir entre plusieurs applis qui jouent (`GetSessions`).
- Clic sur la pochette = amener l'appli source au premier plan.

## Ordre de travail et vérification

1. `SeekBar.qml` + branchement dans `MediaPage` (remplace l'existant, même
   comportement, donc testable sans risque).
2. Rust étape 4 + `cargo clippy --all-targets ; cargo test`.
3. Peek (étape 2) + tailles dans `Ilot.qml`.
4. Style de l'onglet Média (étape 3).
5. `qt\build.cmd` (les QML sont pris par `file(GLOB)`, rien à ajouter dans
   `CMakeLists.txt`), `qmllint` sur les fichiers touchés, `install.ps1`.
6. Agent `relecteur` sur tout le diff.

À tester à la main, avec Spotify **et** un navigateur (YouTube) :
- survol → peek : prev / pause / next marchent, le panneau ne s'ouvre pas ;
- clic ailleurs sur le peek → le panneau s'ouvre comme avant ;
- clic sur la barre → saut ; glisser → bulle de temps, saut au relâchement,
  pas de saut de la barre pendant le glissé ;
- glisser en sortant de l'îlot → il ne se replie pas avant le relâchement,
  puis se replie bien **après** le relâchement hors de l'îlot ;
- relâcher hors de la fenêtre → le seek part quand même ;
- appli qui refuse le seek → la barre revient à la bonne position en ~1 s ;
- radio / live (durée 0) et `can_seek` faux → barre inerte ; vérifier que la
  barre de l'onglet Média ne se désactive pas à tort (Spotify, YouTube) ;
- « précédent » en début de morceau et après 3 s ;
- molette = volume et clic molette = pause toujours OK, y compris au-dessus
  des boutons et de la barre du peek ;
- Discord affiché en même temps → rien ne se chevauche ;
- une notification (`act`) qui arrive pendant le glissé ;
- tailles de pilule s / m / l, thème clair et sombre, animations réduites ;
- CPU comparé à `docs/perf-ilot.md` (version Qt, lecture îlot replié :
  0,5 %), et **mesurer aussi** en peek et onglet Média ouvert, jamais mesurés
  jusqu'ici.

Fin de session : `ETAT.md`, `BACKLOG.md`, `ARCHITECTURE.md` (nouveau
fichier), `CHANGELOG.md` + version si on publie.

## Maquette

`docs/dev/maquettes/media.html` (à ouvrir dans un navigateur) : pilule
repliée, survol, onglet Média, carte de l'accueil, avec un banc d'essai
(variantes de style, simulation de refus du seek, direct, Discord, tailles).
On y choisit les variantes avant d'écrire le QML.

## Références

- **Swiftify** : https://github.com/swiftify-org/swiftify, lecteur Spotify en
  Qt Quick/QML + Rust (librespot), Material 3 Expressive. Pas de licence :
  on s'inspire des valeurs, on ne copie pas les fichiers. Signes distinctifs :
  barre ondulée animée en lecture (4 → 6 px au survol, poignée verticale
  4×18), bouton lecture « cookie » festonné qui tourne, pochette festonnée
  avec anneau de spectre, fond « liquide » aux couleurs de la pochette,
  paroles à ligne active lumineuse.

- boring.notch : https://github.com/TheBoredTeam/boring.notch (pochette
  réduite et voilée en pause, halo flou, barre 5 → 9 px au glissé)
- PlayNotch : https://github.com/Mauto82/PlayNotch (couleur de pochette,
  aperçu du temps au survol de la barre, seek au glissé)
