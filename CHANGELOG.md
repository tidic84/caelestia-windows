# Notes de version

Une section `## <version> — <date>` par version, la plus récente en haut.
Ce fichier est embarqué dans l'îlot (Réglages › Mises à jour) et sert de
description à chaque version publiée sur GitHub.

## 0.4.25 — 2026-10-30

- **Compagnons en sprites** : l'îlot sait afficher un compagnon animé venu d'un pack personnel (dossier `.ilot\pets`), avec promenade au-dessus de la barre des tâches, attaques animées et buste dans la pilule. Aucun pack n'est fourni avec l'îlot.
- **Réglages › Compagnon** : l'aperçu montre le buste d'un pack en grand, centré.
- **Zekrom livré avec l'îlot** : le pack de compagnon Zekrom est installé avec l'appli (dossier `pets` à côté de `ilot.exe`) et se choisit dans Réglages › Compagnon. Un pack du même nom dans `.ilot\pets` reste prioritaire.
- **Lancement au démarrage plus rapide** : l'îlot démarre maintenant par une tâche planifiée « à l'ouverture de session » au lieu de la clé `Run` de l'Explorateur, qui lançait ses entrées une à une (l'îlot arrivait 2 à 3 min après l'ouverture de session). Il attend la barre des tâches avant de s'afficher. Les installations existantes passent d'elles-mêmes à la tâche au premier lancement ; la clé `Run` reste le repli si le Planificateur refuse la tâche.

## 0.4.24 — 2026-10-29

- **Réglages refaits** :
  - 13 onglets rangés en trois groupes : Personnaliser (Thème, Îlot et pilule, Lecteur, Compagnon), Comportement (Alertes, Barre et écran, Jeu et absence, Son) et Système (Clavier, Météo et agenda, Accessibilité, Addons, Mises à jour) ;
  - une recherche en haut de la liste trouve un réglage par son nom et indique où il était avant (« avant : Apparence ») ; les anciens noms d'onglets (Général, Apparence, Pilule, Raccourcis) trouvent aussi ce qu'ils contenaient.
- **Enregistrer ou annuler** : un réglage changé ne s'applique plus tout de suite.
  - Une barre en bas compte les modifications, avec Annuler et Enregistrer (ou Ctrl+S).
  - Un clic sur le nombre liste les changements (avant → après) et mène à leur onglet.
  - Un point orange marque chaque réglage modifié et son onglet.
  - Tant qu'il reste des modifications, l'îlot ne quitte pas Réglages : la barre tremble et rougit.
  - Les actions restent immédiates (sorties audio, ville, agendas, addons, raccourcis, écran, démarrage, Exporter, Tester…). Pour la touche Windows, l'invite administrateur s'ouvre à l'enregistrement.
