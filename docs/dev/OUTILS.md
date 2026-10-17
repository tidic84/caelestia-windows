# Outils de développement (poste et Claude Code)

## Poste (installé le 2026-10-17)

| Outil | Version | Où |
|---|---|---|
| Rust (toolchain MSVC) | 1.95 | `~/.cargo/bin` |
| Visual Studio Community 2022 | 17.14, MSVC 14.44 | chargé par `qt\build.cmd` via `vswhere` + `vcvars64` |
| CMake | 3.31 | `C:\Program Files\CMake\bin` |
| Ninja | winget `Ninja-build.Ninja` | `%LOCALAPPDATA%\Microsoft\WinGet\Links` |
| Qt 6.9.3 msvc2022_64 + qtshadertools | aqtinstall | `C:\Qt\6.9.3\msvc2022_64` (le `QTDIR` par défaut de `build.cmd`) |
| LLVM / clangd | 23.1 | `C:\Program Files\LLVM\bin`, ajouté au PATH utilisateur |

Outils Qt utiles dans `C:\Qt\6.9.3\msvc2022_64\bin` : `qmllint.exe`,
`qmlls.exe` et `windeployqt.exe`.

## Plugins Claude Code à utiliser

| Plugin | Quand l'utiliser |
|---|---|
| `qt-development-skills@claude-plugins-official` | Revue ou écriture de QML et de C++ Qt. Il lance `qmllint` : mets `C:\Qt\6.9.3\msvc2022_64\bin` dans le PATH, ou `QT_HOST_PATH`. |
| `clangd-lsp@claude-plugins-official` | Diagnostics C++ dans `qt/src/`. Il a besoin de `qt/build/compile_commands.json`, que CMake génère à chaque `qt\build.cmd`. |
| `rust-analyzer-lsp@claude-plugins-official` | Diagnostics Rust dans `src/`. |
| `rust-review@trailofbits` (skill `rust-review`) | Audit de sécurité Rust (FFI, `unsafe`, concurrence). Lourd : à réserver aux gros changements. |
| `code-review` (skill) | Revue d'un diff ou d'une PR avant de fusionner. |

Pas utile ici : `playwright` (il ne pilote que les navigateurs, alors que l'îlot
est une appli native).

Pour plus tard, si on veut vérifier l'interface par des captures d'écran : le
MCP `windows-computer-use` (sshh12/claude-plugins). Il n'est pas installé, car
le projet est très jeune.

## Lint QML (à la main)

```powershell
C:\Qt\6.9.3\msvc2022_64\bin\qmllint.exe -I qt\build qt\qml\Ilot.qml
```

Référence au 2026-10-17 : environ 100 avertissements pour `Ilot.qml`, environ
100 pour `Panel.qml` et 4 pour `Main.qml`. Une bonne partie vient de
`Failed to import IlotCore` : `Backend` est enregistré en C++ avec
`qmlRegisterSingletonInstance`, donc qmllint ne le connaît pas. Pour le
moment, ce n'est pas un signal fiable. Il faut comparer avant et après une
modification, sans chercher le zéro.
