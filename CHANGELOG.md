# Notes de version

Une section `## <version> — <date>` par version, la plus récente en haut.
Ce fichier est embarqué dans l'îlot (Réglages › Mises à jour) et sert de
description à chaque version publiée sur GitHub.

## 0.4.6 — 2026-10-17

- **Valorant** : l'îlot suit vos parties. En file d'attente, la pilule affiche le temps d'attente ; quand une partie est trouvée, une notification apparaît (carillon et îlot qui clignote si vous êtes sur une autre fenêtre, clic pour retourner dans le jeu).
- **Sélection des agents** : le temps restant s'affiche dans la pilule (en rouge dans les 10 dernières secondes si votre agent n'est pas verrouillé) ; au survol, l'agent choisi avec son icône, la carte, le mode et le nombre d'alliés verrouillés. Rappel 15 s avant la fin si vous n'avez pas verrouillé et n'êtes pas dans le jeu.
- Se désactive dans Réglages › Jeu et absence › Valorant.

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