- **Aperçus animés** en haut des onglets Thème, Îlot et pilule, Lecteur et Alertes : ils montrent les changements avant qu'on les enregistre (couleurs, forme, contour, horloge, vitesse des animations, bouton et barre du lecteur, alertes). L'îlot tel qu'il est enregistré reste visible à côté (« Ton îlot »). Le compagnon de l'onglet Compagnon porte aussi les changements.
- **Thèmes prêts refaits** : 13 thèmes en cartes, avec un aperçu de la pilule et des couleurs. Ardoise (gris-bleu opaque), Brume (gris-bleu sur acrylique) et OLED sont nouveaux, ainsi qu'Aurore, Papier et Bonbon ; Minuit, Néon, Coucher de soleil, Forêt, Glace, Rétro et Monochrome sont revus. Ils règlent aussi l'horloge et les animations. Après une retouche, « Thème perso, d'après X » propose de revenir au thème.
- **Cartes noires (OLED)** (Réglages › Îlot et pilule) : en mode sombre, le fond devient noir pur et les cartes presque noires.
- **Moins de mémoire** : l'îlot prend environ 75 Mo de moins au lancement (icônes des applis demandées à 48 px, ce qui évite le grand cache d'icônes de Windows). Les images de l'historique du presse-papiers sont gardées compressées : une capture d'écran n'y pèse plus 8 à 33 Mo.
- **Réglages plus rapides à ouvrir** : la page ne fait plus recalculer tout l'îlot à chaque ouverture, et chaque onglet n'est créé qu'à sa première visite.
- **Outils Windows dans Apps** : le lanceur propose aussi le Gestionnaire de périphériques, les Outils Windows (Gestion de l'ordinateur, Observateur d'événements, Planificateur de tâches, Éditeur du Registre…), tous les éléments du Panneau de configuration (Son, Options d'alimentation, Programmes et fonctionnalités, Réseau…), la Gestion des disques, les Connexions réseau, Windows Update et d'autres outils de Windows.

## 0.4.23 — 2026-10-28

- **Survol et clics plus justes** :
  - un clic sur le titre, la marge ou un séparateur d'un menu contextuel (Apps, Tâches) n'atteint plus ce qu'il y a dessous ;
  - la vue du jour (Accueil) et le panneau Playlists (Média) ne laissent plus passer le survol ni les clics vers ce qu'ils couvrent ;
  - le curseur reste une flèche sur les boutons, interrupteurs et curseurs désactivés ;
  - une ligne garde son survol quand la souris passe sur son propre bouton (Presse-papiers, bloc-notes, aperçu des fenêtres de la barre) ;
  - menu latéral des Réglages, pastilles de couleur, notes de version et boutons de raccourci : un léger fond au survol ;
  - les boutons Précédent / Suivant grisés de l'Accueil ne réagissent plus ;
  - les infobulles des boutons au bord de l'écran restent dans l'écran.
- **Soundboard** : Renommer, Volume, Couleur et Supprimer (clic droit sur un son) fonctionnent de nouveau.
- **Wi-Fi** : le mot de passe en cours de saisie ne s'efface plus quand la recherche des réseaux se termine.
- **Aperçu des fenêtres** (barre) : il ne saute plus au bord gauche et ne se ferme plus quand le titre d'une fenêtre change, et il ne passe plus sous l'îlot.
- **Détails visuels** : les tuiles de Contrôles et la progression des sons respectent les coins arrondis ; l'icône Actualiser finit son tour au lieu de rester penchée ; le cadre de sélection au clavier des jeux se voit ; les icônes du Launcher rétrécissent à l'appui ; la barre de défilement reste dans son cadre en bas des longues listes ; dans le mélangeur, le cadre de focus n'apparaît plus qu'au clavier ; la page arrivante glisse toujours du bon côté ; la pilule ne grandit plus en boucle quand la souris est sur son bord.
- **Thème clair** : chiffres des cases chargées de l'onglet Tâches, couleurs des sorties du mélangeur et légende d'Usage Claude lisibles. L'infobulle « Processus Windows protégé » s'affiche.
- **Assistant** : les puces de prompts rapides au-dessus de la saisie sont retirées.
- **Quick Share** : les téléphones récents qui se disent visibles sans envoyer leur nom apparaissent de nouveau (sous leur nom réseau).

## 0.4.22 — 2026-10-27

- **Glisser des fichiers sur l'îlot** : la pilule s'agrandit et ne montre plus que des zones de dépôt (Convertir, Réduire pour les images, Zip, Discord, Quick Share, Applis), sans le panneau ni les onglets. Lâcher sur une zone lance l'action, et le résultat s'affiche dans la pilule (afficher dans l'Explorateur, ouvrir, envoyer sur Discord). Survoler « Applis » ouvre l'onglet Apps pour ranger les fichiers dans un dossier. Ressortir sans lâcher replie l'îlot.
- **Conversion de fichiers**, à la manière de Convertio : la zone « Convertir » ouvre une page avec une ligne par fichier. Pour chacun, on choisit un format : image (PNG, JPG, WEBP, BMP, GIF), audio (MP3, WAV, FLAC, OGG, M4A, OPUS) ou vidéo (MP4, MKV, WEBM, AVI, MOV, GIF). Une vidéo peut aussi donner son audio. « Tout convertir en… » règle tous les fichiers d'un coup. Les fichiers convertis sont créés à côté des originaux. L'audio et la vidéo demandent ffmpeg (`winget install ffmpeg`).
- **Launcher et Jeux remis à l'endroit** (onglet Apps) : la puce des jeux détectés (Steam, Epic, Ubisoft, GOG) s'appelle maintenant « Jeux », et le dossier des launchers « Launcher ». Au premier lancement, l'ancien dossier « Jeux » est renommé et trié : Steam, Epic, GOG, Ubisoft, Rockstar, Xbox, Riot Client ou CurseForge y restent ; Minecraft, Valorant, Roblox, Lunar Client ou Genshin Impact passent dans la puce « Jeux ».
- **Dossiers** : « Supprimer le dossier » et « Renommer » (clic droit sur un dossier) fonctionnent de nouveau.
- **Nouvelles commandes** (taper `>` dans la recherche) : volume à N % (`>volume 30`), couper ou rétablir le son, lecture / pause, piste suivante ou précédente, ouvrir un onglet (Accueil, Média, Presse-papiers…), Corbeille, Téléchargements, dossier des fonds d'écran, Gestionnaire des tâches de Windows, actualiser les applications et les jeux, rechercher une mise à jour.
- **Paroles dans la pilule** (Réglages › Apparence › Lecteur dans la pilule) : la ligne chantée s'affiche directement dans l'îlot fermé, à côté du disque, dans le style des paroles de l'onglet Média, sur un halo de la couleur de la pochette. La pilule s'élargit à chaque ligne ; l'heure et les icônes s'effacent le temps des paroles et reviennent pendant les silences et la pause. Désactivé par défaut.
- **Réglages › Apparence plus lisibles** : la page est découpée en cartes (Couleurs, Îlot, changement de fond, puis une carte par partie du lecteur : bouton, barre de progression, pilule, onglet Média), avec de l'espace entre les groupes. Les titres disent ce qu'ils règlent : « Clair ou sombre » au lieu de « Thème », « Style de la palette » pour la grille des variantes, « Forme du bouton », « Forme de la pochette »… Les réglages eux-mêmes ne changent pas.
- **Presse-papiers au clavier (Win+V)** : dans l'historique, les flèches haut et bas choisissent un élément et Entrée le valide. Valider, au clavier ou d'un clic, copie l'élément et referme l'îlot : il ne reste qu'à coller avec Ctrl+V dans l'appli d'avant.
- **Animations plus fluides** :
  - à l'ouverture, le contenu attend que l'îlot ait grandi au lieu d'apparaître rogné ; à la fermeture, il s'efface avant que l'îlot se rétracte ;
  - l'îlot ne recalcule plus sa zone cliquable à chaque image de l'animation ;
  - le compagnon en promenade, l'aurore boréale et les contours animés suivent la fréquence de l'écran (25 images/s quand l'îlot est replié, pour rester léger) ;
  - volume, luminosité, Bluetooth : l'icône rebondit à l'arrivée et la barre se remplit avec le chiffre qui compte ;
  - glisser un fichier sur l'onglet Apps : la zone réagit et une étiquette indique ce que fera le dépôt (ranger dans un dossier ou choisir une action).
- **Correctifs** : des icônes s'affichaient en texte (« Bouton lecture » dans Réglages › Apparence, la pastille « Prêt » de Valorant, les processus suspendus ou figés de l'onglet Tâches). Échap referme de nouveau l'îlot après un changement d'onglet quand un champ avait le clavier. Deux réglages changés coup sur coup ne peuvent plus faire revenir l'un d'eux à l'ancienne valeur.
- **Mises à jour signées** : l'îlot n'installe plus une mise à jour que si son archive porte une signature valide, faite sur le poste de l'auteur. Un compte GitHub piraté ne suffit plus à faire installer une fausse version.

- **Îlot en plein écran** (Réglages › Jeu et absence) : quatre modes. « Normal » masque l'îlot dès qu'une appli passe en plein écran, comme avant. « Toujours affiché » le garde par-dessus les jeux et les vidéos. « Masquer auto » le masque, puis le fait revenir quand la souris touche le haut de l'écran, au milieu. « Personnalisé » ne le masque que devant les applis choisies, en plein écran ou en fenêtre agrandie (pratique pour les jeux en fenêtre sans bordure). Les applis déjà vues en plein écran et les fenêtres ouvertes sont proposées, et on peut aussi taper le nom d'un exécutable. Dans tous les cas, la barre, les notifications et le compagnon restent masqués en plein écran. Devant une appli en plein écran (ou un jeu en fenêtre sans bordure), l'îlot ne prend plus jamais le focus : un clic dessus laisse le jeu au premier plan, sans le réduire. L'îlot n'a alors pas le clavier, et il se replie dès que la souris le quitte.

## 0.4.21 — 2026-10-26

- **Bluetooth** (Contrôles, chevron de la tuile Bluetooth) : la liste des appareils appairés, avec leur état. Un clic connecte ou déconnecte un casque ou une enceinte ; la corbeille (deux clics) oublie un appareil. En dessous, les appareils à proximité : un clic les appaire, avec le code à confirmer ou à saisir directement dans l'îlot.
- **Paroles des vidéos YouTube** : l'onglet Média trouve maintenant les paroles d'un clip lu dans le navigateur. L'îlot remet en ordre les titres de vidéo (« Artiste - Titre (Clip officiel) », chaînes « …VEVO » ou « … - Topic », titres japonais « 【Ado】Raven Sky » ou « Leina 「誓い」 Music Video ») et accepte un clip plus long que le morceau (intro, fin). Ailleurs, rien ne change.

## 0.4.20 — 2026-10-25

- **Choisir ses sorties audio** (nouvel onglet Réglages › Son) : avec Voicemeeter, VB-Cable, Sonar et compagnie, la liste des sorties déborde. Un interrupteur par sortie, rangées en « Appareils » et « Virtuelles », décide de celles qui apparaissent dans « Sortie audio » et dans le mélangeur. Rien n'est masqué tout seul, et la sortie par défaut reste toujours visible. « +N » du mélangeur montre les sorties masquées, avec un point si une appli y joue.
- **Renommer une sortie** (crayon) : « CABLE Input » peut devenir « OBS », « LG ULTRAGEAR 2 » devenir « Écran droit ». Le nom s'affiche dans « Sortie audio » et dans le mélangeur.
- **Accès rapide** : l'icône en haut de la feuille « Sortie audio » et la ligne « N sorties masquées » mènent aux réglages. Avec au moins 3 sorties virtuelles, la feuille le propose, jusqu'à ce que tu choisisses ou que tu refuses.
- **Noms plus propres** dans le mélangeur : « Speakers (Realtek(R) Audio) » s'affiche « Speakers » (au lieu de « Speakers Audio) »).

## 0.4.19 — 2026-10-25

- **Nouveau mélangeur** (Contrôles) : il montre les applis de toutes les sorties audio, pas seulement de la sortie par défaut. Pratique avec SteelSeries Sonar : Game, Chat, Media et Aux ont chacun leur pastille et leur couleur. Seul l'essentiel est affiché (canaux Sonar, sortie par défaut, sorties où une appli joue) ; « +N » montre les autres.
- **Volume par sortie** : chaque pastille se règle à la molette ou en glissant, et se remplit selon le volume.
- **Changer la sortie d'une appli** : clic sur son point coloré puis choix de la sortie, ou glisser sa poignée sur une pastille. Windows retient ce choix ; certaines applis doivent être relancées pour basculer.
- **Filtre** : un clic sur une ou plusieurs pastilles ne montre que ces sorties ; Échap réaffiche tout. Les groupes se replient, leur titre reste en haut pendant le défilement.
- **Retirés** : les préréglages de volume « Jeu » et « Chill », et leur application au lancement d'un jeu.

## 0.4.18 — 2026-10-24

- **Onglet Média** : les coins du fond « pochette floutée » ne dépassent plus de l'arrondi.
- **Nouveaux réglages du lecteur** (Réglages › Apparence › Lecteur) : forme du bouton lecture (festonné, rond, icône seule), sa couleur (auto, couleur du lecteur, blanc, couleur fixe), couleur de l'icône, rotation / changement de forme / rebond / ombre activables ; épaisseur et amplitude de la barre de progression ; pochette ronde et spectre activables séparément ; flou, dérive et assombrissement du fond ; anneau et rotation du disque de la pilule repliée. Les valeurs par défaut gardent le lecteur de la 0.4.16.
- **Plus léger** : le spectre coupé arrête aussi la capture du son.
- **Correctifs** : survol des boutons pleins (Theme.lift rendait une couleur transparente : ils sont maintenant éclaircis au survol), boucle de liaison au survol de l'îlot (overIsland).

## 0.4.17 — 2026-10-24

- **Nouvel addon « Claude »** (Réglages › Addons) : les limites de ton abonnement Claude, comme `/usage` dans Claude Code. Session de 5 h et semaine (plus Opus / Sonnet si ton compte en a), avec le temps avant la remise à zéro. Utilise la connexion de Claude Code, rien à saisir.
- **Prévision** : à ton rythme actuel, combien tu auras utilisé à la remise à zéro, ou à quelle heure tu atteindras la limite. Graphique façon Agent Burn : relevés, prévision et rythme régulier sur toute la session ou la semaine. L'historique se remplit au fil des relevés (toutes les 5 min tant que l'addon est activé).
- **Claude Code dans WSL** : le bouton « Installer » des hooks (Réglages › Addons › Claude Code) les ajoute aussi dans les distributions WSL où Claude Code est installé. L'animation de la pilule marche donc aussi quand Claude tourne dans WSL.
- **Assistant de jeu** : plus de minuteur « en attente » dès qu'on quitte le jeu (Apex notamment), puisque l'îlot ne peut pas savoir si une recherche est lancée. L'alerte « Partie trouvée » ne se déclenche plus sur un simple chargement du jeu, seulement quand le jeu fait clignoter sa fenêtre. Valorant garde son vrai temps de file.

## 0.4.16 — 2026-10-23

- **Nouveau lecteur de musique**, inspiré de Swiftify : barre de progression ondulée qui s'anime pendant la lecture, bouton lecture festonné qui tourne, couleurs tirées de la pochette.
- **Survol de la pilule** : précédent, lecture / pause et suivant, et une barre qu'on clique ou fait glisser pour se déplacer dans le morceau (avec le temps sous le curseur), sans ouvrir le panneau. L'îlot ne se replie pas pendant qu'on glisse.
- **Pilule repliée** : la pochette qui tourne est entourée d'un anneau qui se remplit avec le morceau ; les petites barres d'égaliseur disparaissent.
- **Onglet Média** : pochette festonnée entourée d'un spectre qui suit la musique, halo de ses couleurs, pochette réduite et assombrie en pause, fond coloré qui dérive, titre qui défile, paroles à droite avec la ligne chantée mise en avant, boutons « Paroles » et « Playlists ».
- **Accueil** : nouvelle carte musique, avec la pochette, le titre, les commandes et la barre de progression.
- **Réglages › Apparence › Lecteur de musique** : couleur du lecteur (pochette, thème ou couleur au choix), barre ondulée ou plate, bouton festonné ou rond, bouton de l'onglet Média blanc ou en couleur, pochette festonnée ou arrondie, disposition en colonne ou côte à côte, glisser la pochette pour changer de titre, et molette sur la pilule qui règle le volume de l'appli qui joue (Spotify…) au lieu du volume général.
- **Plus fiable** : si une appli refuse le déplacement dans le morceau, la barre revient à la vraie position ; précédent, suivant et la barre se grisent quand l'appli ne les permet pas.
- **Plus léger** : la capture du son pour le visualiseur ne tourne plus quand rien ne l'affiche.

## 0.4.15 — 2026-10-20

- **Gestionnaire des tâches, regroupé comme Windows** : chaque hôte de service a sa ligne (« Hôte de service : Audio Windows », « … +2 »), avec la liste de ses services quand on la déplie. Les applis du Store forment une ligne par paquet (Spotify et son lanceur ensemble). Un programme ne regroupe plus que ses propres processus : les assistants lancés par lui (EpicWebHelper, Claude Code sous PowerShell…) ont leur ligne, comme dans Windows.
- **Statuts** : une icône signale un programme suspendu, qui ne répond pas, ou en mode efficacité.
- **Interruptions système** : nouvelle ligne, comme dans Windows ; la somme des lignes rejoint le total du CPU.
- **Chiffres** : le CPU (îlot, barre, accueil, gestionnaire) est le même que celui du Gestionnaire des tâches de Windows, rafraîchi chaque seconde ; le disque des programmes ne dépasse plus le débit réel du disque.
- **Détail d'un programme** : chaque processus a sa propre icône, et « Ouvrir l'emplacement » ouvre le bon fichier. Un second clic sur une colonne inverse le tri.

## 0.4.14 — 2026-10-20

- **Barre, clic droit sur une appli** : menu avec « Nouvelle fenêtre » et « Fermer la fenêtre » (ou « Fermer les N fenêtres »). Il reste affiché tant que la souris est sur lui ou sur la barre.
- **Barre, aperçu des fenêtres** : il ne se ferme plus quand on descend vite de l'icône vers lui.
- **Assistant de jeu** : l'alerte « Partie trouvée » ne se déclenche plus au lancement du jeu, seulement quand on attend hors du jeu. Le son est maintenant le petit « pop » de Claude Code, au lieu des bips.

## 0.4.13 — 2026-10-19

- **Survol et infobulles dans le panneau** : les boutons du panneau ouvert (Verrouiller, Veille, Déconnexion, Redémarrer, Éteindre, onglets, commandes…) réagissent de nouveau au survol de la souris (surbrillance) et affichent leur infobulle. Une zone invisible au-dessus de l'îlot leur prenait le survol.
- **Infobulles bloquées** : une infobulle ne peut plus rester affichée après la fermeture du panneau.

## 0.4.12 — 2026-10-18

- **Infobulles** : tous les boutons sans texte en ont une (calendrier, retour et fermeture des panneaux, lecture / pause, précédent / suivant, minuteur, volume, connexion Wi-Fi…).
- **Barre** : survoler une icône des applications en arrière-plan n'ouvre plus l'infobulle propre à certaines applis, qui restait ensuite affichée sans jamais disparaître. L'îlot affiche toujours le nom de l'appli.
- **Plus léger** : le visualiseur de l'onglet Média est dessiné en une seule passe par la carte graphique ; la couleur du thème tirée du fond d'écran ou de la pochette est calculée par le cœur de l'îlot, sans second moteur JavaScript ; les images sont décodées directement à leur taille d'affichage ; les pages rarement ouvertes (Réglages, Fonds, Tâches…) sont libérées après 5 minutes de panneau fermé ; Verr. Maj n'est plus relue en boucle quand l'îlot est sur la touche Windows ; cœur compilé pour la vitesse.

## 0.4.11 — 2026-10-18

- **Gestionnaire des tâches, chiffres justes** : CPU, mémoire et disque sont lus comme le fait le Gestionnaire des tâches de Windows, pour tous les processus. Les services qui affichaient 0 % (svchost, bases de données, indexation…) ont maintenant leurs vrais chiffres, et la mémoire n'est plus surévaluée. Plus de débits disque absurdes à l'ouverture de l'onglet. Le débit réseau total ne compte plus deux fois le trafic des cartes virtuelles (WSL, Hyper-V).
- **Détail d'un programme** : un clic sur un programme qui a plusieurs processus (« Chrome (30) ») affiche un processus par ligne, avec son PID, le titre de sa fenêtre, ses chiffres et sa propre fin de tâche. Le processus principal est signalé (« principal », confirmation « Tout fermer ? ») : le terminer ferme en général tout le programme.
- **Clic droit sur un programme** : menu avec « Fin de tâche », « Ouvrir l’emplacement du fichier » et « Rechercher en ligne ». Un clic sur l'en-tête d'une colonne (CPU, Mémoire, Disque, GPU, Réseau, Programme) trie la liste.
- **Plus fluide** : la liste ne remonte plus en haut toutes les 2 s, les lignes sont mises à jour sur place au lieu d'être recréées, et l'ordre ne saute plus entre deux rafraîchissements. Onglet fermé, plus rien n'est gardé en mémoire.
- **Fin de tâche** plus rapide (plus de lancement de `taskkill`), avec le nombre de processus concernés et un message si Windows refuse (programme lancé en administrateur). Échap vide le filtre ; « Aucun résultat » quand le filtre ne trouve rien ; nombres avec une virgule.
- **Noms de programmes** : certains noms s'affichaient avec des caractères parasites (« Spotify\b8…FileV » au lieu de « Spotify »). Corrigé dans le gestionnaire des tâches et partout où l'îlot lit le nom d'un programme.

## 0.4.10 — 2026-10-18

- **Claude Code dans l'îlot** : pendant que Claude travaille, une petite animation orange (quatre points en orbite qui fusionnent en étoile, puis se séparent) s'affiche à gauche de l'heure, avec le temps écoulé à droite. Quand il a fini, l'animation s'efface et un petit « pop » retentit si la tâche a duré au moins 30 s. Ça marche pour toutes les sessions Claude Code, quel que soit le dossier.
- À activer dans Réglages › Addons › Claude Code : bouton « Installer » (ajoute les hooks dans `~/.claude/settings.json` sans toucher au reste, avec une copie de sauvegarde), son, durée minimale et bouton « Tester » pour écouter le son. Les terminaux Claude Code déjà ouverts sont à relancer une fois.
- **Stabilité** : deux plantages corrigés, retrouvés dans les rapports de Windows. L'îlot pouvait planter en se fermant ou en se rechargeant (réglage reçu pendant la fermeture), et en sortie de veille ou au rebranchement d'un écran (bug de Qt dans la synchronisation de l'affichage).

## 0.4.9 — 2026-10-17

- **Confidentialité** : les copies marquées privées par l'application (mots de passe copiés depuis KeePass, Bitwarden ou un autre gestionnaire) n'apparaissent plus dans l'historique du presse-papiers, comme dans celui de Windows.
- **Mémoire** : les pochettes, jaquettes et fonds d'écran sont réduits à leur taille d'affichage au lieu d'être gardés en pleine résolution.
- **Stabilité** : quitter ou relancer l'îlot pendant une opération en cours (recherche Wi-Fi, mail…) ne peut plus le faire planter.
- Inclut la **0.4.8**, qui n'a pas été publiée séparément : îlot beaucoup plus léger au repos (animations d'ambiance à 25 images/s et en pause sans activité ou en plein écran, volume, luminosité, presse-papiers, caméra / micro et thème suivis par les notifications de Windows au lieu d'être relus en boucle, GPU NVIDIA lu directement par le pilote, pochettes en mémoire limitée).

## 0.4.8 — 2026-10-17

- **Plus léger au repos** : les animations d'ambiance (compagnon, météo animée, aurore boréale, contour RGB ou pulsé, horloge néon) tournent à 25 images/s au lieu de suivre la fréquence de l'écran (jusqu'à 240 images/s), et s'arrêtent après une minute sans clavier ni souris ou pendant un jeu en plein écran. La promenade du compagnon et le clignotement « partie trouvée » continuent, eux.
- **Moins de travail en arrière-plan** : température et charge du GPU NVIDIA lues directement par le pilote (plus de `nvidia-smi` lancé toutes les 3 s) ; volume, luminosité, presse-papiers, voyant caméra / micro et thème de Windows suivis par les notifications de Windows au lieu d'être relus plusieurs fois par seconde ; notifications, manifestes Steam et espace des disques relus seulement quand ils changent ou quand ils s'affichent.
- **Mémoire** : les pochettes des morceaux écoutés ne s'accumulent plus (seules les dernières sont gardées).
- Discord : la connexion n'est surveillée en continu que pendant un appel vocal.

## 0.4.7 — 2026-10-17

- **Compagnon** entièrement redessiné : le chat (oreilles, moustaches, queue qui remue) et le fantôme (jupe ondulée, petits bras, il flotte) sont refaits, et sept espèces arrivent : lapin, grenouille, pingouin, poussin, robot (bouche en égaliseur sur la musique), axolotl et champignon.
- **Expressions et tours** : yeux heureux, en cœur, étourdis, clin d'œil… et plus de vingt tours (salto, pirouette, coucou, étirement, bâillement, éternuement, danse, langue tirée, il fond comme une gelée). Il réagit à ce qui se passe : salto quand une partie est trouvée, danse quand la musique démarre, coucou à ton retour, frissons quand il gèle.
- **Interactions** : au survol de la pilule, il apparaît à côté de l'heure et te suit des yeux. Clic : un tour ; double clic : salto ; appui long : il se fait caresser. Trop de clics d'affilée et la tête lui tourne. Chaque caresse le rend plus attaché (niveaux 1 à 10).
- **Promenade** : il arrive en parachute, par un portail ou en courant, puis s'occupe : balade, sieste avec bonnet de nuit, ballon de plage, papillon qui se pose sur sa tête, ballon gonflable qui éclate, pêche, skate, bulles de savon, lecture, avion en papier, jardinage (les fleurs restent), cache-cache, méditation, danse avec projecteurs (musique), étoiles filantes (le soir), café (le matin), parapluie sous son petit nuage (pluie), bonhomme de neige (neige) et un tour propre à son espèce (le blob se divise, le chat chasse un point laser, la grenouille attrape une mouche…).
- **Réglages › Compagnon** : nouvel onglet avec un aperçu à caresser, nourrir et faire jouer ; nom, couleur (naturelle, thème ou au choix), yeux, chapeau (couronne, sorcier, auréole…), visage (lunettes, monocle, masque…), cou (nœud papillon, écharpe, grelot…), délai et taille de la promenade, traînée (étincelles, cœurs, fleurs, arc-en-ciel…) et un bouton pour voir chaque scène tout de suite.
- **Masqué**, le compagnon est entièrement retiré : plus aucun dessin, minuterie ni fenêtre de promenade. Même allumé, la fenêtre de promenade n'est chargée que pendant qu'il est dehors.

## 0.4.6 — 2026-10-17

- **Valorant** : l'îlot suit vos parties. En file d'attente, la pilule affiche le temps d'attente ; quand une partie est trouvée, une notification apparaît (carillon et îlot qui clignote si vous êtes sur une autre fenêtre, clic pour retourner dans le jeu).
- **Sélection des agents** : le temps restant s'affiche dans la pilule (en rouge dans les 10 dernières secondes si votre agent n'est pas verrouillé) ; au survol, l'agent choisi avec son icône, la carte, le mode et le nombre d'alliés verrouillés. Rappel 15 s avant la fin si vous n'avez pas verrouillé et n'êtes pas dans le jeu.
- Se désactive dans Réglages › Jeu et absence › Valorant.
- **Barre** : nouvelle option « Titre de la fenêtre active » (Réglages › Barre) ; coupée, la fenêtre au premier plan n'affiche plus que son icône, sans son nom.

## 0.4.5 — 2026-10-17

- **Lanceur** : la recherche apprend vos habitudes. Les applications lancées souvent, récemment ou d'habitude à cette heure-ci passent devant, ainsi que celle choisie la dernière fois pour les mêmes lettres (si vous tapez « d » puis lancez Discord, Discord revient en tête).
- Recherche plus souple : les initiales (« vsc » pour Visual Studio Code) et les lettres dans l'ordre (« ntpd » pour Notepad++) sont acceptées.
- Nouveau tri « Les plus utilisées » ; la commande `>oublier` efface les habitudes du lanceur.

## 0.4.4 — 2026-10-17

- **Bloc-notes** : plusieurs notes (liste à gauche, nouvelle note, suppression en deux clics), mise en forme **Markdown** (titres, gras, italique, listes, cases à cocher, citations, code, liens) avec une barre d'outils, Ctrl+B / Ctrl+I et un aperçu ; un interrupteur repasse en texte brut. L'ancien bloc-notes devient la première note.
- **Raccourcis d'applications** : dans Réglages › Raccourcis, une combinaison ouvre l'application de votre choix, par exemple Win+T pour le Terminal. Les combinaisons avec la touche Windows passent avant celles de Windows.
- **Assistant** : la Traduction ou Claude se désactive dans Réglages › Addons.
- Contour **néon** (et les autres contours) : il suit maintenant les coins arrondis qui relient l'îlot au haut de l'écran, lueur comprise.

## 0.4.3 — 2026-10-17

- **Quick Share** : le vrai partage de Google des téléphones Android remplace le partage par QR code. Bouton en haut à gauche du panneau (ou glisser des fichiers sur l'îlot) : appareils à proximité, envoi de fichiers, de texte ou de liens, QR code à scanner avec le téléphone, progression et annulation.
- Réception : demande à accepter ou refuser dans la pilule, avec le code de vérification ; fichiers dans Téléchargements, texte dans le presse-papiers, liens et mots de passe Wi-Fi.
- Nom du PC et visibilité (visible, 10 minutes, masqué). PC et téléphone sur le même Wi-Fi ; Windows demande d'autoriser l'îlot dans le pare-feu au premier lancement.

## 0.4.2 — 2026-10-17

- Réglages : en changeant d'onglet, le fond de l'onglet précédent s'efface bien (un seul fond, qui glisse vers l'onglet choisi).

## 0.4.1 — 2026-10-17

- Météo : le choix d'une ville est de nouveau enregistré.
- Média : visualiseur en miroir, dégradé par barre.

## 0.4.0 — 2026-10-16

- **Mises à jour automatiques** : l'îlot cherche une nouvelle version au démarrage puis toutes les 6 h. Au choix dans Réglages › Mises à jour : la télécharger et l'installer tout seul (quand vous ne faites rien, ou au lancement suivant), seulement prévenir, ou ne rien vérifier.
- **Notes de version** : ce qui a changé dans chaque version, dans Réglages › Mises à jour ; après une mise à jour, la pilule propose de les lire.
- **Addons** : seuls les onglets essentiels restent (Accueil, Média, Contrôles, Apps, Réglages). Mail, PC, Soundboard, Tâches, Presse-papiers, Assistant et Fonds deviennent des addons à activer dans Réglages › Addons. Un addon désactivé ne tourne plus en arrière-plan (relevé des mails, état des services, soundboard).
- **Réglages en onglets** : Général, Barre, Apparence, Pilule, Jeu, Accessibilité, Météo et agenda, Raccourcis, Addons, Mises à jour.
- Avec peu d'onglets, chacun garde son nom dans le panneau.

## 0.3.1 — 2026-10-16

- Média : paroles synchronisées et visualiseur repris de la branche de Romain.

## 0.3.0 — 2026-10-16

- Onglet PC : Discord, état des services, santé du PC, extinction programmée, logiciels du PC, convertisseur de sensibilité.
- Mail (IMAP, connexion Google), Launcher de jeux, Soundboard, sous-titres en direct, compagnon de la pilule, accessibilité.

## 0.2.2 — 2026-10-16

- Fond acrylique : vrai flou de ce qu'il y a derrière l'îlot et la barre.

## 0.2.1 — 2026-10-16

- Barre : applications en arrière-plan (zone de notification).

## 0.2.0 — 2026-10-16

- Nouvelle interface en Qt Quick / QML, plus légère que l'ancienne interface web.

## 0.1.3 — 2026-10-16

- Barre sur les autres écrans, barre des tâches Windows masquée sur tous les écrans.

## 0.1.2 — 2026-10-16

- Bouton pour quitter l'îlot (second clic pour confirmer), commande `>quitter` du lanceur.

## 0.1.1 — 2026-10-15

- Onglets compacts : seul l'onglet actif garde son nom.
