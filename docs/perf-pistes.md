# Pistes d'optimisation (0.4.6)

Suite de `perf-ilot.md`. Ce rapport relit la version Qt complète (0.4.6), pas
le prototype mesuré le 16/10. Le prototype ne contenait ni le compagnon, ni la
météo animée, ni la plupart des relevés en arrière-plan. Ses 0,5 % au repos ne
valent donc plus pour la version actuelle.

Rien n'a été mesuré ici : c'est une lecture du code. Les gains annoncés sont des
ordres de grandeur à vérifier avec la méthode de `perf-ilot.md`. Chaque piste
indique où regarder et ce qu'il faudrait changer.

## Priorité 1 : gros gains, peu de risque

**Corrigée** (après 0.4.6, sans mesure : à vérifier sous Windows) :

1. Les animations d'ambiance (compagnon, météo animée, aurore, contour RGB et
   pulsé, horloge néon) suivent une horloge commune à 25 images/s
   (`Ilot.amb`, `Ilot.wave`). Elles s'arrêtent après 1 min sans clavier ni
   souris, et en plein écran. La promenade du compagnon et le clignotement
   « partie trouvée » continuent dans ces deux cas. Le compteur d'images/s
   n'est pas encore ajouté.
2. GPU relevé par NVML (`nvml.dll` chargée une fois). `nvidia-smi` ne sert
   plus qu'en repli, sans NVML.
3. `pc::exe_names()` (instantané Toolhelp) pour Wallpaper Engine et
   `procs_running`. Le relevé Discord ne tourne que si l'indicateur s'en sert.
4. Volume : rappels `IAudioEndpointVolumeCallback` et
   `IMMNotificationClient`, plus aucun sondage.
5. Notifications : `PRAGMA data_version` à chaque tour, la base n'est relue
   que si Windows l'a modifiée.
6. Pochettes et QR codes dans `img::ART` (16 dernières images).

### 1. Des animations d'ambiance tournent en permanence, pilule repliée

Avec les réglages par défaut (`pet: "blob"`, `wxfx: true`, `Ilot.qml:23`),
l'îlot replié fait tourner des animations sans fin :

- le compagnon respire (`Pet.qml:53`, `running: pet.visible && !Theme.reduced`) ;
- la météo animée fait passer les nuages (`WxFx.qml:75`, `running: fx.visible`,
  quel que soit le temps), plus le halo, les gouttes ou les étoiles selon la
  météo ;
- selon les réglages : aurore (`Aurora.qml:32`), contour RGB ou pulsé
  (`Island.qml:115`, `:124`), horloge néon (`PillClock.qml:30`).

Tant qu'une animation tourne, Qt redessine la fenêtre à chaque rafraîchissement
de l'écran : 60 à 240 images/s sur un écran de jeu. Il redessine aussi toute la
fenêtre de l'îlot (800 × 600, ou toute la largeur × 600 avec la barre),
transparente, que DWM doit composer à chaque fois. Les `NumberAnimation`
tournent sur le thread de l'interface et réévaluent les liaisons à chaque
image. C'est très probablement le plus gros poste au repos aujourd'hui.

Pistes, de la plus simple à la plus complète :

- **Couper l'ambiance quand personne ne regarde** : `Watch.idle` est déjà relevé
  toutes les 4 s (`Watch.qml:391`). Au-delà de 30 à 60 s sans clavier ni souris,
  ou en mode absent, on met en pause la respiration, la météo, l'aurore et le
  contour. Une seule propriété suffit, par exemple `Ilot.ambient`, ajoutée au
  `running:` de chaque animation.
- **Limiter la cadence** : ces mouvements sont lents (périodes de 1,6 à 21 s),
  et 20 à 30 images/s suffisent. Une horloge commune (`Timer` à 33 ou 50 ms)
  ferait avancer une phase `t`, et chaque effet en calculerait sa position
  (`breathe = 0.5 - 0.5 * Math.cos(2 * Math.PI * t / 3200)`). On rend alors au
  plus 30 images/s au lieu de 144.
- **Animators** (`YAnimator`, `OpacityAnimator`, `ScaleAnimator`) pour ce qui
  ne touche que x, y, l'opacité ou l'échelle, comme `Eq.qml` le fait déjà.
  Le thread de l'interface ne travaille plus, mais le rendu continue : à
  combiner avec les deux pistes au-dessus.

Pour le vérifier, il faudrait un compteur d'images : brancher
`QQuickWindow::frameSwapped` sur un compteur écrit toutes les 10 s dans le
journal `ILOT_QT_LOG`. Îlot replié, sans média et sans activité, il devrait
afficher 0 image/s.

