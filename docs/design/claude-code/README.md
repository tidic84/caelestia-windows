# Îlot × Claude Code : animation et notification de fin

Fonctionnalité de Tyz (tableau de suivi : « Notification / Animation pour
Claude Code »). **Codé en 0.4.10.** L'animation est dans
`qt/shaders/claude.frag` et `qt/qml/ClaudeMark.qml`, l'état dans
`qt/qml/Watch.qml` (`onClaude`), le relais des hooks dans `qt/src/main.cpp`
(`claudeHook`) et `shell.cpp`, et les hooks dans `src/claude.rs`. Ce dossier
garde la maquette et la spécification. Pour modifier l'animation, régler
d'abord `maquette.html`, puis reporter les valeurs dans `claude.frag`.

Différences avec la proposition plus bas :
- c'est `WM_COPYDATA` vers la fenêtre `IlotTray` qui est utilisé, pas un tube
  nommé ;
- un hook `Notification` (`idle_prompt`) a été ajouté, parce qu'Échap ne
  déclenche pas `Stop` ;
- la vitesse d'orbite est π/2 rad/s, pour que la boucle se raccorde.

- `maquette.html` : maquette de référence, à ouvrir dans un navigateur. Les
  réglages sont regroupés dans l'objet `ANIM` en haut du script.
- Maquette en ligne (toutes les versions essayées) :
  https://claude.ai/artifact/WuBj6iXzXVFFJ4JUGg753f

## Ce qu'on veut

Cas visé : un long prompt lancé en mode `--dangerously-skip-permissions`. On
part faire autre chose, et on veut savoir quand Claude a fini.

1. **Pendant que Claude travaille** : à gauche de l'heure dans la pilule,
   l'animation L4 ; à droite, le temps écoulé (`4:12`).
2. **Quand Claude a fini** : un son court (« bulle » pour l'instant, le choix
   final est à faire), puis l'animation et le minuteur s'effacent (fondu +
   réduction, 350 ms). L'îlot revient à l'heure seule. Pas de coche ni de
   pilule agrandie : écartés pendant les essais.
3. **Règle du son** : il ne joue que si la tâche a duré **au moins 30 s**
   (réglable) et si le terminal n'est pas la fenêtre au premier plan.

## L'animation L4

4 nœuds orange en orbite, sans liens entre eux, chacun avec une traînée. Ils
spiralent vers le centre et fusionnent en une étoile à 10 rayons, rappel du
logo Claude. L'étoile respire, puis se replie et relâche les nœuds. Une boucle
de **5 s** se raccorde sans saut.

| Temps (s) | Étape | Détail |
| --- | --- | --- |
| 0 – 1,7 | Orbite | Rayon 1, vitesse 1,5 rad/s, nœuds espacés de 90° |
| 1,7 – 2,4 | Spirale vers le centre | Rayon `1 − InCubic(k)` ; +½ tour (InOutCubic) |
| 2,35 – 2,95 | Impact | Cœur blanc qui s'allume, onde de choc (cercle de 0,3R à 1,4R qui s'efface) |
| 2,35 – 2,75 (+35 ms par rayon) | Déploiement | Chaque rayon s'ouvre en OutBack (dépassement 1,4) ; un rayon sur deux fait 70 % |
| 2,4 – 3,9 | Étoile | Respiration ±10 % (sin, 4,2 rad/s), rotation 26°/s |
| 3,85 – 4,45 | Repli | Rayons rentrés en InOutCubic, décalés de 20 ms, cœur éteint |
| 3,9 – 4,5 | Spirale vers l'extérieur | Rayon `OutBack(k)` ; +½ tour |
| 4,5 – 5 | Orbite | Retour à l'état de départ |

**Pourquoi la boucle ne saute pas** : chaque cycle ajoute exactement un tour
complet (½ en entrant, ½ en sortant). L'angle à la fin d'un cycle est donc
égal à celui du début, à 2π près.

