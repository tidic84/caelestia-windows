# Mémoire de l'îlot : comparaison avec Nusa (2026-10-29)

Suite de `perf-ilot.md` et `perf-pistes.md`, côté RAM. Point de départ :
l'îlot affiche environ 300 Mo dans le Gestionnaire des tâches chez
l'utilisateur. Le 2026-10-19, on mesurait 228 Mo (mémoire privée) au
lancement.

## Nusa

Nusa (https://rama2555.github.io/nusa) est une encoche pour Windows : musique,
paroles, minuteur, étagère de fichiers. Son code n'est pas publié : le dépôt
`rama2555/nusa` ne contient que le site. Son installeur (Inno Setup récent)
n'a pas pu être ouvert ici. Ce qui suit vient donc de son site :

- environ **30 Mo** en usage courant, et **45 Mo** avec 70 fichiers sur
  l'étagère (capture du Gestionnaire des tâches) ;
- « écrit en Rust et dessiné par la carte graphique, sans moteur web » ;
- « ne dessine que quand quelque chose bouge » ; au repos, 0 % de CPU, même
  avec de la musique ;
- « l'étagère retient où sont les fichiers au lieu de les copier en
  mémoire » ;
- 3 Mo à télécharger.

Ce qui s'applique à l'îlot :

| Méthode de Nusa | Îlot |
|---|---|
| Pas de moteur web | Déjà le cas depuis le passage à Qt (WebView2 coûtait ~250 Mo et 7 processus, voir `perf-ilot.md`). |
| Rendu maison en Rust | **Non adapté** : il faudrait réécrire 28 000 lignes de QML. Qt Quick (moteur QML, scene graph D3D11, polices) a un plancher bien plus haut que 30 Mo, et le prototype Qt mesuré le 2026-10-16 pesait déjà 85 Mo pour une petite partie de l'interface. |
| Dessiner seulement quand ça bouge | Déjà fait pour le CPU (horloge d'ambiance coupée au repos, `perf-pistes.md` piste 1). Sans effet sur la RAM. |
| Garder des références plutôt que des contenus | **Pas respecté par l'historique du presse-papiers**, corrigé (plus bas). Ailleurs, c'est déjà le cas : miniatures en cache sur le disque (`img::file_url`), dépôt de fichiers par chemins, pochettes et aperçus dans des files bornées (`img::ART`, `THUMBS`, `CLIPS`). |

## Corrigé : images du presse-papiers

`src/system.rs` (`Clip.image`) gardait les 8 dernières images copiées **en
brut (RGBA)**, pour pouvoir les recopier :

| Capture | Brute | × 8 |
|---|---|---|
| 1920 × 1080 | 8,3 Mo | 66 Mo |
| 2560 × 1440 | 14,7 Mo | 118 Mo |
| 3840 × 2160 | 33,2 Mo | 265 Mo |

Quelques captures d'écran (Win+Maj+S, Impr. écran) suffisaient donc à
expliquer l'écart entre 228 et 300 Mo. Elles restaient jusqu'à ce que
d'autres images les poussent dehors ou qu'on vide l'historique.

L'image est maintenant gardée en **PNG** (sans perte). Elle n'est décodée
que pour la recopier (`clip_copy`). Mesuré sur les captures de `docs/`
(800 × 540, Rust en release, Linux) :

| Image | Brute | PNG | Gain | Encodage | Décodage |
|---|---|---|---|---|---|
| `apps.png` (interface) | 1,7 Mo | 0,06 Mo | × 29 | 0,7 ms | 1,3 ms |
| `accueil.png` | 1,7 Mo | 0,09 Mo | × 19 | 1,3 ms | 1,8 ms |
| `media.png` | 1,7 Mo | 0,13 Mo | × 13 | 1,8 ms | 2,7 ms |
| `fonds.png` (photos) | 1,7 Mo | 0,38 Mo | × 4,6 | 2,4 ms | 3,0 ms |

L'aller-retour rend les mêmes octets. En 4K (×19 en pixels), il faut compter
environ 25 à 50 ms d'encodage, dans le thread du presse-papiers. Une photo
plein écran se compresse moins bien (×2 environ), mais reste plus petite
qu'en brut.

### Mesuré sous Windows (2026-10-29)

Sur le poste, écran 1920 × 1080, avec Valorant ouvert, donc des captures de
jeu, qui se compressent mal. Pour chaque version : îlot lancé seul, 30 s
d'attente, puis 8 captures de l'écran mises dans le presse-papiers par
PowerShell (`Clipboard.SetImage`), une toutes les 3 s. Mesure 10 s après.
Script : `%TEMP%\ilot-mem.ps1` (hors du dépôt).

| Version | Au lancement | Après 8 captures | Écart |
|---|---|---|---|
| Ancienne (0.4.23 installée) | 300,4 Mo | 367,7 Mo | **+67 Mo** (8 × 8,3 Mo) |
| Nouvelle (branche, avec `main`) | 319,2 Mo | 341,5 Mo | **+22 Mo** |

Mémoire privée. Le Gestionnaire des tâches (working set) affiche environ
30 Mo de plus. L'écart au lancement entre les deux versions (19 Mo) vient
d'autre chose : la nouvelle contient les Réglages refaits de `main`, et le
bruit d'une mesure à l'autre est du même ordre. En 1440p ou en 4K, le gain
grandit avec la taille de l'écran.

**Encore inexpliqué** : un `qt\build\ilot.exe` lancé à 13 h 45 était monté
à **449 Mo** vers 14 h 50. Le presse-papiers n'explique pas tout. Une
mesure toutes les 10 min pendant une journée normale dirait ce qui grimpe,
et quand.

## Pistes restantes (non faites, à mesurer d'abord)

Le plancher de 228 Mo au lancement vient presque entièrement de Qt : moteur
QML et objets des pages ouvertes, tas JS, pilote D3D11, polices. Ce n'est
pas mesurable depuis Linux. Par ordre de gain probable :

1. **Une fenêtre Qt = un device D3D11.** Avec la boucle de rendu par thread,
   chaque `Window` affichée au moins une fois garde son propre `QRhi`, ses
   caches de glyphes et ses atlas de textures, même une fois masquée.
   Ce sont : l'îlot, `TipWindow` (dès la première infobulle), `Captions`,
   `PetWindow`, et une `Bar` par écran supplémentaire. Pistes :
   `persistentGraphics: false` et `persistentSceneGraph: false`, puis
   `releaseResources()` quand une fenêtre est masquée ; ou décharger
   `TipWindow` par un `Loader` après quelques secondes sans infobulle. Il
   faut d'abord mesurer : mémoire privée avant et après la première
   infobulle.
2. **Fenêtre repliée trop grande** (`perf-pistes.md` piste 8) : la chaîne
   d'échange fait toute la largeur × 600 px logiques, plus le tampon de
   profondeur. Cela pèse surtout en mémoire GPU.
3. **Pages déchargées** (`Panel.qml`, après 5 min) : on appelle déjà `gc()`.
   On pourrait y ajouter `trimComponentCache()` (types compilés des pages)
   et `releaseResources()` sur la fenêtre (pipelines et images en cache).
   Le gain est probablement faible.
4. **Vider le working set** (`EmptyWorkingSet` après la fermeture du
   panneau) : le chiffre du Gestionnaire des tâches baisserait, mais la
   mémoire n'est pas libérée, elle part dans le fichier d'échange et
   revient par défauts de page. C'est cosmétique, donc déconseillé.

## Méthode de mesure (sous Windows)

Le Gestionnaire des tâches affiche le **working set privé**.
`Get-Process` donne la **mémoire privée** (commit), qui est plus stable
d'une mesure à l'autre :

```powershell
Get-Process ilot | Select-Object @{n="Privée (Mo)";e={[math]::Round($_.PrivateMemorySize64/1MB,1)}}, @{n="Working set (Mo)";e={[math]::Round($_.WorkingSet64/1MB,1)}}
```

Pour le presse-papiers : relever ce chiffre, faire 8 captures
(Win+Maj+S) en attendant 2 s entre chacune, puis relever de nouveau.
Avant ce correctif, chaque capture plein écran ajoutait sa taille brute
(table plus haut). Après, elle ne devrait ajouter que quelques centaines
de Ko.

Pour savoir où part le reste, VMMap (Sysinternals) sépare le tas (Rust et
C++), les « Private Data » (tas JS de QML, pilote graphique) et les DLL.