### 2. `nvidia-smi` lancé toutes les 3 s

`activity.rs:228` et `:525` : sur une machine NVIDIA, la boucle d'activité
lance `nvidia-smi.exe` toutes les 3 s, en permanence. C'est une création de
processus qui charge NVML et initialise le pilote à chaque fois : plusieurs
dizaines de ms de CPU par appel, une fois toutes les 3 s.

- Charger `nvml.dll` une seule fois (`LoadLibrary`, ou la crate `nvml-wrapper`
  qui la charge à l'exécution), puis appeler `nvmlDeviceGetTemperature` et
  `nvmlDeviceGetUtilizationRates` : quelques microsecondes par relevé.
- Ne relever le GPU que s'il sert : jeu en cours (bilan de session, compagnon
  qui transpire) ou activité GPU affichée dans la pilule.

### 3. Relevés complets des processus, répétés

Plusieurs boucles créent un `sysinfo::System` neuf et relèvent tous les
processus avec leurs détails (chemin de l'exe, donc un `OpenProcess` par
processus) juste pour tester un nom :

| Où | Fréquence | Pour |
|---|---|---|
| `we.rs:150` (`running()`, appelé par `we::watch`, `we.rs:219`) | toutes les 2 s, si Wallpaper Engine est installé | savoir si WE tourne |
| `pc.rs:44` (`procs_running`, depuis `Watch.qml:517`) | toutes les 10 s, même si `dc_pill` est coupé ou que le RPC Discord est actif | savoir si Discord tourne |
| `audio.rs:209`, `valorant.rs:413` | ponctuel ou boucle | noms de processus |

Une fonction commune `procs::names()` basée sur `CreateToolhelp32Snapshot`
(noms et PID seulement, aucun processus ouvert) couvre tous ces cas. Côté QML,
le timer Discord ne devrait tourner que si `cfg.dc_pill && !dcRpc`.

### 4. Volume sondé toutes les 70 ms

`audio.rs:285` à `:308` : la boucle lit le volume et la sourdine 14 fois par
seconde, et cherche le périphérique par défaut toutes les ~2 s, en permanence.

- `IAudioEndpointVolume::RegisterControlChangeNotify` (rappel à chaque
  changement de volume ou de sourdine) ;
- `IMMDeviceEnumerator::RegisterEndpointNotificationCallback`
  (`OnDefaultDeviceChanged`) pour suivre le changement de sortie.

On passe de 14 réveils par seconde à aucun.

### 5. Notifications : base relue toutes les 1,2 s

`notif.rs:150` à `:181` : toutes les 1,2 s, la boucle lit les 50 derniers toasts,
analyse leur XML et fait un `stat` de chaque image (`image_data` →
`thumb_sized`). Elle compare ensuite la liste entière à la précédente.

- Solution la plus simple : `PRAGMA data_version` à chaque tour. Cette valeur
  ne change que si une autre connexion a modifié la base. Si elle n'a pas
  bougé, on saute tout le reste, ce qui évite presque tout le travail sans
  changer la logique.
- Mieux : être réveillé par `FindFirstChangeNotificationW` sur le dossier
  `Notifications` (écriture de `wpndatabase.db-wal`), avec un relevé de secours
  toutes les 30 s.
- Ne lire que les nouvelles lignes (`Id > seen_max`) et ne refaire la liste
  complète que sur un changement.

### 6. Pochettes gardées pour toujours (fuite lente)

`img.rs:38` (`url`) range les images dans `KEPT`, qui n'est jamais vidé. C'est
voulu pour les icônes et les fonds, mais `media.rs:141` y met **la pochette de
chaque morceau** (30 à 300 Ko). Il y met aussi le QR code de Quick Share
(`quickshare/mod.rs:779`). Après une journée de musique, la mémoire monte de
plusieurs dizaines de Mo.

Il suffit d'un `Ring` de plus (`img::ART`, 8 à 16 entrées), comme `THUMBS` et
`CLIPS`. Au passage, `find()` copie l'image entière à chaque demande
(`b.clone()`) ; un `Arc<[u8]>` éviterait ces copies.

## Priorité 2 : gains moyens

**En partie corrigée** (à vérifier sous Windows) :