**Couleurs** :
- `#ffb27a` (orange chaud) : tête des nœuds, centre des rayons ;
- `#ff6a2b` (orange profond) : traînées, bout des rayons, halo ;
- `#fff1e6` (blanc chaud) : cœur de l'étoile et point au centre des nœuds
  (seulement au-dessus de 40 px).

Les lueurs s'additionnent (`globalCompositeOperation = "lighter"`).

**Dans l'appli (0.4.10), plus sobre** : on a trouvé la maquette trop brillante. Les couleurs passent à `#f0a371`, `#e0612e` et `#f9dac4`, les halos sont multipliés par `GLOW = 0.4`, la traînée est à 0,4, l'onde de choc à 0,45, et le tout × 0,88. Voir `qt/shaders/claude.frag`.

**Tailles** : dans l'îlot, l'animation fait 20 px. Rayon d'orbite 0,36 × la
taille, nœud de 1,8 px au minimum. Au-dessus de 40 px, 0,32 × la taille. La
traînée compte 7 échos en petit et 12 en grand, espacés de 18 ms.

## Portage en QML : pistes

- **Rendu** : un `Canvas` QML redessiné à chaque image coûterait cher (JS par
  image). Deux options plus légères :
  1. un `ShaderEffect`, car le projet compile déjà des shaders
     (`qt_add_shaders`). Tout se calcule dans le fragment shader à partir d'un
     uniform `t` : distance aux 4 nœuds et à leurs échos, rayons de l'étoile en
     coordonnées polaires. C'est la piste recommandée : un seul appel de dessin
     et aucun JS par image ;
  2. des `Rectangle` ronds (4 nœuds + échos) et 10 `Rectangle` pour les rayons,
     positionnés par des liaisons sur une seule propriété `t`. Plus simple,
     mais il y a beaucoup de liaisons.
- **Cadence** : suivre les règles de la 0.4.8 (`docs/perf-pistes.md`). Utiliser
  l'horloge d'ambiance `Ilot.amb` à 25 images/s, mise en pause sans activité.
  L'animation ne doit tourner que pendant une tâche Claude.
- **Emplacement** : dans la pilule, de part et d'autre de l'heure, comme le
  temps d'attente de la file Valorant. Cet état est géré par `Watch.qml` ; il
  faut repérer où la pilule l'affiche avant de commencer : `Pill.qml`,
  `PillClock.qml` ou `Island.qml`, ce n'est pas encore vérifié.

## Côté Claude Code et transport : à faire

- **Hooks** dans `~/.claude/settings.json` :
  - `UserPromptSubmit` : début, on note l'heure ;
  - `Stop` : fin ;
  - en option, `Notification` (Claude attend une réponse). C'est inutile en
    mode skip permissions.

  Le hook reçoit en JSON sur stdin `session_id` et `cwd` : le nom du projet en
  vient.
- **Transport vers l'îlot** : aucun canal n'existe aujourd'hui, et l'appli tourne
  en une seule instance (mutex dans `qt/src/main.cpp`). Proposition :
  `ilot.exe --claude start|stop --session <id>`. Le second processus transmet
  le message par un tube nommé (`\\.\pipe\ilot`) à l'instance en cours, puis
  quitte. Variante plus simple : le hook écrit un fichier surveillé par l'îlot.
- **Plusieurs sessions** : un minuteur par `session_id`. La pilule montre la
  plus ancienne, avec un compteur s'il y en a plusieurs.
- **Réglages** : Réglages › Addons › Claude Code. Options : activer, son,
  durée minimale, et un bouton « Installer les hooks ».
- **Son** : à choisir. Les variantes essayées sont dans la maquette en ligne
  (version 2). La bulle est un sinus de 380 → 950 Hz en 90 ms, avec une montée
  de 8 ms et une extinction en 220 ms. Elle sera à exporter en `.wav`.
