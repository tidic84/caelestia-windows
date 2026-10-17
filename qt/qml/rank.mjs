// Classement du lanceur : ce qui correspond à la recherche, pondéré par les
// habitudes (« frécence » : souvent et récemment lancé, à cette heure-ci) et
// par ce qui a déjà été choisi pour le même début de recherche.
//
// Habitudes (%LOCALAPPDATA%\Ilot\usage.json) :
//   { apps: { id: { n, t: [ms...] } }, q: { "chr": { at, ids: { id: poids } } } }
// n : nombre de lancements, t : les derniers (dates), q : par début de
// recherche tapé (déjà normalisé), les applis choisies ensuite.

const DAY = 86400000;
const KEEP = 12;          // derniers lancements gardés par appli
const MAX_APPS = 400;
const MAX_QUERIES = 800;
const MAX_PREFIX = 16;    // longueur maximale d'un début de recherche retenu
const FORGET = 180 * DAY; // appli plus lancée depuis : oubliée

export function empty() {
  return { apps: {}, q: {} };
}

// Fichier relu : tout ce qui n'a pas la bonne forme est ignoré.
export function clean(u) {
  const out = empty();
  if (!u || typeof u !== 'object') return out;
  for (const id in u.apps || {}) {
    const e = u.apps[id];
    if (!e || !Array.isArray(e.t)) continue;
    const t = e.t.filter(x => typeof x === 'number' && x > 0).slice(-KEEP);
    if (t.length) out.apps[id] = { n: Math.max(t.length, +e.n || 0), t: t };
  }
  for (const p in u.q || {}) {
    const e = u.q[p];
    if (e && typeof e.ids === 'object' && +e.at > 0) out.q[p] = { at: +e.at, ids: Object.assign({}, e.ids) };
  }
  return out;
}

// Poids d'un lancement selon son âge (barème de Firefox).
function ageWeight(age) {
  return age < DAY ? 100 : age < 4 * DAY ? 80 : age < 14 * DAY ? 60 : age < 31 * DAY ? 40 : age < 90 * DAY ? 20 : 10;
}

// Frécence brute : nombre de lancements × poids moyen des derniers.
function frecency(e, now) {
  if (!e || !e.t.length) return 0;
  let w = 0;
  for (const t of e.t) w += ageWeight(now - t);
  return e.n * w / e.t.length;
}

// Part des derniers lancements faits à cette heure-ci (± 1 h).
function hourAffinity(e, now) {
  if (!e || e.t.length < 3) return 0;
  const h = new Date(now).getHours();
  let hit = 0;
  for (const t of e.t) {
    const d = Math.abs(new Date(t).getHours() - h);
    if (Math.min(d, 24 - d) <= 1) hit++;
  }
  return hit / e.t.length;
}

// Bonus d'habitude, de 0 (jamais lancée) à ~4 (lancée tous les jours).
export function habit(u, id, now) {
  const e = u.apps[id];
  if (!e) return 0;
  return Math.log1p(frecency(e, now) / 100) + 0.6 * hourAffinity(e, now);
}

// Bonus pour une appli déjà choisie après avoir tapé exactement ce début.
function learned(u, id, s) {
  const e = s && u.q[s];
  if (!e || !e.ids[id]) return 0;
  let sum = 0;
  for (const k in e.ids) sum += e.ids[k];
  const w = e.ids[id];
  return 3 * (w / sum) * Math.min(1, w / 2);
}

// Qualité de la correspondance entre un nom et la recherche (normalisés).
export function matchScore(n, s) {
  if (n.startsWith(s)) return 6;
  const words = n.split(/[\s\-_.()]+/).filter(Boolean);
  if (words.some(w => w.startsWith(s))) return 4.5;
  if (s.length >= 2 && words.map(w => w[0]).join('').startsWith(s)) return 4; // « vsc » : Visual Studio Code
  if (n.includes(s)) return 3;
  if (s.length >= 3) { // lettres dans l'ordre : « ntpd » → Notepad
    let i = 0;
    for (const c of n) if (c === s[i] && ++i === s.length) return 1;
  }
  return 0;
}

// Résultats d'une recherche, du plus pertinent au moins pertinent.
// items : [{ id, name }], norm : normalisation des noms, s : recherche normalisée.
export function search(u, items, s, norm, now) {
  const out = [];
  for (const a of items) {
    const n = norm(a.name);
    const m = matchScore(n, s);
    if (!m) continue;
    out.push({ a: a, len: n.length, score: m + 0.8 * Math.min(habit(u, a.id, now), 4) + learned(u, a.id, s) });
  }
  out.sort((x, y) => y.score - x.score || x.len - y.len || x.a.name.localeCompare(y.a.name, 'fr'));
  return out.map(x => x.a);
}

// Tri « Les plus utilisées » (sans recherche) ; à égalité, ordre d'origine.
export function byHabit(u, items, now) {
  return items
    .map((a, i) => ({ a: a, i: i, h: habit(u, a.id, now) }))
    .sort((x, y) => y.h - x.h || x.i - y.i)
    .map(x => x.a);
}

// Note un lancement (s : recherche tapée, normalisée, vide si aucune).
// Modifie u et le renvoie.
export function record(u, id, s, now) {
  const e = u.apps[id] || (u.apps[id] = { n: 0, t: [] });
  e.n++;
  e.t.push(now);
  if (e.t.length > KEEP) e.t.splice(0, e.t.length - KEEP);
  s = (s || '').trim().slice(0, MAX_PREFIX);
  // chaque début de la recherche : « c », « ch », « chr »…
  for (let i = 1; i <= s.length; i++) {
    const p = s.slice(0, i);
    const q = u.q[p] || (u.q[p] = { at: now, ids: {} });
    q.at = now;
    // les choix précédents comptent un peu moins : on suit les changements d'habitude
    for (const k in q.ids) {
      q.ids[k] *= 0.85;
      if (q.ids[k] < 0.1) delete q.ids[k];
    }
    q.ids[id] = (q.ids[id] || 0) + 1;
  }
  return prune(u, now);
}

function prune(u, now) {
  let ids = Object.keys(u.apps).filter(id => {
    const t = u.apps[id].t;
    if (now - t[t.length - 1] < FORGET) return true;
    delete u.apps[id];
    return false;
  });
  if (ids.length > MAX_APPS) {
    ids.sort((a, b) => frecency(u.apps[a], now) - frecency(u.apps[b], now));
    ids.slice(0, ids.length - MAX_APPS).forEach(id => delete u.apps[id]);
  }
  const qs = Object.keys(u.q);
  for (const p of qs) if (now - u.q[p].at >= FORGET) delete u.q[p];
  const left = Object.keys(u.q);
  if (left.length > MAX_QUERIES) {
    left.sort((a, b) => u.q[a].at - u.q[b].at);
    left.slice(0, left.length - MAX_QUERIES).forEach(p => delete u.q[p]);
  }
  return u;
}