- visualiseur : 15 trames/s îlot replié, 30 panneau ouvert (le passage en
  shader de l'onglet Média reste à faire, piste 7) ;
- luminosité : événements WMI `WmiMonitorBrightnessEvent`, l'ancien sondage
  ne sert plus qu'en repli (piste 9) ;
- Steam : manifestes gardés en cache, relus seulement s'ils ont changé ;
  bibliothèques relues toutes les minutes (piste 10) ;
- caméra / micro et thème de Windows : `RegNotifyChangeKeyValue`
  (`events::RegWatch`) ; presse-papiers : `AddClipboardFormatListener` ;
  Discord : 60 ms seulement en vocal, sinon réveillé par les commandes ;
  configuration absente : attente de `discord_setup` (piste 11) ;
- disques : place libre relue toutes les 2 s seulement panneau ouvert, sinon
  toutes les 30 s (piste 12).

Faits ensuite (2026-10-18, voir `docs/dev/ETAT.md`) : visualiseur de
l'onglet Média en shader (piste 7), Verr. Maj réveillée par le crochet
clavier (piste 11), pages déchargées après 5 min (piste 13), décodage à la
taille demandée (piste 14), couleur du thème en Rust (piste 15),
`opt-level = 3` (piste 16).

Restent : piste 8 (fenêtre repliée plus petite), Verr. Maj et plein écran
(piste 11), et le relevé `sys` complet quand rien ne l'affiche.

### 7. Visualiseur

À 30 trames/s, chaque trame passe par ces étapes : JSON en Rust, `QString`,
`JSON.parse` en QML, nouveau tableau `Ilot.shown` (`Ilot.qml:475`).
`shown` est une `property var` : chaque affectation réévalue **toutes** les
liaisons qui la lisent. Ce sont 24 barres de l'accueil, ou 48 dans l'onglet
Média, plus les 3 barres de `Eq` et les 3 bandes d'`Aurora`.

- **Onglet Média (`mirror`)** : chacune des 48 barres refait son `Gradient` et
  appelle trois fois `col()` en JS à chaque trame (`VizBars.qml:56` à `:63`). Un
  seul `ShaderEffect` (24 niveaux en uniformes, dégradé calculé dans le
  shader) remplacerait les 48 `Rectangle` : un seul appel de dessin et aucun JS
  par trame. Le projet compile déjà des shaders (`qt_add_shaders`).
- **Pilule repliée** : l'égaliseur n'a que 3 barres. Le cœur pourrait n'envoyer
  que 3 bandes, à 15 trames/s, quand l'îlot est replié (`viz_set` avec un mode,
  ou `ilot_set_open`). Le `Behavior` sur la hauteur (`Eq.qml:75`) fait aussi
  rendre à la fréquence de l'écran.
- **Chemin direct** : un signal C++ dédié (`Backend::viz(QList<qreal>)`) sans
  JSON, ou un objet `Viz` dont chaque barre lit sa propre propriété. Une barre
  ne serait alors réévaluée que si son niveau change.

### 8. Fenêtre de l'îlot plus petite quand elle est repliée

`shell.cpp:188` : la fenêtre garde 800 × 600 (ou toute la largeur × 600)
même repliée, et Qt Quick redessine toute la fenêtre à chaque image (pas de
mise à jour partielle). Repliée, la pilule plus la barre tiennent dans
~80 px de haut. Réduire la fenêtre réduit d'autant chaque image du visualiseur
et des animations. Le risque est un saut visible à l'ouverture, si le
redimensionnement arrive après la première image de l'animation. C'est à
mesurer après la piste 1, qui supprime déjà la plupart des images.

### 9. Luminosité : WMI toutes les 250 ms (portables)

`display.rs:183` interroge `WmiMonitorBrightness` 4 fois par seconde. Le coût
est surtout dans `WmiPrvSE.exe`, donc **invisible dans les mesures de l'îlot**.
`RegisterPowerSettingNotification(GUID_VIDEO_CURRENT_MONITOR_BRIGHTNESS)`, ou
une requête d'événements WMI `WmiMonitorBrightnessEvent`, préviennent sans
sonder.

### 10. Steam : tous les manifestes relus toutes les 1 à 3 s

`activity.rs:203` (`manifests()`) relit le registre, `libraryfolders.vdf`, chaque
dossier `steamapps` et **chaque** `appmanifest_*.acf` à chaque tour. Il analyse
aussi chaque fichier, une fois par clé, avec un `Vec` par ligne
(`games.rs:52`).

- Garder les manifestes en cache selon leur date de modification et ne
  relire que ceux qui ont changé.
- Relire la liste des bibliothèques une fois par minute.

### 11. Registre et presse-papiers sondés

