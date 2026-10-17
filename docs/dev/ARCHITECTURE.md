# Architecture d'Ilot

Le cœur est en Rust : `src/`, compilé en `ilot_core.dll` (cdylib). L'interface
est en Qt 6.9 / QML avec C++20 : `qt/`, compilée en `ilot.exe`. Les deux parlent
par une petite interface C : le QML envoie des commandes JSON, Rust renvoie des
événements JSON.

Cette carte a été vérifiée le 2026-10-17 (0.4.8). Mets-la à jour quand tu
ajoutes, supprimes ou déplaces un fichier.

## Flux principal

1. **Démarrage (`main.cpp`)** : `ilot_cli()` (s'arrête si c'est un diagnostic), puis le mutex d'instance unique, puis `Backend` (singleton QML `IlotCore`), puis `Tray`, puis `Shell.start()`.
2. **`Shell`** :
   - charge `Main.qml` ;
   - `WinCtl` déclare chaque fenêtre au cœur avec `ilot_register(label, hwnd)` ;
   - `ilot_start(&Backend::onEmit)` lance tous les `watch` et `init` de Rust ;
   - crée une `Bar.qml` par autre écran.
3. **Affichage** : `Main.qml` → `Island` → `Pill` / `Panel` → pages. L'état est dans les singletons `Ilot`, `Watch` et `Theme`.
4. **Commande** :
   - `Api.invoke(cmd, args, label)` → `Backend.invoke` (sur un `QThreadPool`) → `ilot_invoke` → `call()` dans `src/lib.rs` (un `match "cmd"`) ;
   - la réponse `{"ok":…}` ou `{"err":…}` revient par le signal `Backend.reply(id)`, qui résout la Promise ;
   - `Api.call` fait la même chose en synchrone, avec `invokeSync`.
5. **Événement** :
   - un module Rust appelle `app.emit("nom", payload)` (`host.rs`) → `Backend::onEmit` → mise en file sur le thread UI → `event(nom, json)` → `Api.listen("nom", fn)` ;
   - si le nom commence par `@`, le signal est `internal` au lieu de `event`.
6. **Images** : `img::url(...)` = `image://ilot/<clé>` → `IlotImages` (`backend.cpp`) → `ilot_image(clé)`.

## Ajouter une commande de bout en bout

1. **Rust** : dans `src/<module>.rs`, écrire `pub fn ma_cmd(app: AppHandle | State<T>, x: Type) -> Ret`.
   - `Ret` doit être sérialisable, ou `Result<Ret, String>`.
   - Pour un nouveau module, ajouter `mod <module>;` dans `src/lib.rs`.
2. **Aiguillage** : dans `src/lib.rs`, fonction `call()`, ajouter `"ma_cmd" => json(module::ma_cmd(app, a!("x"))),`.
   - Si la fonction renvoie un `Result` : `.and_then(json)`.
   - Les noms d'arguments sont ceux du JSON envoyé par QML, en camelCase.
3. **QML** : appeler `Api.invoke("ma_cmd", { x: … }).then(r => …)`.
4. **État partagé ou surveillance** :
   - état : `app.manage(...)` dans `ilot_start` ;
   - surveillance : `module::watch(app)` dans `ilot_start`, qui émet avec `app.emit`, reçu par `Api.listen`.
5. **C++** : rien à toucher, le pont est générique.
   - Un nouveau `.qml` est repris automatiquement par le glob de `qt/CMakeLists.txt`.
   - Un nouveau singleton doit être ajouté à `QT_QML_SINGLETON_TYPE`.

Attention : rien ne vérifie à la compilation que le nom de la commande ou de ses
arguments est le même côté QML et côté Rust. Une faute de frappe se voit
seulement à l'exécution, dans le journal `ILOT_QT_LOG`.

## Racine

```text
├── Cargo.toml / Cargo.lock  Crate "ilot" : lib ilot_core en cdylib (windows, serde, ureq, rusqlite, image, symphonia, prost, p256…)
├── install.ps1     Compile (qt\build.cmd), copie dans %LOCALAPPDATA%\Programs\Ilot (robocopy /MIR), raccourci Démarrage, lance
├── uninstall.ps1   Arrête ilot.exe, supprime le raccourci et le dossier installé (garde %LOCALAPPDATA%\Ilot et la clé Run)
├── CHANGELOG.md    Notes de version, embarquées dans l'appli (update.rs) et publiées sur GitHub Releases
├── README.md       Présentation pour l'utilisateur
├── .github/workflows/release.yml  Sur un tag v* : compile et publie ilot-<ver>-win64.zip
├── icons/          icon.ico, icon.png
└── docs/           Captures, perf-ilot.md (mesures), perf-pistes.md (optimisations), dev/ (ce dossier)
```

## `src/` : cœur Rust

