// Cle DeepL integree au binaire (src/translate.rs) : lue dans
// %USERPROFILE%\.ilot\deepl.key, hors du depot comme la cle de signature.
// Sans ce fichier, le traducteur passe par Google (apres l'avoir cree :
// `cargo clean -p ilot` ou toucher build.rs).
fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    let Ok(home) = std::env::var("USERPROFILE") else { return };
    let path = std::path::Path::new(&home).join(".ilot").join("deepl.key");
    let Ok(key) = std::fs::read_to_string(&path) else { return };
    // fichier present : on suit ses changements (absent, cargo relancerait ce script a chaque build)
    println!("cargo:rerun-if-changed={}", path.display());
    // BOM : fichier ecrit par PowerShell 5 (Set-Content -Encoding UTF8)
    let key = key.trim_start_matches('\u{feff}').trim();
    if !key.is_empty() {
        println!("cargo:rustc-env=ILOT_DEEPL_KEY={key}");
    }
}
