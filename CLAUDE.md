# Ilot (caelestia-windows)

Îlot dynamique et barre de bureau pour Windows 11, portage de caelestia-shell.
Le cœur est en Rust (`src/`, compilé en `ilot_core.dll`) et l'interface en
Qt 6.9 / QML + C++20 (`qt/`, compilée en `ilot.exe`). Dépôt :
`tidic84/caelestia-windows`.

## En début de session : lire dans cet ordre

1. `docs/dev/ETAT.md` : où on en est, journal des sessions, prochaine étape.
2. `docs/dev/BACKLOG.md` : bugs et pistes connus, non corrigés.
3. Selon le besoin :
   - `docs/dev/ARCHITECTURE.md` : carte de tous les fichiers, flux QML ↔ Rust,
     comment ajouter une commande ;
   - `docs/dev/OUTILS.md` : outils du poste et plugins Claude Code ;
   - `docs/perf-*.md` : mesures et optimisations.

**En fin de session**, ajoute une entrée dans `ETAT.md`. Mets aussi à jour
`BACKLOG.md` et, si des fichiers ont été ajoutés ou déplacés,
`ARCHITECTURE.md`.

## Règles de l'utilisateur pour ce projet

- Ne faire que des changements **essentiels**, qui ne cassent pas l'usage
  actuel.
- Pas de refonte non demandée.
- Le Rust se touche selon l'usage.
- Tout correctif doit être compilé, puis relu par l'agent `relecteur`.

## Commandes

```powershell
qt\build.cmd                                            # compile tout (cargo release + CMake/Ninja + windeployqt) → qt\build\ilot.exe
powershell -ExecutionPolicy Bypass -File install.ps1    # compile, installe dans %LOCALAPPDATA%\Programs\Ilot, relance
cargo clippy --all-targets ; cargo test                 # côté Rust (1 seul test aujourd'hui)
C:\Qt\6.9.3\msvc2022_64\bin\qmllint.exe -I qt\build qt\qml\X.qml
$env:ILOT_QT_LOG="$env:TEMP\ilot.log"; qt\build\ilot.exe   # journal Qt/QML dans un fichier
```

Version : `Cargo.toml`, plus une section dans `CHANGELOG.md` (embarqué dans
l'appli). Pour publier, pousser un tag `v*` : la CI publie
`ilot-<ver>-win64.zip`.

## Pièges connus

- **Depuis le Bash de Claude Code**, il faut lancer le build par PowerShell en
  rechargeant le PATH. Sinon Ninja (installé par winget) et clangd sont
  introuvables :
  ```
  powershell.exe -NoProfile -Command '$env:Path=[Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User"); cmd /c "qt\build.cmd"'
  ```
- **Message `'vswhere.exe' n'est pas reconnu`** : il vient de `vcvars64` et il
  est sans effet. Mais `install.ps1` a `$ErrorActionPreference = "Stop"`, donc
  **ne redirige pas `2>&1`** autour de lui dans PowerShell 5 : le message
  deviendrait une erreur bloquante. Redirige plutôt la sortie du processus
  `powershell.exe` depuis Bash.
- **`install.ps1` finit avec `$LASTEXITCODE = 1`** : c'est le code de robocopy
  (1 veut dire « fichiers copiés »). Ce n'est pas un échec.
- **`C:\MinGW\bin` est dans le PATH** : la toolchain doit rester MSVC (c'est ce
  que fait `build.cmd`).
- **L'appli tourne en une seule instance** (mutex). `install.ps1` la tue avant
  de copier.
- **Commandes QML → Rust** : ce sont des chaînes sans vérification à la
  compilation. Après avoir ajouté une commande, vérifie le nom dans le `match`
  de `src/lib.rs` (`call()`).
- **Icônes** : `qt/fonts/MaterialSymbolsRounded.ttf` est un sous-ensemble
  (≈ 300 ligatures). Un nom absent s'affiche en texte : vérifier que l'icône
  est déjà utilisée ailleurs dans `qt/qml`, ou lister les ligatures avec
  fontTools.
- **`sourceSize`** est déjà multiplié par le DPI par Qt avant d'arriver au
  provider `image://ilot`.
- **CPU « comme le Gestionnaire des tâches »** : c'est
  `\Processor Information(_Total)\% Processor Time`, pas
  `% Processor Utility`, qui est 12 à 25 % plus haut avec le turbo. Vérifié
  par captures simultanées le 2026-10-19.
- **Heredoc Python depuis le Bash de Claude Code** : les `\\` et `\n` placés
  dans des chaînes Rust ou Markdown y sont abîmés. Pour modifier du code qui
  contient des antislashs, utiliser Edit, ou un script `.py` écrit avec Write.
- **Tests de `tasks.rs`** : ne jamais passer à `task_kill` tous les membres
  d'un groupe, qui peut contenir des processus du poste. Ne viser que les pid
  lancés par le test.
- **Ne pas passer `panic = "abort"`** : `ilot_invoke` rattrape les paniques
  avec `catch_unwind`.
- **Effets système de l'appli** :
  - barre des tâches en masquage automatique, rétablie quand on quitte (si
    l'appli plante, redémarrer l'Explorateur) ;
  - clé `Run` dans HKCU ;
  - en option, remappage de la touche Windows dans HKLM (droits admin et
    redémarrage).

## Plugins Claude Code installés (à utiliser si besoin)

- `qt-development-skills` : revue et écriture de QML et de C++ Qt.
- `clangd-lsp` : diagnostics C++. Il faut avoir compilé une fois, pour
  `qt/build/compile_commands.json`.
- `rust-analyzer-lsp` : diagnostics Rust.
- Skill `rust-review` : audit de sécurité Rust, lourd.
- Skill `code-review` : revue avant de fusionner.

Détails dans `docs/dev/OUTILS.md`.