```text
├── lib.rs        Interface C (ilot_register, ilot_start, ilot_invoke → call() = gros match, ilot_image, ilot_free*, ilot_cli, ilot_shutdown), com_init, http(), screens
├── host.rs       Remplace Tauri : EmitFn, emit, état partagé manage/state, fenêtres par label (island, bar-DISPLAYn)
├── store.rs      Petits JSON dans %LOCALAPPDATA%\Ilot
├── settings.rs   Réglages (autostart = clé Run, écran, apparence, météo, agendas, fonds, barre, addons)
├── prefs.rs      Raccourcis clavier globaux, export/import des réglages (seul test du projet)
├── events.rs     WinEvent, curseur, notifications presse-papiers, RegWatch (surveillance du registre)
├── img.rs        Cache des images image://ilot/
├── bar.rs        Barre façon Waybar, AppBar, masquage de la barre des tâches
├── winkey.rs     Touche Windows → lanceur (Scancode Map HKLM, admin), hook clavier, combos
├── media.rs      Lecteur (GSMTC)        ├── lyrics.rs  Paroles LRC (LRCLIB, NetEase)
├── audio.rs      Sortie, mélangeur, OSD volume, visualiseur (loopback + FFT)
├── boost.rs      Volume > 100 % via Equalizer APO
├── system.rs     Ressources, batterie, historique presse-papiers, caféine, profil, actions de session
├── display.rs    Luminosité (WMI, DDC/CI) + OSD
├── net.rs        Wi-Fi, Bluetooth, réseau
├── notif.rs      Notifications Windows (wpndatabase.db en lecture seule)
├── theme.rs      Clair/sombre et accent        ├── wall.rs  Fonds d'écran      ├── we.rs  Wallpaper Engine
├── apps.rs       Lanceur (shell:AppsFolder)    ├── games.rs Jeux Steam/Epic/Ubisoft/GOG, sélecteurs de fichiers
├── files.rs      Fichiers déposés (conversion, zip, presse-papiers)
├── tasks.rs      Gestionnaire des tâches       ├── pdh.rs   Compteurs PDH (CPU, GPU, disque)
├── pc.rs         Mode d'alimentation, logiciels constructeur, instantané Toolhelp
├── health.rs     Disques, nettoyage, pilote NVIDIA, idle_secs
├── status.rs     État des services en ligne (toutes les 3 min)
├── privacy.rs    Voyant caméra/micro (ConsentStore)
├── activity.rs   Steam, jeu lancé, GPU NVIDIA (NVML) → événement gaming
├── valorant.rs   File, partie trouvée, sélection d'agents (API locale Riot)
├── discord.rs    RPC Discord (pipe IPC), identifiants DPAPI
├── soundboard.rs Soundboard vers câble virtuel ├── decode.rs  Décodage audio (symphonia)
├── captions.rs   Sous-titres (LiveCaptions via UI Automation)
├── translate.rs  Traduction Google « gtx »
├── mail.rs       IMAP (mots de passe DPAPI)    ├── google.rs  OAuth 2 Gmail (PKCE)
├── update.rs     Mises à jour GitHub Releases (toutes les 6 h)
└── quickshare/   Quick Share (d'après NearDrop)
    ├── mod.rs  État, mDNS, commandes qs_*   ├── conn.rs  UKEY2, AES-CBC + HMAC, trames
    ├── inbound.rs  Réception                ├── outbound.rs  Envoi
    └── proto.rs  Messages protobuf (prost)
```

## `qt/` : interface

```text
├── CMakeLists.txt  Module QML "Ilot" (glob qml/*), singletons Theme/Ilot/Api/Watch, shader, polices, compile_commands.json
├── build.cmd       cargo build --release → CMake/Ninja (MSVC via vswhere) → windeployqt
├── ilot.rc, fonts/ (Rubik, Material Symbols), shaders/round.frag (image arrondie en une passe)
└── src/
    ├── main.cpp      Démarrage, instance unique, journal ILOT_QT_LOG
    ├── core.h        Prototypes C du cœur Rust
    ├── backend.*     Pont QML↔Rust : invoke/invokeSync, onEmit, provider image://ilot, imagePixels, quit/restart
    ├── shell.*       Fenêtres, placement et réservation, menu de notification, Ctrl+Alt+Espace
    ├── tray.*        Hôte de la zone de notification (fausse Shell_TrayWnd), provider image://tray
    ├── winctl.*      Élément QML WinCtl : zones cliquables, flou, plein écran, focus
    └── backdrop.*    Flou acrylique (Windows.UI.Composition) sous la fenêtre Qt
```

## `qt/qml/`

```text
Singletons    Api (invoke/call/listen) · Ilot (état global : réglages, thème, pilule, lecteur, météo, minuteur, horloge d'ambiance amb/wave)
              Watch (jeux, absence, Valorant, extinction, caméra/micro, services) · Theme (Material You, polices, courbes)
Fenêtres      Main (îlot) · Bar (écrans sans îlot) · Captions · TipWindow · PetWindow (promenade du compagnon)
Îlot          Island · Pill · PillClock · Panel · BarContent · BarTask · TaskIcon · TaskPreview · QuickShare · Ear
Pages         HomePage · MediaPage · CtrlPage · AppsPage · ClipsPage · WallsPage · MailPage · TasksPage · PcPage
              SoundsPage · AssistPage · SettingsPage
Cartes PC     PcCard · ServicesCard · HealthCard · ShutdownCard · SensCard
Compagnon     Pet (10 espèces, expressions, tours)
Décor         Aurora · WxFx (météo animée) · Glow · Eq · VizBars
Composants    Btn · IconBtn · TextBtn · M3Switch · M3Slider · Seg · Field · Area · CtxMenu · Card · Chip · Empty
              Gauge · Spinner · Scroller · Tip · Txt · Ms · RoundImage · ArtImage · RoundArt · MediaControls
              NotifRow · TimerBody
Modules JS    calc · emoji · ical · rank (frécence du lanceur) · quant (couleur du thème) · mcu (material-color-utilities)
```
