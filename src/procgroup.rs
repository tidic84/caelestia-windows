//! Regroupement des processus comme l'onglet Processus du Gestionnaire des
//! taches. Algorithme pur (aucun appel Windows) : `tasks.rs` fournit les
//! noeuds, ce module rend les groupes et leurs cles stables.
//!
//! Regles (voir le contrat) :
//! - App : un processus qui a une fenetre, avec ses descendants du meme exe
//!   (Zen, Discord), son `conhost` (console) et, pour une appli du Store, les
//!   processus du meme paquet. Les autres descendants (EpicWebHelper sous
//!   EpicGamesLauncher, claude sous pwsh) ont leur propre ligne, comme dans le
//!   Gestionnaire des taches (verifie par capture le 2026-10-20). Un
//!   descendant qui a sa propre fenetre forme sa propre app. Un hote
//!   `NO_ADOPT` n'adopte pas de `conhost`.
//! - Fusion par identite : les apps de meme identite forment une seule ligne
//!   (`app:<identite>`).
//! - Arriere-plan : le reste forme des arbres de meme exe (un processus rejoint
//!   son parent s'il a le meme exe), une ligne par arbre
//!   (`tree:<pid>:<created_ms>` de la racine). Seuls les paquets du Store sont
//!   fusionnes (`bg:pkg:<famille>`), ou rejoignent l'app du meme paquet.
//! - Exceptions : chaque svchost (`svc:<pid>:<created_ms>`) et chaque csrss
//!   (`one:<pid>:<created_ms>`) forme sa propre ligne.
//!
//! Le lien parent n'est valable que si le parent existe, n'est pas le
//! processus lui-meme, et est ne avant l'enfant (sinon le pid a ete reutilise).
//! Tout est en O(n) (plus un tri des racines de chaque groupe).


use std::collections::HashMap;

/// Hotes qui n'adoptent que des enfants du meme exe.
pub const NO_ADOPT: &[&str] = &[
    "explorer", "sihost", "svchost", "services", "wininit", "winlogon", "smss", "csrss",
    "dllhost", "runtimebroker", "applicationframehost", "taskhostw", "ilot", "system",
    "wmiprvse",
];

/// Un processus du releve.
#[derive(Debug, Clone)]
pub struct Node {
    pub pid: u32,
    pub ppid: u32,
    /// Heure de creation en unites de 100 ns (comme `SpInfo.create_time`).
    pub create: i64,
    /// Nom de l'exe en minuscules, sans `.exe`.
    pub exe: String,
    /// Chemin de l'exe en minuscules, ou `exe` si le chemin est inconnu.
    pub ident: String,
    /// Le processus a une vraie fenetre.
    pub window: bool,
}

/// Une ligne de l'onglet Taches.
#[derive(Debug, Clone)]
pub struct Group {
    pub key: String,
    /// `true` pour une app (`app:`), `false` sinon.
    pub app: bool,
    /// Indices dans `nodes` : les racines d'abord (par heure de creation), puis
    /// le reste dans l'ordre de parcours (parents avant enfants).
    pub members: Vec<usize>,
}

/// `created_ms` des cles : meme valeur que `Sub.created`.
pub fn created_ms(create: i64) -> u64 {
    create.max(0) as u64 / 10_000
}

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    /// svchost ou csrss : une ligne par processus.
    Single,
    Normal,
}

fn kind(exe: &str) -> Kind {
    match exe {
        "svchost" | "csrss" => Kind::Single,
        _ => Kind::Normal,
    }
}

/// Arbres d'un groupe en cours de construction : racines et suites.
struct Acc {
    key: String,
    app: bool,
    /// (create, pid, indice) des racines.
    roots: Vec<(i64, u32, usize)>,
    /// Pour chaque arbre (meme ordre que `roots`), les descendants dans
    /// l'ordre de parcours, sans la racine.
    rest: Vec<Vec<usize>>,
}

