//! Signe une archive de l'ilot pour la mise a jour automatique
//! (`src/update.rs` refuse une archive sans signature valide).
//!
//! ```text
//! cargo run --release --example sign -- keygen <cle>                 nouvelle cle privee
//! cargo run --release --example sign -- pub <cle>                    cle publique (SIGN_KEY)
//! cargo run --release --example sign -- sign <cle> <zip> <version>   ecrit <zip>.sig
//! ```
//!
//! La cle privee ne doit jamais aller dans le depot. Sans elle, plus aucune
//! mise a jour ne s'installe toute seule : la sauvegarder.

use std::io::Read;

use base64::Engine;
use p256::ecdsa::signature::DigestSigner;
use p256::ecdsa::{Signature, SigningKey};
use sha2::{Digest, Sha256};

fn b64() -> base64::engine::GeneralPurpose {
    base64::engine::general_purpose::STANDARD
}

fn load(path: &str) -> SigningKey {
    let s = std::fs::read_to_string(path).unwrap_or_else(|e| fail(&format!("{path} : {e}")));
    let k = b64().decode(s.trim()).unwrap_or_else(|_| fail("cle illisible"));
    SigningKey::from_slice(&k).unwrap_or_else(|_| fail("cle invalide"))
}

fn public(k: &SigningKey) -> String {
    b64().encode(k.verifying_key().to_encoded_point(true).as_bytes())
}

fn fail(msg: &str) -> ! {
    eprintln!("sign : {msg}");
    std::process::exit(1)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        ["keygen", path] => {
            if std::path::Path::new(path).exists() {
                fail(&format!("{path} existe deja"));
            }
            let k = SigningKey::random(&mut rand::rngs::OsRng);
            std::fs::write(path, b64().encode(k.to_bytes())).unwrap_or_else(|e| fail(&e.to_string()));
            println!("{}", public(&k));
        }
        ["pub", path] => println!("{}", public(&load(path))),
        ["sign", path, zip, version] => {
            let k = load(path);
            // meme message que `signed_message` (src/update.rs)
            let mut h = Sha256::new();
            let mut f = std::fs::File::open(zip).unwrap_or_else(|e| fail(&format!("{zip} : {e}")));
            let mut buf = vec![0u8; 64 * 1024];
            loop {
                let n = f.read(&mut buf).unwrap_or_else(|e| fail(&e.to_string()));
                if n == 0 {
                    break;
                }
                h.update(&buf[..n]);
            }
            h.update(format!("\nilot {version}").as_bytes());
            let sig: Signature = k.sign_digest(h);
            let out = format!("{zip}.sig");
            std::fs::write(&out, b64().encode(sig.to_bytes())).unwrap_or_else(|e| fail(&e.to_string()));
            println!("{out}");
        }
        _ => fail("usage : keygen <cle> | pub <cle> | sign <cle> <zip> <version>"),
    }
}
