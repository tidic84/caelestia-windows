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

## Où partent les ~295 Mo au lancement (mesuré le 2026-10-29)

Poste : 2 écrans 1920 × 1080, carte NVIDIA, 530 applis dans le menu
Démarrer. L'îlot installé, 45 s après son lancement :

- 297 Mo de mémoire privée (engagée) ;
- **193 Mo de working set privé** : c'est la colonne « Mémoire » du
  Gestionnaire des tâches ;
- 175 threads.

Méthode : répartition des régions privées par `VirtualQueryEx` (sorte de
VMMap maison), copie des grosses régions pour voir leur contenu, puis
variantes de lancement (variables d'environnement, barre coupée) et petits
programmes isolés pour chiffrer chaque poste. Les scripts sont dans
`%TEMP%` (`ilot-vm.ps1`, `ilot-var.ps1`, `ilot-dump.ps1`, `d3dcost\`).

| Poste | Coût mesuré | Comment on le sait |
|---|---|---|
| Icônes des applis (liste « jumbo » du shell) | **~80 Mo** | Un bloc unique de 80 Mo, rempli d'icônes 256 × 256 BGRA. Un programme seul qui demande les 530 icônes à 64 px garde +94 Mo, contre +14 Mo à 48 px. |
| Pilote NVIDIA, premier device D3D11 | ~50 Mo, ~20 threads | Programme seul : 4 → 55 Mo pour un device. En rendu logiciel, l'îlot passe de 297 à 213 Mo et de 170 à 77 threads. |
| Barre du second écran (2e fenêtre Qt) | ~40 Mo, ~40 threads | Barre coupée : 253 Mo, 129 threads. Programme seul : +15 Mo et +20 threads par device supplémentaire, le reste vient de Qt (rendu, caches). |
| NVML (`nvml.dll`, température et charge du GPU) | ~19 Mo | `nvmlInit` seul : +19 Mo, non rendus par `nvmlShutdown` ni `FreeLibrary`. Dans l'îlot : 18,5 Mo de pages écrites dans `nvml.dll`. |
| PDH (compteurs du CPU, comme le Gestionnaire) | ~7 Mo | La première requête charge les tables des noms et des aides (+6,6 Mo). Les suivantes ne coûtent presque rien. |
| Piles des 170 threads | ~5 Mo | Les régions avec page de garde. |
| Reste : tas Rust, Qt, QML, shell, polices | ~90 Mo | Plusieurs segments de tas de 15 à 23 Mo, dont deux presque vides (pages engagées à zéro, hors working set). |

Ce qui ne marche pas :

- **Autres moteurs de rendu de Qt** : OpenGL 516 Mo, Vulkan 611 Mo, D3D12
  629 Mo. D3D11, utilisé aujourd'hui, est de loin le plus léger.
- **`D3D11_CREATE_DEVICE_PREVENT_INTERNAL_THREADING_OPTIMIZATIONS`** : 21
  threads au lieu de 23 par device, et la même mémoire.
- **Rendu logiciel** (`QT_QUICK_BACKEND=software`, 213 Mo, ou WARP,
  223 Mo) : le dessin passe sur le processeur, et `MultiEffect` et les
  `ShaderEffect` ne marchent pas en mode `software`. À écarter.
- **Boucle de rendu `basic`** : 290 Mo, pas de gain seule.

## Pistes, par gain

1. **Icônes à 48 px au lieu de 64** (`apps.rs`, `icon_of`) : **−80 Mo**.
   Au-delà de 48 px, `IShellItemImageFactory` passe par la liste jumbo du
   shell (256 × 256 par icône, gardée tant que le processus vit). Les
   icônes de l'onglet Apps s'affichent à 40 px × DPI : à 100 % (le poste),
   48 px suffisent. À 150 %, il en faudrait 60 et l'icône serait un peu
   floue. Variantes qui gardent la qualité :
   - extraire les icônes dans un processus à part (`ilot.exe --apps`, par
     `ilot_cli`) qui écrit les PNG dans le cache disque puis se ferme ;
   - garder les icônes en cache disque par appli, pour ne rappeler le shell
     que pour les nouvelles applis.
2. **NVML remplacé** (`activity.rs`) : **−19 Mo**. La température vient de
   `D3DKMTQueryAdapterInfo(KMTQAITYPE_ADAPTERPERFDATA)`, que le
   Gestionnaire des tâches utilise aussi, et la charge du compteur PDH
   `\GPU Engine(*engtype_3D)\Utilization Percentage`, que `tasks.rs` lit
   déjà. Plus de code, à valider sur une carte AMD ou Intel.
3. **Un seul device pour l'îlot et les barres** : de −15 à −40 Mo, et
   −20 threads par écran en plus. Il faudrait
   `QQuickGraphicsDevice::fromRhi` (Qt 6.6 et plus) avec la boucle
   `basic`, car en boucle `threaded` chaque fenêtre a son propre thread de
   rendu. Risque : à plusieurs fenêtres, la boucle `basic` peut caler
   l'animation sur la synchro verticale de chacune. À essayer en dernier.
4. **Vider le working set** (`EmptyWorkingSet`) : cosmétique, la mémoire
   part dans le fichier d'échange. Déconseillé.

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