pub fn group(nodes: &[Node]) -> Vec<Group> {
    let n = nodes.len();

    // pid -> indice (le premier gagne si un pid apparait deux fois).
    let mut by_pid: HashMap<u32, usize> = HashMap::with_capacity(n);
    for (i, nd) in nodes.iter().enumerate() {
        if nd.pid != 0 {
            by_pid.entry(nd.pid).or_insert(i);
        }
    }

    // Lien parent valable.
    let parent: Vec<Option<usize>> = nodes
        .iter()
        .map(|nd| {
            if nd.pid == 0 || nd.ppid == nd.pid {
                return None;
            }
            let &p = by_pid.get(&nd.ppid)?;
            (nodes[p].create <= nd.create).then_some(p)
        })
        .collect();

    // Enfants (liste chainee dans deux tableaux, sans allocation par noeud).
    // Parcours en sens inverse pour garder l'ordre de `nodes` dans chaque liste.
    let mut first_child = vec![usize::MAX; n];
    let mut next_sibling = vec![usize::MAX; n];
    for i in (0..n).rev() {
        if let Some(p) = parent[i] {
            next_sibling[i] = first_child[p];
            first_child[p] = i;
        }
    }

    // Groupe de chaque noeud (indice dans `accs`), usize::MAX = pas encore.
    const NONE: usize = usize::MAX;
    let mut owner = vec![NONE; n];
    let mut accs: Vec<Acc> = Vec::new();
    let mut by_key: HashMap<String, usize> = HashMap::new();
    let mut queue: Vec<usize> = Vec::new();

    let skip = |i: usize| nodes[i].pid == 0;

    // Ajoute un arbre de racine `r` au groupe `key` ; `adopt(enfant)` dit si
    // un enfant d'un membre rejoint l'arbre. Le test `owner` garantit la fin
    // du parcours meme avec un cycle de ppid.
    let mut add_tree = |r: usize,
                        key: String,
                        app: bool,
                        owner: &mut Vec<usize>,
                        adopt: &dyn Fn(usize) -> bool| {
        // paquet du Store : l'arriere-plan rejoint l'app du meme paquet
        let key = match key.strip_prefix("bg:pkg:") {
            Some(f) if by_key.contains_key(&format!("app:pkg:{f}")) => format!("app:pkg:{f}"),
            _ => key,
        };
        let gi = *by_key.entry(key.clone()).or_insert_with(|| {
            accs.push(Acc { key, app, roots: Vec::new(), rest: Vec::new() });
            accs.len() - 1
        });
        owner[r] = gi;
        let mut rest = Vec::new();
        queue.clear();
        queue.push(r);
        let mut head = 0;
        while head < queue.len() {
            let u = queue[head];
            head += 1;
            let mut c = first_child[u];
            while c != usize::MAX {
                if owner[c] == NONE && adopt(c) {
                    owner[c] = gi;
                    queue.push(c);
                    rest.push(c);
                }
                c = next_sibling[c];
            }
        }
        accs[gi].roots.push((nodes[r].create, nodes[r].pid, r));
        accs[gi].rest.push(rest);
    };

    // 1. Exceptions : une ligne par processus.
    for (i, nd) in nodes.iter().enumerate() {
        if nd.pid == 0 || kind(&nd.exe) != Kind::Single {
            continue;
        }
        let pre = if nd.exe == "svchost" { "svc" } else { "one" };
        let key = format!("{pre}:{}:{}", nd.pid, created_ms(nd.create));
        add_tree(i, key, false, &mut owner, &|_| false);
    }

    // 2. Apps : chaque processus a fenetre est une racine. Un enfant sans
    // fenetre rejoint l'app s'il a le meme exe, le meme paquet du Store, ou
    // si c'est la console (conhost) d'une racine qui n'est pas un hote.
    for r in 0..n {
        if skip(r) || owner[r] != NONE || !nodes[r].window {
            continue;
        }
        let root_exe = nodes[r].exe.as_str();
        let root_ident = nodes[r].ident.as_str();
        let host = NO_ADOPT.contains(&root_exe);
        let adopt = |c: usize| {
            let ch = &nodes[c];
            !ch.window
                && ch.pid != 0
                && kind(&ch.exe) == Kind::Normal
                && (ch.exe == root_exe
                    || (root_ident.starts_with("pkg:") && ch.ident == root_ident)
                    || (!host && ch.exe == "conhost"))
        };
        add_tree(r, format!("app:{}", nodes[r].ident), true, &mut owner, &adopt);
    }

    // 3. Arriere-plan : arbres de meme exe, une ligne par arbre (Windows ne
    // fusionne pas deux EpicWebHelper freres, verifie par capture), sauf les
    // paquets du Store (une ligne par paquet). Racine = noeud restant dont le
    // parent est pris ailleurs, absent, ou d'un autre exe.
    let bg_key = |r: usize| {
        let nd = &nodes[r];
        if nd.ident.starts_with("pkg:") {
            format!("bg:{}", nd.ident)
        } else {
            format!("tree:{}:{}", nd.pid, created_ms(nd.create))
        }
    };
    let bg_adopt = |c: usize| {
        let ch = &nodes[c];
        let p = parent[c].expect("enfant sans parent");
        ch.pid != 0 && kind(&ch.exe) == Kind::Normal && ch.exe == nodes[p].exe
    };
    for r in 0..n {
        if skip(r) || owner[r] != NONE {
            continue;
        }
        let is_root = match parent[r] {
            None => true,
            Some(p) => owner[p] != NONE || nodes[p].exe != nodes[r].exe,
        };
        // Un parent de meme exe encore libre sera traite comme racine (ou par
        // la passe suivante s'il fait partie d'un cycle).
        if is_root {
            add_tree(r, bg_key(r), false, &mut owner, &bg_adopt);
        }
    }
    // Restes : cycles de ppid de meme exe, sans racine. On coupe le cycle.
    for r in 0..n {
        if !skip(r) && owner[r] == NONE {
            add_tree(r, bg_key(r), false, &mut owner, &bg_adopt);
        }
    }

    // Assemblage : racines triees par heure de creation, puis les suites.
    accs.into_iter()
        .map(|mut a| {
            let mut order: Vec<usize> = (0..a.roots.len()).collect();
            order.sort_by_key(|&t| (a.roots[t].0, a.roots[t].1));
            let total = a.roots.len() + a.rest.iter().map(Vec::len).sum::<usize>();
            let mut members = Vec::with_capacity(total);
            members.extend(order.iter().map(|&t| a.roots[t].2));
            for &t in &order {
                members.append(&mut a.rest[t]);
            }
            Group { key: a.key, app: a.app, members }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn nd(pid: u32, ppid: u32, create: i64, exe: &str, window: bool) -> Node {
        Node {
            pid,
            ppid,
            create,
            exe: exe.to_string(),
            ident: format!("c:\\{exe}.exe"),
            window,
        }
    }

    /// Groupes sous forme (cle, pids des membres), tries par cle.
    fn run(nodes: &[Node]) -> Vec<(String, Vec<u32>)> {
        let gs = group(nodes);
        // Chaque noeud (sauf pid 0) dans exactement un groupe.
        let mut seen = vec![0; nodes.len()];
        for g in &gs {
            assert_eq!(g.app, g.key.starts_with("app:"));
            for &m in &g.members {
                seen[m] += 1;
            }
        }
        for (i, n) in nodes.iter().enumerate() {
            assert_eq!(seen[i], if n.pid == 0 { 0 } else { 1 }, "pid {}", n.pid);
        }
        let mut out: Vec<_> = gs
            .into_iter()
            .map(|g| (g.key, g.members.iter().map(|&i| nodes[i].pid).collect()))
            .collect();
        out.sort();
        out
    }

    fn k(s: &str, pids: &[u32]) -> (String, Vec<u32>) {
        (s.to_string(), pids.to_vec())
    }

    #[test]
    fn app_avec_enfants() {
        let v = [
            nd(10, 1, 100, "code", true),
            nd(11, 10, 110, "code", false),
            nd(12, 11, 120, "node", false),
            nd(13, 10, 130, "conhost", false),
        ];
        // node (autre exe) a sa propre ligne, comme EpicWebHelper chez Windows
        assert_eq!(run(&v), vec![k("app:c:\\code.exe", &[10, 11, 13]), k("tree:12:0", &[12])]);
    }

    #[test]
    fn enfant_avec_sa_fenetre() {
        let v = [
            nd(10, 1, 100, "code", true),
            nd(11, 10, 110, "notepad", true),
            nd(12, 11, 120, "notepad", false),
        ];
        assert_eq!(
            run(&v),
            vec![k("app:c:\\code.exe", &[10]), k("app:c:\\notepad.exe", &[11, 12])]
        );
    }

    #[test]
    fn explorer_n_adopte_pas_notepad() {
        let v = [
            nd(10, 1, 100, "explorer", true),
            nd(11, 10, 110, "explorer", false),
            nd(12, 10, 120, "notepad", true),
            nd(13, 10, 130, "onedrive", false),
        ];
        assert_eq!(
            run(&v),
            vec![
                k("app:c:\\explorer.exe", &[10, 11]),
                k("app:c:\\notepad.exe", &[12]),
                k("tree:13:0", &[13]),
            ]
        );
    }

    #[test]
    fn fusion_de_deux_chrome() {
        let v = [
            nd(20, 1, 200, "chrome", true),
            nd(21, 20, 210, "chrome", false),
            nd(10, 1, 100, "chrome", true),
            nd(11, 10, 110, "chrome", false),
        ];
        // Racines d'abord, par heure de creation.
        assert_eq!(run(&v), vec![k("app:c:\\chrome.exe", &[10, 20, 11, 21])]);
    }

    #[test]
    fn paquet_du_store_rejoint_son_app() {
        let mut v = vec![
            nd(10, 1, 100, "launcher", false),
            nd(11, 10, 110, "crashpad", false),
            nd(20, 9, 200, "spotify", true),
            nd(21, 20, 210, "spotify", false),
            nd(30, 1, 300, "other", false),
        ];
        for x in &mut v[..4] {
            x.ident = "pkg:spotify_x".into();
        }
        assert_eq!(
            run(&v),
            vec![k("app:pkg:spotify_x", &[10, 11, 20, 21]), k("tree:30:0", &[30])]
        );
    }

    #[test]
    fn bg_une_ligne_par_arbre() {
        let v = [
            nd(5, 1, 50, "svchost", false),
            nd(30, 5, 300, "runtimebroker", false),
            nd(31, 5, 310, "runtimebroker", false),
            nd(32, 30, 320, "runtimebroker", false),
            nd(33, 30, 330, "other", false),
        ];
        assert_eq!(
            run(&v),
            vec![
                k("svc:5:0", &[5]),
                k("tree:30:0", &[30, 32]),
                k("tree:31:0", &[31]),
                k("tree:33:0", &[33]),
            ]
        );
    }

    #[test]
    fn svchost_une_ligne_chacun() {
        let v = [
            nd(4, 0, 0, "system", false),
            nd(5, 4, 10_000, "services", false),
            nd(6, 5, 25_000_000, "svchost", false),
            nd(7, 5, 30_000_000, "svchost", false),
            nd(8, 6, 40_000_000, "svchost", false),
        ];
        assert_eq!(
            run(&v),
            vec![
                k("svc:6:2500", &[6]),
                k("svc:7:3000", &[7]),
                k("svc:8:4000", &[8]),
                k("tree:4:0", &[4]),
                k("tree:5:1", &[5]),
            ]
        );
    }

    #[test]
    fn csrss_one() {
        let v = [
            nd(500, 1, -5, "csrss", false),
            nd(600, 1, 70_000, "csrss", true),
            nd(601, 600, 80_000, "csrss", false),
        ];
        // create negatif -> 0 ; meme avec une fenetre, csrss reste seul.
        assert_eq!(
            run(&v),
            vec![k("one:500:0", &[500]), k("one:600:7", &[600]), k("one:601:8", &[601])]
        );
    }

    #[test]
    fn pid_reutilise() {
        // Le "parent" 10 est ne apres l'enfant : ce n'est pas son parent.
        let v = [
            nd(10, 1, 500, "code", true),
            nd(11, 10, 100, "worker", false),
        ];
        assert_eq!(
            run(&v),
            vec![k("app:c:\\code.exe", &[10]), k("tree:11:0", &[11])]
        );
    }

    #[test]
    fn cycle_de_ppid() {
        // Memes heures de creation : le lien passe le test, le cycle existe.
        let v = [
            nd(40, 41, 100, "foo", false),
            nd(41, 42, 100, "foo", false),
            nd(42, 40, 100, "foo", false),
            nd(50, 51, 100, "bar", true),
            nd(51, 50, 100, "bar", false),
            nd(60, 60, 100, "self", false),
        ];
        let r = run(&v);
        assert_eq!(r.len(), 3);
        assert_eq!(r[0], k("app:c:\\bar.exe", &[50, 51]));
        assert_eq!(r[1].0, "tree:40:0");
        assert_eq!(r[1].1.len(), 3);
        assert_eq!(r[2], k("tree:60:0", &[60]));
    }

    #[test]
    fn pid_zero_ignore() {
        let v = [
            nd(0, 0, 0, "idle", false),
            nd(4, 0, 0, "system", false),
            nd(10, 0, 100, "idle", true),
        ];
        assert_eq!(
            run(&v),
            vec![k("app:c:\\idle.exe", &[10]), k("tree:4:0", &[4])]
        );
    }

    #[test]
    fn hote_no_adopt_garde_meme_exe() {
        // explorer : garde son enfant explorer, pas l'outil lance (bg)
        let v = [
            nd(10, 1, 100, "explorer", true),
            nd(11, 10, 110, "explorer", false),
            nd(12, 11, 120, "explorer", false),
            nd(13, 11, 130, "git", false),
        ];
        assert_eq!(
            run(&v),
            vec![k("app:c:\\explorer.exe", &[10, 11, 12]), k("tree:13:0", &[13])]
        );
    }

    #[test]
    fn grand_releve_lineaire() {
        // Chaine de 50 000 processus : doit rester rapide (pas de quadratique).
        let v: Vec<Node> = (1..=50_000u32)
            .map(|p| nd(p, p - 1, p as i64, "x", p == 1))
            .collect();
        let gs = group(&v);
        assert_eq!(gs.len(), 1);
        assert_eq!(gs[0].members.len(), 50_000);
    }
}