| Où | Fréquence | Remplacement |
|---|---|---|
| `privacy.rs:103` (caméra / micro, parcourt tout `ConsentStore`) | 2 s | `RegNotifyChangeKeyValue` (sous-arbre) |
| `theme.rs:105` (clair / sombre de Windows) | 2 s | `RegNotifyChangeKeyValue`, ou `WM_SETTINGCHANGE` |
| `system.rs:224` (presse-papiers) | 400 ms | `AddClipboardFormatListener` (`WM_CLIPBOARDUPDATE`) |
| `system.rs:393` (Verr. Maj) | 120 ms | crochet clavier (`winkey.rs`) ou `WM_KEYDOWN VK_CAPITAL` |
| `winctl.cpp:17` (plein écran, par fenêtre) | 500 ms | `ABN_FULLSCREENAPP` (l'îlot réserve déjà le haut de l'écran) ou crochet `EVENT_SYSTEM_FOREGROUND` (déjà dans `events.rs`) |
| `discord.rs:388` (tube RPC) | 60 ms | lecture bloquante dans le thread, ou E/S asynchrones |
| `discord.rs:406` (configuration absente) | 2 s | attendre un signal de `discord_setup` |

Un seul thread peut attendre plusieurs de ces événements à la fois
(`WaitForMultipleObjects`). Pris un par un, ces relevés coûtent peu. Ensemble,
ils font des dizaines de réveils par seconde, ce qui empêche le processeur de
rester dans ses états de veille profonds (autonomie des portables).

### 12. `sys` émis toutes les 2 s, quoi qu'il arrive

`system.rs:102` : CPU, mémoire, **tous les disques**
(`GetDiskFreeSpaceEx`, qui peut bloquer sur un lecteur réseau), batterie,
toutes les 2 s, même si personne n'affiche ces valeurs. Les disques
pourraient être relevés toutes les 30 s, sauf quand l'accueil est affiché. On
pourrait aussi ralentir tout le relevé (10 s) quand ni l'accueil ni le
CPU / RAM de la barre ne se voient.

## Priorité 3 : mémoire, démarrage, taille

### 13. Pages gardées après leur première ouverture

`Panel.qml:339` : une page est créée à sa première ouverture, puis gardée. Après
un passage dans Apps (icônes de toutes les applis), Réglages
(1 842 lignes) ou Fonds, la mémoire ne redescend plus. On pourrait décharger
les pages autres qu'Accueil et Média après quelques minutes de panneau fermé,
puis appeler `QQuickWindow::releaseResources()` et `gc()`.

### 14. Images

- `backend.cpp:165` (`IlotImages`) : l'image est décodée en entier puis
  réduite. `QImageReader::setScaledSize` décode directement à la bonne taille
  (le JPEG se réduit au décodage), avec moins de mémoire et de temps.
- Vérifier que les `Image` ont un `sourceSize`. Sinon, Qt garde l'image à sa
  taille d'origine dans son cache.

### 15. Couleur du thème

`Backend::imagePixels` renvoie jusqu'à 16 384 `double` dans une `QVariantList`,
quantifiés en JS dans un `WorkerScript` (un second moteur JS en mémoire).
Faire la quantification et le score en Rust (crate `material-colors`, même
algorithme que `material-color-utilities`) serait bien plus rapide, et pourrait
travailler sur l'image entière (teinte plus fidèle, voir `qt/README.md`).

### 16. Compilation et distribution

- `Cargo.toml` : `opt-level = "s"` optimise la taille au détriment de la
  vitesse. Or le cœur fait du calcul : FFT, décodage symphonia, miniatures,
  crypto Quick Share. `opt-level = 3` et `codegen-units = 1` ne grossiraient la
  DLL que de peu, à côté des 40 Mo de Qt.
- QML : `qmlcachegen` ne compile en C++ que les liaisons dont il connaît les
  types. Beaucoup de `property var` (`cfg`, `media`, `shown`…) les en
  empêchent. `qmllint` signale les liaisons non compilées : typer les plus
  sollicitées (visualiseur, horloge, pilule) déplace ce travail hors de
  l'interpréteur.
- `windeployqt` : vérifier les plugins copiés (formats d'images, `qmltooling`,
  pilotes inutiles) pour réduire les 40 Mo et le nombre de DLL chargées au
  démarrage.

## Ordre conseillé

1. Ajouter le compteur d'images/s (piste 1), puis refaire les mesures de
   `perf-ilot.md` sur 0.4.6, pour avoir un point de départ chiffré. Ajouter
   aussi au dépôt les scripts de mesure restés dans le dossier de travail.
2. Pistes 1, 2, 6 : peu de code, gains les plus probables (CPU au repos,
   processus créés, mémoire qui monte).
3. Pistes 3, 4, 5 : remplacer les sondages les plus lourds par des événements.
4. Piste 7 (visualiseur en shader), puis le reste selon les mesures.
