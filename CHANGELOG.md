# Notes de version

Une section `## <version> — <date>` par version, la plus récente en haut.
Ce fichier est embarqué dans l'îlot (Réglages › Mises à jour) et sert de
description à chaque version publiée sur GitHub.

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
