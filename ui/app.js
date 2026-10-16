import {
  Hct, SchemeTonalSpot, SchemeVibrant, SchemeExpressive, SchemeFidelity, SchemeContent, SchemeNeutral,
  SchemeMonochrome, SchemeRainbow, SchemeFruitSalad,
  MaterialDynamicColors as MDC, sourceColorFromImage, hexFromArgb, argbFromHex,
} from './vendor/mcu.js';

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const island = $('#island');

// ======================================================= état de l'îlot
// collapsed -> (survol) peek -> (clic / molette) open
const SIZE = {
  collapsed: m => ({ w: (m ? 200 : 132) + (actChip ? 68 : 0) + (dcShown ? 26 : 0) + (petShown ? 22 : 0) + (privShown ? 14 : 0) + (offShown ? 52 : 0) + clockExtra, h: 30 }),
  peek: m => {
    const s = m ? { w: 420, h: 66 } : actChip ? { w: 380, h: 60 } : { w: 250, h: 50 };
    return dcShown ? { w: s.w + 70, h: s.h } : s;
  },
  open: () => (big ? bigSize() : normalSize()),
};
// Accessibilité > Taille du texte : le panneau normal grandit avec le texte
let textK = 1;
const normalSize = () => ({ w: Math.round(NORMAL.w * textK), h: Math.round(NORMAL.h * textK) });
const NORMAL = { w: 740, h: 484 };
// panneau agrandi : presque tout l'écran, sans dépasser 1400×860
const bigSize = () => ({
  w: Math.max(normalSize().w, Math.min(1400, screen.width - 160)),
  h: Math.max(normalSize().h, Math.min(860, screen.height - 120)),
});
let big = false;
let locked = false; // verrouillé : ne se replie pas quand la souris sort
const EAR = 22;
let state = 'collapsed';
let hovered = false;
let pinned = false; // ouvert au clavier : ne se referme pas en sortant la souris
let leaveTimer = null;
let hasMedia = false;
let actChip = false; // activité en cours affichée dans la pilule repliée
let dcShown = false; // raccourcis Discord (micro / sourdine) dans la pilule
let petShown = false; // compagnon dans la pilule repliée
let privShown = false; // voyant caméra / micro
let offShown = false; // minuteur d'extinction dans la pilule
let clockExtra = 0; // largeur en plus / en moins selon le style d'horloge
let notifShown = null; // notification affichée (îlot agrandi)
const NOTIF_SIZE = { w: 420, h: 66 };
const PILL_SCALE = { s: 0.85, m: 1, l: 1.2 };
const placement = { k: 1, bottom: false }; // Apparence > Taille / Position (applyPlacement)

function reportHit() {
  const { w, h } = notifShown && state !== 'open' ? NOTIF_SIZE : SIZE[state](hasMedia);
  // taille de la pilule (repliée / survol) : le CSS la suit (--pill-w / --pill-h)
  if (state !== 'open') {
    const p = SIZE[state](hasMedia);
    island.style.setProperty('--pill-w', p.w + 'px');
    island.style.setProperty('--pill-h', p.h + 'px');
  }
  // Apparence > Taille de la pilule (pas le panneau ouvert) / Position en bas
  const k = state === 'open' ? 1 : placement.k;
  const W = (w + EAR * 2) * k, H = (h + (state === 'collapsed' ? 6 : 2)) * k;
  const x = (innerWidth - W) / 2;
  // un peu de marge sous l'îlot replié pour l'attraper facilement
  invoke('set_hit', { x, y: placement.bottom ? innerHeight - H : 0, w: W, h: H });
}

function setState(s) {
  if (s === state) return;
  state = s;
  island.classList.remove('collapsed', 'peek', 'open');
  island.classList.add(s);
  if (s !== 'open') pinned = false;
  if (s === 'open') onOpen();
  reportHit();
}

function open(tab) {
  if (tab) showTab(tab);
  setState('open');
}
function close() {
  setState(hovered ? 'peek' : 'collapsed');
}

listen('hover', ({ payload }) => {
  hovered = payload;
  clearTimeout(leaveTimer);
  if (hovered) {
    if (state === 'collapsed') setState('peek');
  } else if (state === 'peek') {
    leaveTimer = setTimeout(() => setState('collapsed'), 120);
  } else if (state === 'open' && !pinned && !locked) {
    leaveTimer = setTimeout(() => setState('collapsed'), 450);
  }
});
listen('fullscreen', ({ payload }) => {
  island.classList.toggle('hidden', payload);
  if (payload) setState('collapsed');
  syncViz();
});
listen('blur', () => {
  if (state === 'open' && !hovered && !locked) setState('collapsed');
});

// ------------------------------------------- agrandir / verrouiller le panneau
// enregistré dans %LOCALAPPDATA%\Ilot\layout.json : { big, locked }
const WIN_PAD = { w: 60, h: 56 }; // marge de la fenêtre autour du panneau (oreilles)
function setBig(on, save = true) {
  big = on;
  const s = on ? bigSize() : normalSize();
  // la fenêtre grandit avant le panneau, et rétrécit après l'animation
  if (on || textK > 1) invoke('win_resize', { w: s.w + WIN_PAD.w, h: s.h + WIN_PAD.h });
  else setTimeout(() => { if (!big) invoke('win_resize', { w: 800, h: 540 }); }, 550);
  island.style.setProperty('--open-w', s.w + 'px');
  island.style.setProperty('--open-h', s.h + 'px');
  island.classList.toggle('big', on);
  const b = $('[data-tool="big"]');
  b.classList.toggle('on', on);
  b.title = on ? 'Réduire' : 'Agrandir';
  b.querySelector('.ms').textContent = on ? 'close_fullscreen' : 'open_in_full';
  reportHit();
  setTimeout(moveIndicator, 520);
  if (save) saveLayout();
}
function setLocked(on, save = true) {
  locked = on;
  const b = $('[data-tool="lock"]');
  b.classList.toggle('on', on);
  b.title = on ? 'Déverrouiller : l\'îlot se replie quand la souris sort' : 'Verrouiller : l\'îlot reste ouvert';
  b.querySelector('.ms').textContent = on ? 'lock' : 'lock_open';
  if (on) clearTimeout(leaveTimer);
  if (save) saveLayout();
}
function saveLayout() { invoke('store_set', { key: 'layout', value: { big, locked } }); }
$('[data-tool="big"]').addEventListener('click', () => setBig(!big));
$('[data-tool="lock"]').addEventListener('click', () => setLocked(!locked));
invoke('store_get', { key: 'layout' }).then(l => {
  if (l && l.big) setBig(true, false);
  if (l && l.locked) setLocked(true, false);
});
listen('launcher', () => {
  if (state === 'open' && currentTab === 'apps') return setState('collapsed');
  pinned = true;
  open('apps');
  setTimeout(() => $('#q').focus(), 60);
});

$('#pill').addEventListener('click', e => {
  if (e.target.closest('[data-media], [data-dc]')) return;
  // clic sur une notification : ouvre l'onglet lié (mail) ou la fait disparaître
  if (notifShown && state !== 'open') {
    const { tab, url, cmd, fn } = notifShown;
    nextNotif();
    if (url) { invoke('open_url', { url }); return; }
    if (fn) { fn(); return; }
    if (cmd) { invoke(...cmd); return; }
    if (tab) open(tab);
    return;
  }
  open(hasMedia && currentTab === 'home' ? 'home' : null);
});
// îlot replié : la molette règle le volume, le clic molette met en pause / relance
island.addEventListener('wheel', e => {
  if (state !== 'open') (e.shiftKey ? fgVolume : wheelVolume)(e.deltaY || e.deltaX);
  else if (e.deltaY < 0 && e.target.closest('#tabs')) close();
}, { passive: true });
island.addEventListener('mousedown', e => { if (e.button === 1) e.preventDefault(); }); // pas de défilement auto
island.addEventListener('auxclick', e => {
  if (e.button !== 1 || state === 'open' || !hasMedia) return;
  invoke('media_action', { action: 'toggle' });
  showOsd(media.playing ? 'pause' : 'play_arrow', null, media.playing ? 'Pause' : 'Lecture');
});

// --- affichage éphémère dans la pilule (volume, lecture, sortie audio)
let osdTimer = null;
function showOsd(icon, frac, label) {
  const o = $('.pill-osd');
  o.querySelector('.ms').textContent = icon;
  o.querySelector('.osd-bar').hidden = frac == null;
  if (frac != null) o.querySelector('.osd-bar i').style.width = Math.min(100, frac * 100) + '%';
  o.querySelector('b').textContent = label;
  island.classList.add('osd');
  clearTimeout(osdTimer);
  osdTimer = setTimeout(() => island.classList.remove('osd'), 1300);
}

// --- volume à la molette (pas de 2 %) ; relu dans Windows après 3 s sans molette
let wheelVol = null;
let wheelAt = 0;
let wheelSteps = 0;
let wheelFetching = false;
async function wheelVolume(dy) {
  wheelSteps -= Math.sign(dy);
  if (wheelVol === null || performance.now() - wheelAt > 3000) {
    if (wheelFetching) return;
    wheelFetching = true;
    const v = await invoke('volume_get').catch(() => ({ level: 0.5, muted: false }));
    wheelFetching = false;
    wheelVol = v.muted ? 0 : Math.round(v.level * 100);
  }
  wheelAt = performance.now();
  wheelVol = Math.max(0, Math.min(100, wheelVol + wheelSteps * 2));
  wheelSteps = 0;
  showVolume(wheelVol / 100, false);
  applyVolume(wheelVol / 100, true);
  showOsd(wheelVol === 0 ? 'volume_off' : wheelVol < 50 ? 'volume_down' : 'volume_up', wheelVol / 100, wheelVol);
}
// Maj + molette : volume de l'appli au premier plan (jeu, navigateur...)
let fgBusy = false;
async function fgVolume(dy) {
  if (fgBusy) return;
  fgBusy = true;
  const r = await invoke('fg_volume', { step: dy < 0 ? 0.04 : -0.04 }).catch(() => null);
  fgBusy = false;
  if (!r) return showOsd('volume_off', null, 'Cette appli ne joue pas de son');
  const n = Math.round(r.level * 100);
  showOsd(n === 0 ? 'volume_off' : 'tune', r.level, `${mixName(r.exe)} · ${n}`);
}
addEventListener('keydown', e => {
  if (e.key === 'Escape' && state === 'open') close();
});
addEventListener('resize', reportHit);

// ================================================================ onglets
let currentTab = 'home';
const TABS = $$('#tabs button').map(b => b.dataset.tab);
$$('#tabs button').forEach(b => (b.title = b.querySelector('span:not(.ms)').textContent));

function showTab(tab) {
  const dir = TABS.indexOf(tab) > TABS.indexOf(currentTab) ? 1 : -1;
  currentTab = tab;
  if (typeof ctx !== 'undefined') hideCtx(); // le menu est commun à toutes les pages
  $$('#tabs button').forEach(b => b.classList.toggle('on', b.dataset.tab === tab));
  $$('.page').forEach(p => {
    const on = p.dataset.page === tab;
    p.style.setProperty('--dx', `${on ? 0 : -dir * 24}px`);
    p.classList.toggle('on', on);
  });
  moveIndicator();
  onTab(tab);
}
function moveIndicator() {
  const b = $('#tabs button.on');
  if (!b) return;
  const ind = $('.tab-ind');
  ind.style.left = b.offsetLeft + 'px';
  ind.style.width = b.offsetWidth + 'px';
}
$$('#tabs button').forEach(b => b.addEventListener('click', () => {
  showTab(b.dataset.tab);
  if (b.dataset.tab === 'apps') $('#q').focus();
}));
document.fonts.ready.then(moveIndicator);
// largeur des onglets changée (police d'icônes chargée, libellé actif) : on recale
new ResizeObserver(moveIndicator).observe($('#tabs'));

function onOpen() {
  moveIndicator();
  refreshVolume();
  refreshOutputs();
  onTab(currentTab);
}
function onTab(tab) {
  if (tab === 'walls' && !wallsLoaded) loadWalls();
  if (tab === 'apps') renderApps();
  if (tab === 'media') refreshAppVolume();
  // onglet PC : état des logiciels, du mode d'alimentation et du volume Discord
  clearInterval(pcTimer);
  if (tab === 'pc') { refreshPc(); pcTimer = setInterval(() => state === 'open' && currentTab === 'pc' ? refreshPc() : clearInterval(pcTimer), 3000); }
  if (tab === 'claude') setTimeout(() => $('.cl-in').focus(), 60);
  clearInterval(taskTimer);
  if (tab === 'tasks') { refreshTasks(); taskTimer = setInterval(() => state === 'open' && currentTab === 'tasks' ? refreshTasks() : clearInterval(taskTimer), 2000); }
}

// ================================================ gestionnaire des tâches
// processus regroupés par programme (src/tasks.rs), rafraîchis toutes les 2 s
let taskTimer = null;
let tasks = [];
let taskSort = 'cpu';
let taskArmed = ''; // fin de tâche en attente de confirmation
let taskBusy = false;
const fmtMem = b => b >= 1024 ** 3 ? (b / 1024 ** 3).toFixed(1) + ' Go' : Math.round(b / 1024 ** 2) + ' Mo';
// débit réseau en bits/s, comme Windows
const fmtNet = b => {
  const k = b * 8 / 1e3;
  return k < 1 ? '0' : k < 1000 ? Math.round(k) + ' k' : k < 10000 ? (k / 1e3).toFixed(1) + ' M' : Math.round(k / 1e3) + ' M';
};
const fmtRate = b => b < 0.05 * 1024 ** 2 ? '0 Mo/s' : (b / 1024 ** 2).toFixed(1) + ' Mo/s';
const DISK_FULL = 100 * 1024 ** 2; // 100 Mo/s = case « pleine »
const NET_FULL = 12.5 * 1024 ** 2; // 100 Mbit/s
const CONN_FULL = 40; // connexions actives
let netRate = { down: 0, up: 0 };
// une couleur par colonne (comme les graphiques de Windows), plus intense avec
// la charge ; au-delà de 75 % la case vire au rouge
const HUES = { cpu: 210, mem: 275, disk: 135, gpu: 330, net: 30 };
function heat(el, frac, kind) {
  const f = Math.max(0, Math.min(1, frac || 0));
  const hue = f >= 0.75 ? 0 : HUES[kind] ?? 50;
  el.style.setProperty('--heat', `hsl(${hue} 85% 55% / ${0.1 + 0.6 * Math.sqrt(f)})`);
  el.style.setProperty('--bar', `hsl(${hue} 90% 60%)`);
  el.style.setProperty('--fill', Math.max(f * 100, f > 0.002 ? 3 : 0) + '%');
  el.classList.toggle('hot', f >= 0.5);
}
let taskTot = { cpu: 0, gpu: 0, disk: 0, procs: 0 };
async function refreshTasks() {
  if (taskBusy) return;
  taskBusy = true;
  try {
    const r = await invoke('tasks_get');
    tasks = r.list;
    netRate = { down: r.net_down, up: r.net_up };
    taskTot = { cpu: r.cpu, gpu: r.gpu, disk: r.disk_active, procs: r.procs };
  } finally { taskBusy = false; }
  renderTasks();
}
// mêmes sections que l'onglet Processus du Gestionnaire des tâches
// en-tête des colonnes : remis en tête de liste à chaque rendu (position collante)
const TASK_HEAD = $('.task-headrow');
const TASK_KINDS = [['app', 'Applications'], ['bg', 'Processus en arrière-plan'], ['win', 'Processus Windows']];
function renderTasks() {
  const q = norm($('#task-q').value.trim());
  const by = {
    cpu: (x, y) => y.cpu - x.cpu || y.mem - x.mem,
    mem: (x, y) => y.mem - x.mem,
    disk: (x, y) => y.disk - x.disk || y.cpu - x.cpu,
    gpu: (x, y) => y.gpu - x.gpu || y.cpu - x.cpu,
    net: (x, y) => y.net - x.net || y.cpu - x.cpu,
    name: (x, y) => x.label.localeCompare(y.label, 'fr'),
  }[taskSort];
  const list = tasks.filter(t => !q || norm(t.label).includes(q) || norm(t.name).includes(q)).sort(by);
  const memTotal = lastSys?.mem_total || 16 * 1024 ** 3;
  const memUsed = lastSys ? lastSys.mem_used : tasks.reduce((n, t) => n + t.mem, 0);
  $('.task-sum').textContent = `${taskTot.procs} processus`;
  // en-têtes : totaux colorés, comme le Gestionnaire des tâches
  const head = (k, frac, text) => {
    const h = $(`.task-headrow [data-h="${k}"]`);
    heat(h, frac, k);
    h.querySelector('b').textContent = text;
  };
  head('cpu', taskTot.cpu / 100, Math.round(taskTot.cpu) + ' %');
  head('mem', memUsed / memTotal, Math.round(memUsed / memTotal * 100) + ' %');
  head('disk', taskTot.disk / 100, Math.round(taskTot.disk) + ' %');
  head('gpu', taskTot.gpu / 100, Math.round(taskTot.gpu) + ' %');
  head('net', (netRate.down + netRate.up) / NET_FULL, `↓${fmtNet(netRate.down)} ↑${fmtNet(netRate.up)}`);
  const box = $('.task-list');
  if (!list.length) { box.innerHTML = '<div class="empty">Aucun processus</div>'; box.prepend(TASK_HEAD); return; }
  box.innerHTML = '';
  box.append(TASK_HEAD);
  TASK_KINDS.forEach(([kind, title]) => {
    const part = list.filter(t => t.kind === kind);
    if (!part.length) return;
    const sec = document.createElement('div');
    sec.className = 'task-sec';
    sec.textContent = `${title} (${part.length})`;
    box.append(sec);
    part.forEach(t => box.append(taskRow(t, memTotal)));
  });
}
function taskRow(t, memTotal) {
  const row = document.createElement('div');
  row.className = 'task-row task';
  row.title = t.label !== t.name ? `${t.name}.exe` : '';
  row.innerHTML = t.icon ? `<img src="${t.icon}" alt="">` : '<span class="ms">memory</span>';
  const name = document.createElement('span');
  name.className = 'task-name';
  name.textContent = t.label;
  if (t.count > 1) name.insertAdjacentHTML('beforeend', ` <i>(${t.count})</i>`);
  row.append(name);
  [
    ['cpu', t.cpu / 100, t.cpu.toFixed(1).replace('.', ',') + ' %'],
    ['mem', t.mem / memTotal, fmtMem(t.mem)],
    ['disk', t.disk / DISK_FULL, fmtRate(t.disk)],
    ['gpu', t.gpu / 100, t.gpu >= 0.05 ? t.gpu.toFixed(1).replace('.', ',') + ' %' : '0 %'],
    ['net', t.net / CONN_FULL, t.net ? `${t.net} conn.` : '–'],
  ].forEach(([kind, frac, text]) => {
    const c = document.createElement('span');
    c.className = 'task-cell';
    c.textContent = text;
    heat(c, frac, kind);
    row.append(c);
  });
  const kill = document.createElement('button');
  kill.className = 'task-kill' + (taskArmed === t.name ? ' armed' : '');
  kill.disabled = t.protected;
  kill.title = t.protected ? 'Processus Windows protégé' : 'Fin de tâche';
  kill.innerHTML = `<span class="ms">${t.protected ? 'shield' : taskArmed === t.name ? 'check' : 'close'}</span>`;
  if (taskArmed === t.name) kill.title = 'Clique encore pour confirmer';
  kill.addEventListener('click', async () => {
    // premier clic : arme ; second clic : termine tous les processus du programme
    if (taskArmed !== t.name) {
      taskArmed = t.name;
      renderTasks();
      setTimeout(() => { if (taskArmed === t.name) { taskArmed = ''; renderTasks(); } }, 3000);
      return;
    }
    taskArmed = '';
    await invoke('task_kill', { name: t.name });
    refreshTasks();
  });
  row.append(kill);
  return row;
}
$$('.task-seg button').forEach(b => b.addEventListener('click', () => {
  taskSort = b.dataset.s;
  $$('.task-seg button').forEach(x => x.classList.toggle('on', x === b));
  renderTasks();
}));
$('#task-q').addEventListener('input', renderTasks);
$('#taskmgr').addEventListener('click', () => { invoke('taskmgr_open'); setState('collapsed'); });

// ================================================================ Claude
// la question part dans l'application Claude (lien claude://, comme les
// raccourcis du menu Démarrer) : rien ne passe par l'API
let clMode = 'chat';
let clHist = []; // %LOCALAPPDATA%\Ilot\claude.json : { hist: [...] }
invoke('store_get', { key: 'claude' }).then(c => { if (c && Array.isArray(c.hist)) clHist = c.hist; renderClaudeHist(); });
const CL_QUICK = [
  ['summarize', 'Résumer', 'Résume ce texte en quelques points :'],
  ['help', 'Expliquer', 'Explique-moi simplement :'],
  ['spellcheck', 'Corriger', 'Corrige l’orthographe et la grammaire de ce texte, sans changer le sens :'],
  ['translate', 'En français', 'Traduis en français :'],
  ['reply', 'Répondre', 'Aide-moi à répondre à ce message :'],
  ['code', 'Code', 'Explique ce code et signale les bugs éventuels :'],
];
const clIn = $('.cl-in');
CL_QUICK.forEach(([icon, label, prompt]) => {
  const b = document.createElement('button');
  b.title = `${prompt} + dernier texte copié`;
  b.innerHTML = `<span class="ms">${icon}</span>${label}`;
  b.addEventListener('click', async () => {
    const [last] = await invoke('clips_get');
    if (!last) { $('.cl-note').textContent = 'Copie d’abord un texte (Ctrl+C)'; return; }
    clIn.value = `${prompt}\n\n${last}`.slice(0, 6000);
    clIn.focus();
  });
  $('.cl-quick').append(b);
});
function askClaude(text) {
  text = text.trim();
  if (!text) return;
  const host = clMode === 'cowork' ? 'cowork' : 'claude.ai';
  invoke('open_url', { url: `claude://${host}/new?q=${encodeURIComponent(text)}` });
  clHist = [text, ...clHist.filter(t => t !== text)].slice(0, 20);
  invoke('store_set', { key: 'claude', value: { hist: clHist } });
  renderClaudeHist();
  clIn.value = '';
  $('.cl-note').textContent = 'Envoyé : valide dans Claude avec Entrée';
  setState('collapsed');
}
function renderClaudeHist() {
  const box = $('.cl-hist');
  box.innerHTML = clHist.length ? '' : '<div class="sp-hint">Tes questions apparaîtront ici.</div>';
  clHist.forEach(t => {
    const b = document.createElement('button');
    b.textContent = t;
    b.title = 'Reprendre cette question';
    b.addEventListener('click', () => { clIn.value = t; clIn.focus(); });
    box.append(b);
  });
}
clIn.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); askClaude(clIn.value); }
});
clIn.addEventListener('focus', () => { pinned = true; });
clIn.addEventListener('input', () => { $('.cl-note').textContent = ''; });
$('#cl-send').addEventListener('click', () => askClaude(clIn.value));
$('#cl-open').addEventListener('click', () => { invoke('open_url', { url: 'claude://claude.ai/new' }); setState('collapsed'); });
$('#cl-code').addEventListener('click', () => { invoke('open_url', { url: 'claude://code/new' }); setState('collapsed'); });
$$('.cl-seg button').forEach(b => b.addEventListener('click', () => {
  clMode = b.dataset.m;
  $$('.cl-seg button').forEach(x => x.classList.toggle('on', x === b));
  clIn.focus();
}));

// ================================================================ horloge
// pilule : Apparence > Horloge de la pilule (classique, volets, aiguilles, néon, pixel)
let ckStyle = '', ckText = '';
const CLOCK_W = { flip: 10, analog: -16, pixel: 6 };
function renderMiniClock(d, hh, mm) {
  const el = $('.mini-clock');
  const st = (typeof theme !== 'undefined' && theme.clock) || 'digital';
  if (st !== ckStyle) {
    ckStyle = st; ckText = '';
    el.className = 'mini-clock ck-' + st;
    el.innerHTML = '';
    if ((CLOCK_W[st] || 0) !== clockExtra) { clockExtra = CLOCK_W[st] || 0; reportHit(); }
  }
  if (ckText === hh + mm) return;
  const first = !ckText;
  ckText = hh + mm;
  el.title = `${hh}:${mm}`;
  if (st === 'analog') {
    const ha = (d.getHours() % 12) * 30 + d.getMinutes() * 0.5, ma = d.getMinutes() * 6;
    el.innerHTML = `<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="8.4"/><line class="h" x1="10" y1="10" x2="10" y2="5.6" transform="rotate(${ha} 10 10)"/>`
      + `<line class="m" x1="10" y1="10" x2="10" y2="3.4" transform="rotate(${ma} 10 10)"/><circle class="c" cx="10" cy="10" r="1.3"/></svg>`;
  } else if (st === 'flip') {
    if (!el.querySelector('.fd')) el.innerHTML = '<b class="fd"></b><b class="fd"></b><i>:</i><b class="fd"></b><b class="fd"></b>';
    const ds = el.querySelectorAll('.fd');
    [...(hh + mm)].forEach((c, i) => {
      if (ds[i].textContent === c) return;
      ds[i].textContent = c;
      if (first) return;
      ds[i].classList.remove('go'); void ds[i].offsetWidth; ds[i].classList.add('go');
    });
  } else el.textContent = `${hh}:${mm}`;
}
const fmtDate = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
const fmtShort = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
function tickClock() {
  const d = new Date();
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  $('.peek-clock').textContent = `${hh}:${mm}`;
  renderMiniClock(d, hh, mm);
  $('.big-clock .hh').textContent = hh;
  $('.big-clock .mm').textContent = mm;
  $('.big-date').textContent = fmtDate.format(d);
  $('.peek-date').textContent = fmtShort.format(d);
  if (d.getDate() !== calToday) { calToday = d.getDate(); renderCal(); }
}
setInterval(tickClock, 1000);

// ============================================================ calendrier
let calOffset = 0;
let calToday = -1;
const fmtMonth = new Intl.DateTimeFormat('fr-FR', { month: 'long', year: 'numeric' });
function renderCal() {
  const now = new Date();
  const first = new Date(now.getFullYear(), now.getMonth() + calOffset, 1);
  $('.cal-title').textContent = fmtMonth.format(first);
  const grid = $('.cal-grid');
  grid.innerHTML = ['L', 'M', 'M', 'J', 'V', 'S', 'D'].map(d => `<span class="dow">${d}</span>`).join('');
  const start = (first.getDay() + 6) % 7; // lundi en premier
  const day = new Date(first);
  day.setDate(1 - start);
  for (let i = 0; i < 42; i++) {
    const out = day.getMonth() !== first.getMonth();
    const today = day.toDateString() === now.toDateString();
    const we = i % 7 >= 5;
    const key = dayKey(day);
    const el = document.createElement('span');
    el.className = `d${out ? ' out' : ''}${today ? ' today' : ''}${we ? ' we' : ''}${calNotes[key] ? ' noted' : ''}`;
    el.textContent = day.getDate();
    if (calNotes[key]) el.title = calNotes[key];
    el.addEventListener('click', () => openNote(key));
    grid.append(el);
    day.setDate(day.getDate() + 1);
  }
}
$$('[data-cal]').forEach(b => b.addEventListener('click', () => {
  calOffset += Number(b.dataset.cal);
  renderCal();
}));

// --- notes par date, dans %LOCALAPPDATA%\Ilot\calnotes.json : { "AAAA-MM-JJ": "texte" }
let calNotes = {};
let noteKey = null;
const dayKey = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const fmtNoteDate = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
const calNote = $('.cal-note');
const calText = $('.cal-note textarea');
function openNote(key) {
  noteKey = key;
  const [y, m, d] = key.split('-').map(Number);
  $('.cal-note-date').textContent = fmtNoteDate.format(new Date(y, m - 1, d));
  calText.value = calNotes[key] || '';
  calNote.hidden = false;
  calText.focus();
}
function closeNote() {
  calNote.hidden = true;
  noteKey = null;
  renderCal();
}
function saveCalNotes() { invoke('store_set', { key: 'calnotes', value: calNotes }); }
calText.addEventListener('input', () => {
  const t = calText.value.trim();
  if (t) calNotes[noteKey] = calText.value; else delete calNotes[noteKey];
  saveCalNotes();
});
calText.addEventListener('keydown', e => {
  if (e.key === 'Escape') { e.stopPropagation(); closeNote(); }
});
$('[data-note="close"]').addEventListener('click', closeNote);
$('[data-note="del"]').addEventListener('click', () => {
  delete calNotes[noteKey];
  saveCalNotes();
  closeNote();
});
invoke('store_get', { key: 'calnotes' }).then(n => { if (n && typeof n === 'object') { calNotes = n; renderCal(); } });

// ================================================================== météo
// Open-Meteo (sans clé) ; position : ville choisie (weather.json) ou par IP
const WMO = [
  [[0], 'clear_day', 'Ensoleillé'], [[1], 'partly_cloudy_day', 'Peu nuageux'],
  [[2], 'partly_cloudy_day', 'Partiellement nuageux'], [[3], 'cloud', 'Couvert'],
  [[45, 48], 'foggy', 'Brouillard'], [[51, 53, 55, 56, 57], 'rainy_light', 'Bruine'],
  [[61, 63, 66, 80, 81], 'rainy', 'Pluie'], [[65, 67, 82], 'rainy_heavy', 'Forte pluie'],
  [[71, 73, 75, 77, 85, 86], 'weather_snowy', 'Neige'], [[95, 96, 99], 'thunderstorm', 'Orage'],
];
let wPlace = null; // { name, lat, lon, manual }
let sunTimes = null; // [lever, coucher] en minutes depuis minuit (thème « Soleil »)
async function locate() {
  const saved = await invoke('store_get', { key: 'weather' });
  if (saved && saved.manual) return saved;
  const r = await fetch('https://get.geojs.io/v1/ip/geo.json').then(r => r.json());
  // l'IP d'une box 4G est souvent mal placée : clic sur la météo pour choisir sa ville
  return { name: r.city || r.region || 'Position auto', lat: Number(r.latitude), lon: Number(r.longitude) };
}
async function refreshWeather() {
  try {
    if (!wPlace) wPlace = await locate();
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${wPlace.lat}&longitude=${wPlace.lon}`
      + '&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto&forecast_days=1';
    const w = await fetch(url).then(r => r.json());
    if (!w.current) throw new Error(w.reason || 'météo');
    const code = w.current.weather_code;
    let [, icon, label] = WMO.find(([c]) => c.includes(code)) || [, 'cloud', 'Météo'];
    if (!w.current.is_day) icon = icon.replace('clear_day', 'clear_night').replace('partly_cloudy_day', 'partly_cloudy_night');
    $('.w-icon').textContent = icon;
    wxKind = !w.current.is_day && code <= 1 ? 'night' : code <= 1 ? 'sun' : code <= 3 ? 'cloud' : code <= 48 ? 'fog'
      : code >= 95 ? 'storm' : (code >= 71 && code <= 77) || code === 85 || code === 86 ? 'snow'
      : [65, 67, 82].includes(code) ? 'heavy' : 'rain';
    applyWeatherFx();
    $('.w-temp').textContent = Math.round(w.current.temperature_2m) + '°';
    $('.w-city').textContent = wPlace.name;
    // « 2026-10-16T08:12 » -> minutes
    const mins = s => s ? Number(s.slice(11, 13)) * 60 + Number(s.slice(14, 16)) : NaN;
    const sun = [mins(w.daily.sunrise?.[0]), mins(w.daily.sunset?.[0])];
    if (sun.every(Number.isFinite)) { sunTimes = sun; checkDarkSchedule(); }
    $('.weather').title = `${label} · min ${Math.round(w.daily.temperature_2m_min[0])}° / max ${Math.round(w.daily.temperature_2m_max[0])}°\nClic pour changer de ville`;
  } catch {
    $('.w-city').textContent = 'Météo indisponible';
    // service saturé ou hors ligne : on réessaie plus tôt
    clearTimeout(wRetry);
    wRetry = setTimeout(refreshWeather, 3 * 60 * 1000);
  }
}
let wRetry = null;
// --- météo animée derrière la pilule (Apparence > Météo animée)
let wxKind = '';
const WX_CLASSES = ['wx-sun', 'wx-night', 'wx-cloud', 'wx-fog', 'wx-rain', 'wx-heavy', 'wx-snow', 'wx-storm'];
(() => {
  // gouttes / flocons / étoiles : positions et rythmes tirés au hasard une fois
  const fx = $('.wx-fx');
  for (let i = 0; i < 18; i++) {
    const d = document.createElement('i');
    d.style.setProperty('--x', (Math.random() * 100).toFixed(1) + '%');
    d.style.setProperty('--y', (Math.random() * 90).toFixed(1) + '%');
    d.style.setProperty('--d', (0.55 + Math.random() * 0.5).toFixed(2) + 's');
    d.style.setProperty('--w', (-Math.random() * 3).toFixed(2) + 's');
    fx.append(d);
  }
})();
function applyWeatherFx() {
  island.classList.remove(...WX_CLASSES);
  if (theme.wxfx === 'off' || !wxKind) return;
  island.classList.add('wx-' + wxKind);
  if (wxKind === 'heavy') island.classList.add('wx-rain');
}
const wInput = $('.w-input');
$('.weather').addEventListener('click', () => {
  wInput.value = wPlace && wPlace.manual ? wPlace.name : '';
  wInput.hidden = false;
  $('.weather').hidden = true;
  wInput.focus();
});
function closeWeatherInput() { wInput.hidden = true; $('.weather').hidden = false; }
wInput.addEventListener('blur', closeWeatherInput);
wInput.addEventListener('keydown', async e => {
  e.stopPropagation();
  if (e.key === 'Escape') return closeWeatherInput();
  if (e.key !== 'Enter') return;
  const q = wInput.value.trim();
  if (!q) {
    // vide : retour à la position automatique
    invoke('store_set', { key: 'weather', value: {} });
    wPlace = null;
  } else {
    try {
      const g = await fetch(`https://geocoding-api.open-meteo.com/v1/search?count=1&language=fr&name=${encodeURIComponent(q)}`).then(r => r.json());
      const p = g.results && g.results[0];
      if (!p) { wInput.value = ''; wInput.placeholder = 'Ville introuvable'; return; }
      wPlace = { name: p.name, lat: p.latitude, lon: p.longitude, manual: true };
      invoke('store_set', { key: 'weather', value: wPlace });
    } catch { return; }
  }
  closeWeatherInput();
  refreshWeather();
});
refreshWeather();
setInterval(refreshWeather, 30 * 60 * 1000);

// ================================================================== média
let media = { has: false };
let mediaAt = 0;
const fmtTime = s => {
  s = Math.max(0, Math.floor(s));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};
function position() {
  if (!media.has) return 0;
  let p = media.position + (media.playing ? (performance.now() - mediaAt) / 1000 : 0);
  return media.duration ? Math.min(p, media.duration) : p;
}
function applyMedia(m) {
  media = m;
  mediaAt = performance.now();
  const had = hasMedia;
  hasMedia = m.has && !!(m.title || m.artist);
  island.classList.toggle('media', hasMedia);
  island.classList.toggle('playing', hasMedia && m.playing);
  if (had !== hasMedia) reportHit();
  const title = hasMedia ? m.title || 'Sans titre' : 'Rien en lecture';
  $('.peek-title').textContent = $('.hm-title').textContent = $('.mp-title').textContent = title;
  $('.peek-artist').textContent = $('.hm-artist').textContent = $('.mp-artist').textContent = hasMedia ? m.artist : '';
  $('.mp-album').textContent = hasMedia ? m.album : '';
  $('.mp-app').textContent = hasMedia ? m.app : '';
  $$('.play-icon').forEach(i => (i.textContent = m.playing ? 'pause' : 'play_arrow'));
  updateProgress();
  syncViz();
}

// ============================================================ visualiseur
// bandes de fréquences du son joué par le PC (src/viz.rs, capture loopback),
// capturées seulement pendant la lecture, îlot visible
const VIZ_BANDS = 48;
let spec = new Array(VIZ_BANDS).fill(0); // dernière mesure (0-1)
const shown = new Array(VIZ_BANDS).fill(0); // valeurs affichées, lissées
let vizOn = false;
let vizLoop = false;
function syncViz() {
  const want = hasMedia && media.playing && !island.classList.contains('hidden');
  if (want === vizOn) return;
  vizOn = want;
  invoke('viz_set', { on: want });
  island.classList.toggle('viz', want);
  if (want && !vizLoop) { vizLoop = true; requestAnimationFrame(drawViz); }
}
listen('spectrum', ({ payload }) => { spec = payload.map(v => v / 255); });
let vizColors = null;
let vizColorsAt = 0;
function drawViz(t) {
  let energy = 0;
  for (let i = 0; i < VIZ_BANDS; i++) {
    // montée rapide, retombée douce
    const s = vizOn ? spec[i] : 0;
    shown[i] = s > shown[i] ? shown[i] + (s - shown[i]) * 0.55 : shown[i] * 0.86 + s * 0.14;
    energy += shown[i];
  }
  // couleurs du thème (relues de temps en temps : elles suivent la pochette / le fond)
  if (!vizColors || t - vizColorsAt > 1000) {
    const cs = getComputedStyle(document.documentElement);
    vizColors = ['--primary', '--tertiary', '--secondary'].map(v => cs.getPropertyValue(v).trim() || '#cfbdfe');
    vizColorsAt = t;
  }
  // pilule : les 3 barres suivent graves / médiums / aigus
  const eq = $$('.eq i');
  [[0, 8], [8, 24], [24, 48]].forEach(([a, b], k) => {
    const avg = shown.slice(a, b).reduce((x, y) => x + y, 0) / (b - a);
    if (eq[k]) eq[k].style.height = (3 + avg * 11).toFixed(1) + 'px';
  });
  if (petShown && state === 'collapsed') {
    const bass = shown.slice(0, 6).reduce((x, y) => x + y, 0) / 6;
    $('.pet').style.setProperty('--bop', bass.toFixed(3));
  }
  // aurore boréale : les voiles suivent graves / médiums / aigus
  if (island.classList.contains('aurora-bg')) {
    const band = (a, b) => shown.slice(a, b).reduce((x, y) => x + y, 0) / (b - a);
    const au = $('.island-aurora');
    au.style.setProperty('--ab', band(0, 6).toFixed(3));
    au.style.setProperty('--am', band(6, 24).toFixed(3));
    au.style.setProperty('--ah', band(24, 48).toFixed(3));
  }
  if (state === 'open' && currentTab === 'media') drawBars($('.viz-mp'), { mirror: true });
  if (state === 'open' && currentTab === 'home') { drawBars($('.viz-home'), { mirror: false }); drawRing(); }
  if (vizOn || energy > 0.02) requestAnimationFrame(drawViz);
  else {
    vizLoop = false;
    $$('.eq i').forEach(i => (i.style.height = ''));
    ['--ab', '--am', '--ah'].forEach(v => $('.island-aurora').style.removeProperty(v));
  }
}
// Accueil : barres en cercle autour du disque (graves en haut, symétrique)
function drawRing() {
  const c = $('.disc-viz');
  const w = c.clientWidth, h = c.clientHeight;
  if (!w || !h) return;
  const dpr = devicePixelRatio || 1;
  if (c.width !== Math.round(w * dpr)) { c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); }
  const g = c.getContext('2d');
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, w, h);
  const bass = shown.slice(0, 6).reduce((x, y) => x + y, 0) / 6;
  $('.disc').style.setProperty('--beat', (1 + bass * 0.07).toFixed(3));
  const cx = w / 2, cy = h / 2;
  const r0 = 69 + 7; // rayon du disque + son liseré
  const n = VIZ_BANDS * 2;
  g.lineCap = 'round';
  g.lineWidth = 2.6;
  // halo qui respire avec les basses
  g.shadowColor = vizColors[0];
  g.shadowBlur = 4 + bass * 14;
  for (let i = 0; i < n; i++) {
    const band = i < VIZ_BANDS ? i : n - 1 - i;
    const v = shown[band];
    if (v < 0.01) continue;
    const a = (i / n) * Math.PI * 2 - Math.PI / 2;
    const len = 2 + v * 20;
    g.strokeStyle = vizColors[band < 16 ? 0 : band < 32 ? 1 : 2];
    g.globalAlpha = 0.45 + v * 0.55;
    g.beginPath();
    g.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0);
    g.lineTo(cx + Math.cos(a) * (r0 + len), cy + Math.sin(a) * (r0 + len));
    g.stroke();
  }
  g.globalAlpha = 1;
}
function drawBars(c, { mirror }) {
  const w = c.clientWidth, h = c.clientHeight;
  if (!w || !h) return;
  const dpr = devicePixelRatio || 1;
  if (c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) { c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); }
  const g = c.getContext('2d');
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, w, h);
  // en miroir : graves au centre, aigus vers les bords
  const n = mirror ? VIZ_BANDS * 2 : VIZ_BANDS;
  const gap = mirror ? 3 : 2;
  const bw = (w - gap * (n - 1)) / n;
  const grad = g.createLinearGradient(0, h, 0, 0);
  grad.addColorStop(0, vizColors[0]);
  grad.addColorStop(0.6, vizColors[1]);
  grad.addColorStop(1, vizColors[2]);
  g.fillStyle = grad;
  for (let i = 0; i < n; i++) {
    const band = mirror ? (i < VIZ_BANDS ? VIZ_BANDS - 1 - i : i - VIZ_BANDS) : i;
    const v = shown[band];
    const bh = Math.max(2, v * h);
    const x = i * (bw + gap);
    g.beginPath();
    g.roundRect(x, h - bh, bw, bh, Math.min(bw / 2, 4));
    g.fill();
  }
}
let seeking = false;
function updateProgress() {
  const p = position();
  const pct = media.duration ? (p / media.duration) * 100 : 0;
  $('.peek-bar div').style.width = pct + '%';
  if (!seeking) {
    const seek = $('#seek');
    seek.value = pct * 10;
    seek.style.setProperty('--p', pct + '%');
    $('.t-pos').textContent = fmtTime(p);
  }
  $('.t-dur').textContent = fmtTime(media.duration || 0);
}
setInterval(() => media.playing && updateProgress(), 500);

let currentArt = ''; // pochette en cours (data URL), source du thème « Pochette »
function applyArt(src) {
  $$('.mini-art, .peek-art, .disc-art, .mp-art img').forEach(i => {
    if (src) i.src = src; else i.removeAttribute('src');
  });
  $('.mp-bg').style.backgroundImage = src ? `url("${src}")` : 'none';
  const changed = (src || '') !== currentArt;
  currentArt = src || '';
  if (changed && theme.color === 'art') themeFrom(currentThumb);
}

listen('media', ({ payload }) => applyMedia(payload));
listen('media-art', ({ payload }) => applyArt(payload));
invoke('media_get').then(applyMedia);
invoke('media_art').then(applyArt);

document.addEventListener('click', e => {
  const b = e.target.closest('[data-media]');
  if (!b) return;
  e.stopPropagation();
  const action = b.dataset.media;
  if (action === 'toggle') { // retour visuel immédiat
    media.playing = !media.playing;
    applyMedia({ ...media, position: position() });
  }
  invoke('media_action', { action });
});
const seek = $('#seek');
seek.addEventListener('input', () => {
  seeking = true;
  seek.style.setProperty('--p', seek.value / 10 + '%');
  $('.t-pos').textContent = fmtTime((seek.value / 1000) * (media.duration || 0));
});
seek.addEventListener('change', () => {
  const v = (seek.value / 1000) * (media.duration || 0);
  invoke('media_action', { action: 'seek', value: v });
  media.position = v;
  mediaAt = performance.now();
  seeking = false;
});

// ================================================================= volume
// 0-100 % : volume Windows ; 100-200 % : Windows à 100 % + gain réel par le
// « Preamp » d'Equalizer APO (src/boost.rs), si Equalizer APO est installé
const vol = $('#vol');
let volBusy = false;
let boost = null; // gain actuel (1 = 100 %), null sans Equalizer APO
let boostAt = 0;
function showVolume(level, muted) {
  const v = Math.round(level * 100);
  const max = Number(vol.max);
  vol.value = v;
  vol.style.setProperty('--p', (muted ? 0 : v / max * 100) + '%');
  $('.vol-card').classList.toggle('boost', !muted && v > 100);
  $('.vol-val').textContent = muted ? '–' : v;
  $('.vol-icon').textContent = muted || v === 0 ? 'volume_off' : v > 100 ? 'campaign' : v < 50 ? 'volume_down' : 'volume_up';
  vol.dataset.muted = muted;
}
async function refreshVolume() {
  const [v, b] = await Promise.all([invoke('volume_get'), invoke('boost_get')]);
  boost = b;
  vol.max = boost === null ? 100 : 200;
  vol.title = boost === null ? '' : 'Au-delà de 100 % : gain réel par Equalizer APO (attention à la saturation)';
  // volume Windows baissé ailleurs (touches, mélangeur) : le gain n'a plus lieu d'être
  if (boost > 1 && v.level < 0.99) { boost = 1; invoke('boost_set', { gain: 1 }); }
  showVolume(boost > 1 ? boost : v.level, v.muted);
}
// applique un niveau 0-2 (au-delà de 1 : gain Equalizer APO)
// le fichier d'Equalizer APO n'est réécrit qu'une fois toutes les 80 ms pendant
// qu'on fait glisser ; la valeur finale (force) est toujours appliquée
function applyVolume(level, force = false) {
  if (boost === null) level = Math.min(level, 1);
  const p = invoke('volume_set', { level: Math.min(level, 1), muted: false });
  if (boost === null) return p;
  const g = Math.max(1, level);
  const now = performance.now();
  if (g !== boost && (force || g === 1 || now - boostAt > 80)) {
    boost = g;
    boostAt = now;
    invoke('boost_set', { gain: g });
  }
  return p;
}
vol.addEventListener('input', () => {
  showVolume(vol.value / 100, false);
  if (volBusy) return;
  volBusy = true;
  applyVolume(vol.value / 100).finally(() => (volBusy = false));
});
vol.addEventListener('change', () => applyVolume(vol.value / 100, true));
vol.addEventListener('wheel', e => {
  e.stopPropagation();
  const v = Math.max(0, Math.min(Number(vol.max), Number(vol.value) - Math.sign(e.deltaY) * 5));
  showVolume(v / 100, false);
  applyVolume(v / 100, true);
}, { passive: true });
// --- sortie audio (onglet PC) : toutes les sorties actives, clic = la choisir
let outputs = [];
const outIcon = n => /casque|headset|headphone|écouteur|hyperx|arctis|airpods|buds/i.test(n) ? 'headphones'
  : /hdmi|nvidia|tv|écran|moniteur|display/i.test(n) ? 'tv' : /usb/i.test(n) ? 'usb' : 'speaker';
// « Casque (HyperX Cloud III) » -> « HyperX Cloud III » ; « Haut-parleurs (Realtek(R) Audio) » reste entier
const outShort = n => { const m = n.match(/^(Casque|Headset|Headphones)\s*\((.+)\)$/i); return m ? m[2] : n; };
async function refreshOutputs() {
  outputs = await invoke('audio_outputs').catch(() => []);
  const box = $('.out-list');
  box.innerHTML = outputs.length ? '' : '<div class="sp-hint">Aucune sortie audio active.</div>';
  outputs.forEach(o => {
    const b = document.createElement('button');
    b.className = 'out' + (o.default ? ' on' : '');
    b.title = o.name;
    b.innerHTML = `<span class="ms">${outIcon(o.name)}</span><span class="out-name"></span>${o.default ? '<span class="ms out-check">check</span>' : ''}`;
    b.querySelector('.out-name').textContent = outShort(o.name);
    b.addEventListener('click', () => setOutput(o.id));
    box.append(b);
  });
}
async function setOutput(id) {
  const cur = outputs.find(o => o.default);
  if (cur && cur.id === id) return;
  if (!await invoke('audio_output_set', { id })) return;
  await refreshOutputs();
  refreshVolume();
  wheelVol = null; // le volume dépend de la sortie
  const now = outputs.find(o => o.id === id);
  if (now && state !== 'open') showOsd(outIcon(now.name), null, outShort(now.name));
}
refreshOutputs();

$('#mute').addEventListener('click', () => {
  const muted = vol.dataset.muted !== 'true';
  showVolume(vol.value / 100, muted);
  invoke('volume_set', { muted });
});

// ============================================================= ressources
const CIRC = 2 * Math.PI * 18;
function gauge(name, frac, label) {
  const g = $(`.gauge[data-g="${name}"]`);
  g.querySelector('.val').style.strokeDashoffset = CIRC * (1 - Math.max(0, Math.min(1, frac)));
  g.querySelector('em').textContent = label;
  g.classList.toggle('hot', frac > 0.9);
}
const gb = b => (b / 1024 ** 3).toFixed(b > 100 * 1024 ** 3 ? 0 : 1);
let lastSys = null;
// tous les disques : lettre, barre d'occupation, place libre (survol : nom du volume)
const fmtFree = b => b >= 1024 ** 4 ? (b / 1024 ** 4).toFixed(2).replace('.', ',') + ' To' : Math.round(b / 1024 ** 3) + ' Go';
function renderDisks(list) {
  const box = $('.disks');
  const key = list.map(d => d.mount).join();
  if (box.dataset.key !== key) {
    box.dataset.key = key;
    box.innerHTML = list.map(d => `<div class="disk"><span class="ms">${d.removable ? 'usb' : 'hard_drive'}</span><b>${d.mount}</b><span class="dk-bar"><i></i></span><em></em></div>`).join('');
  }
  list.forEach((d, i) => {
    const row = box.children[i];
    const frac = d.used / d.total;
    row.classList.toggle('hot', frac > 0.9);
    row.querySelector('i').style.width = (frac * 100).toFixed(1) + '%';
    row.querySelector('em').textContent = fmtFree(d.total - d.used) + ' libres';
    row.title = `${d.label ? d.label + ' (' + d.mount + ')' : d.mount}\n${fmtFree(d.used)} utilisés sur ${fmtFree(d.total)}`;
  });
}
listen('sys',({ payload: r }) => {
  lastSys = r;
  gauge('cpu', r.cpu / 100, Math.round(r.cpu) + ' %');
  gauge('mem', r.mem_used / r.mem_total, `${gb(r.mem_used)} / ${gb(r.mem_total)} Go`);
  renderDisks(r.disks || []);
  const bat = $('.gauge[data-g="bat"]');
  bat.hidden = r.battery < 0;
  if (r.battery >= 0) gauge('bat', r.battery / 100, r.battery + (r.charging ? ' % ⚡' : ' %'));
});

// ================================================================ session
$$('.sess').forEach(b => b.addEventListener('click', () => {
  // les actions lourdes demandent un second clic
  if (b.hasAttribute('data-confirm') && !b.classList.contains('armed')) {
    $$('.sess.armed').forEach(x => x.classList.remove('armed'));
    b.classList.add('armed');
    b.title = b.title.replace(/ \?$/, '') + ' ?';
    setTimeout(() => b.classList.remove('armed'), 3000);
    return;
  }
  b.classList.remove('armed');
  setState('collapsed');
  invoke('session_action', { action: b.dataset.sess });
}));

// =================================================================== apps
let apps = [];
let games = [];
const GAMES = '@games'; // pseudo-dossier « Launcher de jeux »
const SOURCE = { steam: 'Steam', epic: 'Epic', ubisoft: 'Ubisoft', gog: 'GOG' };
let appSel = 0;
let appView = [];
const norm = s => s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
function renderApps() {
  renderFolders();
  const q = norm($('#q').value.trim());
  const folder = folders.list.find(f => f.id === folders.sel);
  const inGames = folders.sel === GAMES;
  const pool = sortItems(inGames ? launcherItems() : folder ? folderItems(folder) : apps.filter(a => !isHidden(a.id)));
  appView = !q ? pool : pool
    .map(a => {
      const n = norm(a.name);
      const score = n.startsWith(q) ? 0 : n.split(/[\s\-_.]/).some(w => w.startsWith(q)) ? 1 : n.includes(q) ? 2 : 9;
      return { a, score };
    })
    .filter(x => x.score < 9)
    .sort((x, y) => x.score - y.score)
    .map(x => x.a);
  appSel = Math.min(appSel, Math.max(0, appView.length - 1));
  const grid = $('.app-grid');
  grid.classList.toggle('games', inGames);
  if (inGames) return renderGames(grid, q);
  if (!apps.length) { grid.innerHTML = '<div class="empty">Chargement des applications…</div>'; return; }
  if (!appView.length) {
    grid.innerHTML = folder && !q
      ? '<div class="empty">Dossier vide : glisse une appli sur le dossier, dépose un fichier ici, ou clic droit sur une application.</div>'
      : '<div class="empty">Aucune application</div>';
    return;
  }
  grid.innerHTML = '';
  appView.forEach((a, i) => {
    const el = document.createElement('button');
    el.className = 'app' + (q && i === appSel ? ' sel' : '') + (a.missing ? ' missing' : '');
    el.title = (a.file ? a.file : a.name) + (a.added ? `\nAjoutée le ${fmtAdded.format(a.added)}` : '');
    el.innerHTML = a.icon ? `<img src="${a.icon}" alt="">` : `<div class="ph">${a.name[0] || '?'}</div>`;
    const label = document.createElement('span');
    label.textContent = a.name;
    el.append(label);
    el.addEventListener('click', () => { if (!dragJustEnded) launch(a); });
    el.addEventListener('contextmenu', e => { e.preventDefault(); appMenu(a, e); });
    el.addEventListener('pointerdown', e => dragStart(a, el, e));
    grid.append(el);
  });
}

// --------------------------------------------- glisser une appli sur un dossier
// fait à la main (pointer events) : le glisser-déposer HTML5 est désactivé par
// la webview tant qu'elle accepte les fichiers venus de l'Explorateur
let drag = null;
let dragJustEnded = false;
function dragStart(a, el, e) {
  if (e.button !== 0) return;
  drag = { a, el, x: e.clientX, y: e.clientY, ghost: null };
}
function chipAt(x, y) {
  const c = document.elementFromPoint(x, y)?.closest('.fchip[data-id]');
  return c && findFolder(c.dataset.id) ? c : null;
}
// dossier réel, ou le Launcher (jeux détectés + éléments ajoutés à la main)
function findFolder(id) {
  return id === GAMES ? launcherFolder() : folders.list.find(f => f.id === id);
}
function launcherFolder() {
  folders.games = folders.games || [];
  return {
    id: GAMES, name: 'Launcher',
    get apps() { return folders.games; },
    set apps(v) { folders.games = v; },
  };
}
const isHiddenGame = id => (folders.hiddenGames || []).includes(id);
function launcherItems() {
  const extra = (folders.games || [])
    .map(id => id.startsWith(FILE) ? fileItem(id) : apps.find(a => a.id === id))
    .filter(Boolean);
  return [...games.filter(g => !isHiddenGame(g.id)), ...extra];
}
function markDrop(chip) {
  $$('.fchip.drop').forEach(c => c !== chip && c.classList.remove('drop'));
  chip?.classList.add('drop');
}
addEventListener('pointermove', e => {
  if (!drag) return;
  if (!drag.ghost) {
    if (Math.hypot(e.clientX - drag.x, e.clientY - drag.y) < 6) return;
    drag.ghost = document.createElement('div');
    drag.ghost.className = 'drag-ghost';
    drag.ghost.innerHTML = drag.a.icon ? `<img src="${drag.a.icon}" alt="">` : '<span class="ms">draft</span>';
    document.body.append(drag.ghost);
    drag.el.classList.add('dragging');
    hideCtx();
  }
  drag.ghost.style.transform = `translate(${e.clientX - 20}px, ${e.clientY - 20}px)`;
  markDrop(chipAt(e.clientX, e.clientY));
});
addEventListener('pointerup', e => {
  if (!drag) return;
  const d = drag;
  drag = null;
  if (!d.ghost) return;
  d.ghost.remove();
  d.el.classList.remove('dragging');
  markDrop(null);
  // le clic qui suit le relâchement ne doit pas lancer l'appli
  dragJustEnded = true;
  setTimeout(() => (dragJustEnded = false), 0);
  const chip = chipAt(e.clientX, e.clientY);
  const f = chip && findFolder(chip.dataset.id);
  if (f && !f.apps.includes(d.a.id)) {
    f.apps.push(d.a.id);
    saveFolders();
    renderApps();
  }
});

// ------------------------------------- fichiers déposés depuis l'Explorateur
// rangés dans le dossier visé sous l'id « file:<chemin> »
const FILE = 'file:';
const fileCache = {}; // chemin -> { id, file, name, icon, missing }
function fileItem(id) {
  const path = id.slice(FILE.length);
  if (!fileCache[path]) {
    const base = path.split('\\').pop() || path;
    fileCache[path] = { id, file: path, name: base.replace(/\.(lnk|url|exe)$/i, ''), icon: '', added: (folders.added || {})[id] || 0 };
    invoke('file_info', { path }).then(info => {
      if (info) Object.assign(fileCache[path], info);
      else fileCache[path].missing = true;
      if (currentTab === 'apps') renderApps();
    });
  }
  return fileCache[path];
}
function folderItems(f) {
  return f.apps
    .map(id => id.startsWith(FILE) ? fileItem(id) : apps.find(a => a.id === id))
    .filter(a => a && (a.file || !isHidden(a.id)));
}
function addFiles(f, paths) {
  folders.added = folders.added || {};
  paths.forEach(p => {
    if (f.apps.includes(FILE + p)) return;
    f.apps.push(FILE + p);
    folders.added[FILE + p] = Date.now();
    if (fileCache[p]) fileCache[p].added = folders.added[FILE + p];
  });
  folders.sel = f.id;
  saveFolders();
  renderApps();
}
let fileDragOpened = false;
// fichiers venus de l'Explorateur : évènements HTML de WebView2 ; au dépôt, les
// fichiers partent vers src/dropfix.rs, qui renvoie leurs chemins (« drop-paths »)
const fileDrag = {};
// tout glisser venu de l'extérieur (la Corbeille n'apporte aucun fichier)
const isFileDrag = e => !!e.dataTransfer;
// pas de glisser HTML interne (images, liens) : seuls les dépôts venus de Windows comptent
addEventListener('dragstart', e => e.preventDefault());
const hasFiles = e => [...(e.dataTransfer?.types || [])].includes('Files');
let dragDepth = 0;
let dropAt = { x: 0, y: 0 };
const dragPos = e => ({ x: e.clientX * devicePixelRatio, y: e.clientY * devicePixelRatio });
addEventListener('dragenter', e => {
  if (!isFileDrag(e)) return;
  e.preventDefault();
  if (dragDepth++ === 0) fileDrag.enter();
});
addEventListener('dragover', e => {
  if (!isFileDrag(e)) return;
  e.preventDefault();
  // la Corbeille ne se laisse que « lier », pas copier
  const ok = e.dataTransfer.effectAllowed;
  e.dataTransfer.dropEffect = /copy|all|uninitialized/i.test(ok) ? 'copy' : /link/i.test(ok) ? 'link' : 'move';
  fileDrag.over({ payload: { position: dragPos(e) } });
});
addEventListener('dragleave', e => {
  if (!isFileDrag(e)) return;
  if (--dragDepth <= 0) { dragDepth = 0; fileDrag.leave(); }
});
addEventListener('drop', e => {
  if (!isFileDrag(e)) return;
  e.preventDefault();
  dragDepth = 0;
  dropAt = dragPos(e);
  const files = e.dataTransfer.files;
  if (!hasFiles(e) || !files.length) return dropSpecial(e);
  if (window.chrome?.webview?.postMessageWithAdditionalObjects) {
    chrome.webview.postMessageWithAdditionalObjects('ilot-drop', files);
  } else fileDrag.drop({ payload: { paths: [], position: dropAt } });
});
listen('drop-paths', ({ payload }) => fileDrag.drop({ payload: { paths: payload, position: dropAt } }));
// Corbeille, Ce PC... : Windows ne donne pas de chemin, on propose l'emplacement
const SPECIAL = [
  ['shell:RecycleBinFolder', 'delete', 'Corbeille'], ['shell:MyComputerFolder', 'computer', 'Ce PC'],
  ['shell:Downloads', 'download', 'Téléchargements'], ['shell:ControlPanelFolder', 'tune', 'Panneau de configuration'],
  ['shell:NetworkPlacesFolder', 'lan', 'Réseau'],
];
function dropSpecial(e) {
  island.classList.remove('filedrag');
  markDrop(null);
  fileDragOpened = false;
  const text = e.dataTransfer.getData('text/plain');
  if (text) { showOsd('block', null, 'Dépose un fichier ou un raccourci'); return; }
  const p = { clientX: e.clientX, clientY: e.clientY };
  const chip = chipAt(p.clientX, p.clientY);
  const target = (chip && findFolder(chip.dataset.id)) || launcherFolder();
  showCtx(p, box => {
    ctxTitle(box, 'Ajouter un emplacement');
    SPECIAL.forEach(([path, icon, name]) => ctxItem(box, icon, name, () => { hideCtx(); addFiles(target, [path]); }));
  });
}
fileDrag.enter = (() => {
  // déposer sur l'îlot l'ouvre sur les applis
  // (sauf onglet Soundboard ouvert : on y dépose des sons)
  if (state === 'open' && (currentTab === 'sounds' || !$('.share-pop').hidden)) { island.classList.add('filedrag'); return; }
  if (state !== 'open' || currentTab !== 'apps') { fileDragOpened = true; pinned = true; open('apps'); }
  island.classList.add('filedrag');
});
const dropPoint = pos => ({ clientX: pos.x / devicePixelRatio, clientY: pos.y / devicePixelRatio });
fileDrag.over = (({ payload }) => {
  const p = dropPoint(payload.position);
  markDrop(chipAt(p.clientX, p.clientY));
});
fileDrag.leave = (() => {
  island.classList.remove('filedrag');
  markDrop(null);
  if (fileDragOpened) { fileDragOpened = false; close(); }
});
fileDrag.drop = (({ payload }) => {
  island.classList.remove('filedrag');
  markDrop(null);
  fileDragOpened = false;
  const paths = payload.paths || [];
  // menu Démarrer, barre des tâches : ce ne sont pas des fichiers
  if (!paths.length) { showOsd('block', null, 'Dépose un fichier ou un raccourci'); return; }
  if (!$('.share-pop').hidden) return openShare(paths);
  if (currentTab === 'sounds') return sbImportPaths(paths);
  const p = dropPoint(payload.position);
  const chip = chipAt(p.clientX, p.clientY);
  // lâché sur un dossier : rangé directement
  const target = chip && findFolder(chip.dataset.id);
  if (target) return addFiles(target, paths);
  // ailleurs : actions sur le fichier (conversion, zip, Discord) ou dossier où le ranger
  const what = paths.length > 1 ? `${paths.length} éléments` : paths[0].split('\\').pop();
  showCtx(p, box => {
    ctxTitle(box, what);
    fileActions(box, paths, p);
    box.insertAdjacentHTML('beforeend', '<hr class="ctx-sep">');
    ctxTitle(box, 'Ranger dans…');
    ctxItem(box, 'stadia_controller', 'Launcher de jeux', () => { hideCtx(); addFiles(launcherFolder(), paths); });
    folders.list.forEach(f => ctxItem(box, folderIcon(f.name), f.name, () => { hideCtx(); addFiles(f, paths); }));
    ctxItem(box, 'create_new_folder', 'Nouveau dossier…', () => askName(p, 'Nouveau dossier', '', name => addFiles(newFolder(name), paths)));
  });
});

// --- actions sur les fichiers déposés (src/files.rs) : le résultat est créé à
// côté du fichier d'origine, puis proposé (afficher, ouvrir, copier)
const IMG_RE = /\.(png|jpe?g|webp|bmp|gif)$/i;
const baseName = f => f.split('\\').pop();
function fileActions(box, paths, p) {
  const run = async (label, job) => {
    showCtx(p, b => ctxTitle(b, 'En cours…'));
    try { doneCtx(p, label, await job()); } catch (e) { doneCtx(p, 'Échec : ' + e, []); }
  };
  const imgs = paths.filter(f => IMG_RE.test(f));
  if (imgs.length) {
    const toPng = imgs.every(f => /\.jpe?g$/i.test(f));
    ctxItem(box, 'image', toPng ? 'Convertir en PNG' : 'Convertir en JPG', () =>
      run('Converti', () => Promise.all(imgs.map(f => invoke('img_convert', { path: f, to: toPng ? 'png' : 'jpg' })))));
    ctxItem(box, 'photo_size_select_large', 'Réduire la taille (1920 px)', () =>
      run('Réduit', () => Promise.all(imgs.map(f => invoke('img_shrink', { path: f })))));
  }
  ctxItem(box, 'folder_zip', 'Compresser (.zip)', () => run('Compressé', async () => [await invoke('zip_files', { paths })]));
  ctxItem(box, 'send', 'Envoyer sur Discord', () => sendToDiscord(paths, p));
  ctxItem(box, 'phonelink', 'Envoyer sur le téléphone (QR)', () => { hideCtx(); openShare(paths); });
}

// ================================================ partage avec le téléphone
// src/share.rs : petit serveur web local, adresse avec jeton dans un QR code
const shareSent = new Set();
const shareRecv = [];
async function openShare(paths = []) {
  const pop = $('.share-pop');
  pop.hidden = false;
  pinned = true;
  $('.share-err').textContent = '';
  try {
    const r = await invoke('share_start', { paths });
    $('.share-qr').innerHTML = r.qr;
    const url = $('.share-url');
    url.textContent = r.url;
    url.title = 'Clic pour copier le lien';
    url.onclick = () => navigator.clipboard?.writeText(r.url);
    shareFiles = r.files;
    renderShare();
  } catch (e) {
    $('.share-qr').innerHTML = '';
    $('.share-err').textContent = String(e);
  }
}
let shareFiles = [];
function renderShare() {
  const box = $('.share-files');
  box.innerHTML = shareFiles.length ? '' : '<div class="sp-hint">Aucun : le téléphone peut seulement envoyer.</div>';
  shareFiles.forEach(n => {
    const d = document.createElement('div');
    d.innerHTML = '<span class="ms">description</span><span></span>' + (shareSent.has(n) ? '<small>✓ récupéré</small>' : '');
    d.querySelector('span:not(.ms)').textContent = n;
    box.append(d);
  });
  const rb = $('.share-recv');
  rb.innerHTML = shareRecv.length ? '' : '<div class="sp-hint">Rien pour l’instant.</div>';
  shareRecv.forEach(f => {
    const b = document.createElement('button');
    b.title = 'Afficher dans l’Explorateur';
    b.innerHTML = '<span class="ms">download_done</span><span></span>';
    b.querySelector('span:not(.ms)').textContent = f.name;
    b.addEventListener('click', () => invoke('file_reveal', { path: f.path }));
    rb.append(b);
  });
}
listen('share', ({ payload: e }) => {
  if (e.kind === 'sent') shareSent.add(e.name);
  else {
    shareRecv.unshift(e);
    pushNotif({ app: 'Téléphone', sym: 'phonelink', title: `Reçu : ${e.name}`, body: 'Rangé dans Téléchargements',
      action: 'Afficher', cmd: ['file_reveal', { path: e.path }], ms: 8000 });
  }
  renderShare();
});
$('[data-tool="share"]').addEventListener('click', () => openShare());
$('#share-close').addEventListener('click', () => { $('.share-pop').hidden = true; });
$('#share-stop').addEventListener('click', () => {
  invoke('share_stop');
  shareFiles = []; shareSent.clear();
  $('.share-pop').hidden = true;
});
// Discord n'a pas d'API d'envoi : le fichier est copié (comme dans l'Explorateur)
// puis Discord est mis au premier plan, il reste à coller (Ctrl+V)
async function sendToDiscord(paths, p) {
  const ok = await invoke('files_copy', { paths });
  if (ok) invoke('open_url', { url: 'discord://-/channels/@me' });
  showCtx(p, box => {
    ctxTitle(box, ok ? 'Copié ! Dans Discord : Ctrl+V' : 'Copie impossible (presse-papiers occupé)');
    if (ok) ctxItem(box, 'check', 'OK', hideCtx);
  });
}
function doneCtx(p, label, outs) {
  outs = (outs || []).filter(Boolean);
  showCtx(p, box => {
    ctxTitle(box, outs.length ? `${label} : ${outs.length > 1 ? outs.length + ' fichiers' : baseName(outs[0])}` : label);
    if (!outs.length) return ctxItem(box, 'close', 'Fermer', hideCtx);
    ctxItem(box, 'folder_open', 'Afficher dans l’Explorateur', () => { hideCtx(); invoke('file_reveal', { path: outs[0] }); });
    if (outs.length === 1) ctxItem(box, 'open_in_new', 'Ouvrir', () => { hideCtx(); invoke('file_open', { path: outs[0] }); });
    ctxItem(box, 'send', 'Envoyer sur Discord', () => sendToDiscord(outs, p));
  });
}

// ------------------------------------------- applis masquées de l'îlot
const isHidden = id => (folders.hidden || []).includes(id);
function removeEverywhere(id) {
  folders.list.forEach(f => (f.apps = f.apps.filter(x => x !== id)));
  folders.games = (folders.games || []).filter(x => x !== id);
}

// ---------------------------------------------------- tri : nom ou date d'ajout
// date d'ajout : installation de l'appli (côté Rust) ou dépôt du fichier dans l'îlot
const SORTS = {
  name: ['sort_by_alpha', 'Nom', 'Nom (A → Z)'],
  'name-desc': ['sort_by_alpha', 'Nom ↓', 'Nom (Z → A)'],
  recent: ['schedule', 'Récentes', 'Ajout le plus récent'],
  old: ['history', 'Anciennes', 'Ajout le plus ancien'],
};
const fmtAdded = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
function sortItems(list) {
  const late = a => a.added || Number.MAX_SAFE_INTEGER; // dates inconnues à la fin
  const byName = (x, y) => x.name.localeCompare(y.name, 'fr');
  const by = {
    name: byName,
    'name-desc': (x, y) => byName(y, x),
    recent: (x, y) => (y.added || 0) - (x.added || 0) || byName(x, y),
    old: (x, y) => late(x) - late(y) || byName(x, y),
  }[folders.sort] || byName;
  return [...list].sort(by);
}
function renderSortBtn() {
  const [icon, short] = SORTS[folders.sort] || SORTS.name;
  $('.sort-btn .ms').textContent = icon;
  $('.sort-lbl').textContent = short;
}
$('.sort-btn').addEventListener('click', e => {
  e.preventDefault();
  showCtx(e, box => {
    ctxTitle(box, 'Trier par');
    Object.entries(SORTS).forEach(([k, [icon, , label]]) => {
      const b = ctxItem(box, (folders.sort || 'name') === k ? 'check' : icon, label, () => {
        folders.sort = k;
        saveFolders();
        hideCtx();
        renderSortBtn();
        renderApps();
      });
      if ((folders.sort || 'name') === k) b.classList.add('on');
    });
  });
});

// ------------------------------------------------------- launcher de jeux
// jeux Steam / Epic / Ubisoft / GOG détectés côté Rust (src/games.rs)
function renderGames(grid, q) {
  if (!appView.length) {
    grid.innerHTML = q ? '<div class="empty">Aucun jeu</div>'
      : '<div class="empty">Aucun jeu trouvé (Steam, Epic Games, Ubisoft Connect, GOG).</div>';
    return;
  }
  grid.innerHTML = '';
  appView.forEach((g, i) => {
    const el = document.createElement('button');
    el.className = 'game' + (q && i === appSel ? ' sel' : '') + (g.cover ? '' : ' nocover');
    el.dataset.id = g.id;
    el.title = g.name + (g.added ? `\nInstallé le ${fmtAdded.format(g.added)}` : '');
    el.innerHTML = g.cover ? `<img class="cov" src="${g.cover}" alt="" loading="lazy">`
      : g.icon ? `<img class="ico" src="${g.icon}" alt="">` : `<div class="ph">${g.name[0] || '?'}</div>`;
    const cap = document.createElement('span');
    cap.className = 'cap';
    const b = document.createElement('b');
    b.textContent = g.name;
    cap.append(b);
    cap.insertAdjacentHTML('beforeend', `<i>${SOURCE[g.source] || ''}</i>`);
    el.append(cap);
    el.addEventListener('click', () => launch(g));
    el.addEventListener('contextmenu', e => { e.preventDefault(); gameMenu(g, e); });
    grid.append(el);
  });
  updateGameDownloads();
}
function gameMenu(g, e) {
  showCtx(e, box => {
    ctxTitle(box, g.name);
    ctxItem(box, 'play_arrow', 'Lancer', () => { hideCtx(); launch(g); });
    const extra = !g.source; // ajouté à la main (fichier déposé ou appli)
    ctxItem(box, 'folder_open', 'Ouvrir le dossier du jeu', () => openFolder(() =>
      g.file ? invoke('folder_open', { path: g.file.replace(/\\[^\\]*$/, '') })
        : extra ? invoke('app_folder', { id: g.id, name: g.name })
          : invoke('game_folder', { id: g.id })));
    box.insertAdjacentHTML('beforeend', '<hr class="ctx-sep">');
    // jeu détecté : masqué (réaffichable) ; ajout manuel : retiré du Launcher
    ctxItem(box, 'delete', 'Supprimer de l’îlot', ev => {
      const b = ev.currentTarget;
      if (!b.classList.contains('armed')) { b.classList.add('armed'); b.lastChild.textContent = 'Confirmer'; return; }
      if (extra) folders.games = (folders.games || []).filter(x => x !== g.id);
      else folders.hiddenGames = [...(folders.hiddenGames || []), g.id];
      saveFolders();
      hideCtx();
      renderApps();
    }, 'danger');
  });
}
// clic droit sur « Launcher » : réafficher les jeux supprimés
function hiddenGamesMenu(e) {
  showCtx(e, box => {
    const list = (folders.hiddenGames || []).map(id => games.find(g => g.id === id)).filter(Boolean);
    ctxTitle(box, list.length ? 'Jeux supprimés de l’îlot' : 'Aucun jeu supprimé');
    list.forEach(g => ctxItem(box, 'visibility', g.name, () => {
      folders.hiddenGames = folders.hiddenGames.filter(x => x !== g.id);
      saveFolders();
      hideCtx();
      renderApps();
    }));
    if (list.length > 1) {
      ctxItem(box, 'select_all', 'Tout réafficher', () => {
        folders.hiddenGames = [];
        saveFolders();
        hideCtx();
        renderApps();
      });
    }
  });
}
// ouvre l'Explorateur puis replie l'îlot ; sinon le signale dans le menu
async function openFolder(call) {
  const ok = await call();
  if (ok) { hideCtx(); setState('collapsed'); return; }
  showCtx(lastCtxEvent, box => ctxTitle(box, 'Dossier introuvable'));
  setTimeout(hideCtx, 1500);
}
listen('games', ({ payload }) => { games = payload; if (currentTab === 'apps' && folders.sel === GAMES) renderApps(); });
invoke('games_get').then(l => { if (l.length) games = l; });

// ---------------------------------------------------------- dossiers d'apps
// enregistrés dans %LOCALAPPDATA%\Ilot\folders.json : { list: [{ id, name, apps: [id…] }], sel }
let folders = { list: [], sel: '' };
const FOLDER_ICONS = [
  [/jeu|game|gaming/, 'sports_esports'], [/cours|ecole|etude|school|fac|lycee/, 'school'],
  [/travail|boulot|work|bureau/, 'work'], [/musique|music|audio/, 'music_note'],
  [/video|film|stream/, 'movie'], [/dev|code|prog/, 'code'], [/photo|image|design|dessin/, 'palette'],
  [/internet|web|navigat/, 'language'], [/social|discu|chat|message/, 'forum'],
  [/outil|util|tool|systeme/, 'build'], [/app/, 'apps'],
];
const folderIcon = name => (FOLDER_ICONS.find(([re]) => re.test(norm(name))) || [, 'folder'])[1];
// premier lancement : quelques dossiers, et les jeux reconnus rangés d'office
const GAME_HINTS = /steam|epic games|roblox|minecraft|riot client|valorant|league of legends|battle\.net|ubisoft|ea app|gog galaxy|fortnite|rockstar|xbox|playnite|heroic|curseforge|lunar client|genshin|hoyoplay/;

function saveFolders() { invoke('store_set', { key: 'folders', value: folders }); }

function renderFolders() {
  const bar = $('.folder-bar');
  bar.innerHTML = '';
  const chip = (id, icon, name, count) => {
    const b = document.createElement('button');
    b.className = 'fchip' + (folders.sel === id ? ' on' : '');
    b.dataset.id = id;
    b.innerHTML = `<span class="ms">${icon}</span>`;
    const n = document.createElement('span');
    n.textContent = name;
    b.append(n);
    if (count != null) b.insertAdjacentHTML('beforeend', `<i>${count}</i>`);
    b.addEventListener('click', () => { folders.sel = id; saveFolders(); renderApps(); });
    bar.append(b);
    return b;
  };
  chip('', 'grid_view', 'Toutes').addEventListener('contextmenu', e => { e.preventDefault(); hiddenMenu(e); });
  const gc = chip(GAMES, 'stadia_controller', 'Launcher', launcherItems().length || null);
  gc.classList.add('games-chip');
  gc.addEventListener('contextmenu', e => { e.preventDefault(); hiddenGamesMenu(e); });
  folders.list.forEach(f => {
    const n = f.apps.filter(id => id.startsWith(FILE) || (apps.some(a => a.id === id) && !isHidden(id))).length;
    const b = chip(f.id, folderIcon(f.name), f.name, n);
    b.addEventListener('contextmenu', e => { e.preventDefault(); folderMenu(f, e); });
  });
  const add = document.createElement('button');
  add.className = 'fchip add';
  add.title = 'Nouveau dossier';
  add.innerHTML = '<span class="ms">create_new_folder</span>';
  add.addEventListener('click', e => askName(e, 'Nouveau dossier', '', name => {
    const f = newFolder(name);
    folders.sel = f.id;
    saveFolders();
    renderApps();
  }));
  bar.append(add);
}

function newFolder(name) {
  const f = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6), name, apps: [] };
  folders.list.push(f);
  return f;
}

// --- menu contextuel (clic droit)
const ctx = $('.ctx');
let lastCtxEvent = null;
function showCtx(e, build) {
  lastCtxEvent = e;
  ctx.innerHTML = '';
  build(ctx);
  ctx.hidden = false;
  const page = $('#pages').getBoundingClientRect();
  const r = ctx.getBoundingClientRect();
  ctx.style.left = Math.min(e.clientX - page.left, page.width - r.width - 4) + 'px';
  ctx.style.top = Math.min(e.clientY - page.top, page.height - r.height - 4) + 'px';
}
function hideCtx() { ctx.hidden = true; }
function ctxItem(box, icon, label, fn, cls = '') {
  const b = document.createElement('button');
  b.className = 'ctx-item ' + cls;
  b.innerHTML = `<span class="ms">${icon}</span>`;
  const t = document.createElement('span');
  t.textContent = label;
  b.append(t);
  b.addEventListener('click', ev => { ev.stopPropagation(); fn(ev); });
  box.append(b);
  return b;
}
function ctxTitle(box, text) {
  const t = document.createElement('div');
  t.className = 'ctx-title';
  t.textContent = text;
  box.append(t);
}
// petite saisie de nom dans le menu (pas de prompt() dans la webview)
function ctxInput(box, value, done) {
  const inp = document.createElement('input');
  inp.className = 'ctx-input';
  inp.value = value;
  inp.placeholder = 'Nom du dossier';
  inp.spellcheck = false;
  inp.addEventListener('keydown', ev => {
    ev.stopPropagation();
    if (ev.key === 'Enter' && inp.value.trim()) { done(inp.value.trim()); hideCtx(); }
    if (ev.key === 'Escape') hideCtx();
  });
  box.append(inp);
  setTimeout(() => { inp.focus(); inp.select(); }, 0);
}
function askName(e, title, value, done) {
  showCtx(e, box => { ctxTitle(box, title); ctxInput(box, value, done); });
}

function appMenu(a, e) {
  showCtx(e, box => {
    ctxTitle(box, a.name);
    ctxItem(box, 'folder_open', 'Ouvrir l’emplacement du fichier', () => openFolder(() =>
      a.file ? invoke('folder_open', { path: a.file.replace(/\\[^\\]*$/, '') }) : invoke('app_folder', { id: a.id, name: a.name })));
    const cur = folders.list.find(f => f.id === folders.sel);
    if (cur && cur.apps.includes(a.id)) {
      ctxItem(box, 'remove_circle_outline', `Retirer de « ${cur.name} »`, () => {
        cur.apps = cur.apps.filter(x => x !== a.id);
        saveFolders();
        hideCtx();
        renderApps();
      });
    }
    // fichier déposé : on l'enlève de tous les dossiers ; appli : on la masque
    ctxItem(box, a.file ? 'delete' : 'visibility_off', a.file ? 'Supprimer de l’îlot' : 'Masquer de l’îlot', ev => {
      const b = ev.currentTarget;
      if (!b.classList.contains('armed')) { b.classList.add('armed'); b.lastChild.textContent = 'Confirmer'; return; }
      removeEverywhere(a.id);
      if (!a.file) folders.hidden = [...(folders.hidden || []), a.id];
      saveFolders();
      hideCtx();
      renderApps();
    }, 'danger');
    box.insertAdjacentHTML('beforeend', '<hr class="ctx-sep">');
    [launcherFolder(), ...folders.list].forEach(f => {
      const inside = f.apps.includes(a.id);
      ctxItem(box, inside ? 'check_box' : 'check_box_outline_blank', f.name, () => {
        if (inside) f.apps = f.apps.filter(x => x !== a.id); else f.apps.push(a.id);
        saveFolders();
        hideCtx();
        renderApps();
      });
    });
    ctxItem(box, 'create_new_folder', 'Nouveau dossier…', () => askName(e, 'Nouveau dossier pour ' + a.name, '', name => {
      newFolder(name).apps.push(a.id);
      saveFolders();
      renderApps();
    }));
  });
}

// clic droit sur « Toutes » : réafficher les applis masquées
function hiddenMenu(e) {
  showCtx(e, box => {
    const list = (folders.hidden || []).map(id => apps.find(a => a.id === id)).filter(Boolean);
    ctxTitle(box, list.length ? 'Applis masquées' : 'Aucune appli masquée');
    list.forEach(a => ctxItem(box, 'visibility', a.name, () => {
      folders.hidden = folders.hidden.filter(x => x !== a.id);
      saveFolders();
      hideCtx();
      renderApps();
    }));
    if (list.length > 1) {
      ctxItem(box, 'select_all', 'Tout réafficher', () => {
        folders.hidden = [];
        saveFolders();
        hideCtx();
        renderApps();
      });
    }
  });
}

function folderMenu(f, e) {
  showCtx(e, box => {
    ctxTitle(box, f.name);
    // dossier réel associé (ex. Documents\Cours) pour y accéder vite
    ctxItem(box, 'folder_open', 'Ouvrir l’emplacement du fichier', async () => {
      if (!f.path) {
        hideCtx();
        const p = await invoke('pick_folder', { title: `Emplacement du dossier « ${f.name} »` });
        if (!p) return;
        f.path = p;
        saveFolders();
      }
      openFolder(() => invoke('folder_open', { path: f.path }));
    });
    if (f.path) {
      ctxItem(box, 'drive_file_move', 'Changer l’emplacement…', async () => {
        hideCtx();
        const p = await invoke('pick_folder', { title: `Emplacement du dossier « ${f.name} »` });
        if (p) { f.path = p; saveFolders(); }
      });
    }
    box.insertAdjacentHTML('beforeend', '<hr class="ctx-sep">');
    ctxItem(box, 'edit', 'Renommer', () => askName(e, 'Renommer', f.name, name => {
      f.name = name;
      saveFolders();
      renderApps();
    }));
    ctxItem(box, 'delete', 'Supprimer le dossier', ev => {
      // second clic pour confirmer (les applis ne sont pas supprimées)
      const b = ev.currentTarget;
      if (!b.classList.contains('armed')) { b.classList.add('armed'); b.lastChild.textContent = 'Confirmer la suppression'; return; }
      folders.list = folders.list.filter(x => x !== f);
      if (folders.sel === f.id) folders.sel = '';
      saveFolders();
      hideCtx();
      renderApps();
    }, 'danger');
  });
}
document.addEventListener('mousedown', e => { if (!ctx.hidden && !ctx.contains(e.target)) hideCtx(); });
addEventListener('keydown', e => {
  if (e.key === 'Escape' && !ctx.hidden) { hideCtx(); e.stopImmediatePropagation(); }
}, true);

invoke('store_get', { key: 'folders' }).then(saved => {
  if (saved && Array.isArray(saved.list)) {
    folders = {
      ...saved, sel: saved.sel || '', hidden: saved.hidden || [], added: saved.added || {}, sort: saved.sort || 'name',
      games: saved.games || [], hiddenGames: saved.hiddenGames || [],
    };
    renderSortBtn();
  } else {
    folders = { list: [], sel: '' };
    newFolder('Jeux');
    newFolder('Apps');
    newFolder('Cours');
    folders.seeded = false;
  }
  seedGames();
  if (currentTab === 'apps') renderApps();
});
// range les jeux reconnus dans « Jeux » au premier lancement (dès que la liste d'applis est là)
function seedGames() {
  if (folders.seeded !== false || !apps.length) return;
  const jeux = folders.list.find(f => f.name === 'Jeux');
  if (jeux) jeux.apps = apps.filter(a => GAME_HINTS.test(a.name.toLowerCase()) && !/studio|editor|server/i.test(a.name)).map(a => a.id);
  delete folders.seeded;
  saveFolders();
}
function launch(a) {
  if (a.file) invoke('file_open', { path: a.file });
  else if (a.source) invoke('game_launch', { id: a.id });
  else invoke('app_launch', { id: a.id });
  $('#q').value = '';
  setState('collapsed');
}
$('#q').addEventListener('input', () => { appSel = 0; renderApps(); });
$('#q').addEventListener('keydown', e => {
  // nombre de colonnes réel (varie avec le panneau agrandi)
  const cols = getComputedStyle($('.app-grid')).gridTemplateColumns.split(' ').length;
  const moves = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: cols, ArrowUp: -cols };
  if (e.key in moves) {
    e.preventDefault();
    appSel = Math.max(0, Math.min(appView.length - 1, appSel + moves[e.key]));
    $$('.app-grid > button').forEach((el, i) => el.classList.toggle('sel', i === appSel));
    $$('.app-grid > button')[appSel]?.scrollIntoView({ block: 'nearest' });
  } else if (e.key === 'Enter' && appView[appSel]) {
    launch(appView[appSel]);
  }
});
listen('apps', ({ payload }) => { apps = payload; seedGames(); if (currentTab === 'apps') renderApps(); });
invoke('apps_get').then(l => { if (l.length) { apps = l; seedGames(); } });

// =================================================================== mail
// comptes IMAP gérés côté Rust (src/mail.rs) ; vérification toutes les 2 min
let inbox = { accounts: [], mails: [] };
let mailAcc = ''; // filtre : '' = tous les comptes
let mailOpen = null; // message affiché dans le lecteur
let mailBusy = false;
const mailKnown = new Set(); // messages déjà vus par l'îlot (compte + uid)
const fmtHour = new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit' });
const fmtDay = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'short' });
function mailDate(ts) {
  const d = new Date(ts * 1000);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) return fmtHour.format(d);
  const y = new Date(now); y.setDate(now.getDate() - 1);
  if (d.toDateString() === y.toDateString()) return 'Hier';
  return fmtDay.format(d);
}

function mailView(v) { // 'list' | 'reader' | 'setup'
  $('.mail-main').hidden = v !== 'list';
  $('.mail-reader').hidden = v !== 'reader';
  $('.mail-setup').hidden = v !== 'setup';
  if (v === 'setup') renderAccounts();
}

function applyInbox(ib) {
  inbox = ib;
  if (mailAcc && !inbox.accounts.some(a => a.email === mailAcc)) mailAcc = '';
  const unread = inbox.accounts.reduce((n, a) => n + a.unread, 0);
  const badge = $('#tabs .badge');
  badge.hidden = !unread;
  badge.textContent = unread > 99 ? '99+' : unread;
  $('.mini-mail').hidden = !unread;
  $('.peek-mail').hidden = !unread;
  $('.peek-mail b').textContent = unread;
  // nouveaux mails depuis la dernière vérification : notification dans l'îlot
  const fresh = inbox.mails.filter(m => !m.seen && !mailKnown.has(m.account + m.uid));
  if (mailKnown.size) {
    if (fresh.length === 1) pushNotif({ app: fresh[0].account, title: fresh[0].from || fresh[0].from_addr, body: fresh[0].subject || '(sans objet)', icon: '', sym: 'mail', tab: 'mail' });
    else if (fresh.length > 1) pushNotif({ app: 'Mail', title: `${fresh.length} nouveaux mails`, body: fresh.map(m => m.from || m.from_addr).slice(0, 3).join(', '), icon: '', sym: 'mail', tab: 'mail' });
  }
  inbox.mails.forEach(m => mailKnown.add(m.account + m.uid));
  renderMail();
  if (!$('.mail-setup').hidden) renderAccounts();
}

function renderMail() {
  const seg = $('.mail-seg');
  seg.hidden = inbox.accounts.length < 2;
  seg.innerHTML = '';
  if (inbox.accounts.length > 1) {
    [{ email: '', label: 'Tous' }, ...inbox.accounts.map(a => ({ email: a.email, label: a.email.split('@')[0], unread: a.unread }))]
      .forEach(a => {
        const b = document.createElement('button');
        b.className = mailAcc === a.email ? 'on' : '';
        b.textContent = a.label;
        b.title = a.email || 'Tous les comptes';
        b.addEventListener('click', () => { mailAcc = a.email; renderMail(); });
        seg.append(b);
      });
  }
  const errs = inbox.accounts.filter(a => a.error);
  const unread = inbox.accounts.filter(a => !mailAcc || a.email === mailAcc).reduce((n, a) => n + a.unread, 0);
  $('.mail-note').textContent = errs.length
    ? `⚠ ${errs[0].email} : ${errs[0].error}`
    : inbox.accounts.length ? (unread ? `${unread} non lu${unread > 1 ? 's' : ''}` : 'Tout est lu') : '';
  $('.mail-note').classList.toggle('err', !!errs.length);

  const box = $('.mail-list');
  if (!inbox.accounts.length) {
    box.innerHTML = '<div class="empty">Aucun compte.<br><button class="text-btn primary" id="mail-first"><span class="ms">add</span>Ajouter un compte</button></div>';
    $('#mail-first').addEventListener('click', () => mailView('setup'));
    return;
  }
  const list = inbox.mails.filter(m => !mailAcc || m.account === mailAcc);
  if (!list.length) {
    box.innerHTML = `<div class="empty">${mailBusy ? 'Chargement…' : 'Boîte de réception vide'}</div>`;
    return;
  }
  box.innerHTML = '';
  const multi = inbox.accounts.length > 1 && !mailAcc;
  list.forEach(m => {
    const el = document.createElement('button');
    el.className = 'mail-item' + (m.seen ? '' : ' unread');
    el.innerHTML = '<i class="dot"></i><div class="mi-text"><div class="mi-top"><b></b><time></time></div><div class="mi-sub"></div></div>';
    el.querySelector('b').textContent = m.from || m.from_addr || '(inconnu)';
    el.querySelector('time').textContent = mailDate(m.date);
    el.querySelector('.mi-sub').textContent = m.subject || '(sans objet)';
    el.title = (multi ? m.account + '\n' : '') + m.from_addr;
    if (multi) el.querySelector('.mi-top').insertAdjacentHTML('beforeend', `<span class="mi-acc">${m.account.split('@')[0].replace(/[<>&"]/g, '')}</span>`);
    el.addEventListener('click', () => readMail(m));
    box.append(el);
  });
}

async function refreshMail() {
  if (mailBusy) return;
  mailBusy = true;
  $('#mail-refresh').classList.add('busy');
  try { applyInbox(await invoke('mail_refresh')); } finally {
    mailBusy = false;
    $('#mail-refresh').classList.remove('busy');
  }
}

// le message est affiché dans une iframe sans scripts ; les liens partent dans le navigateur
function mailDoc(body) {
  const esc = s => s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
  const content = body.html || `<pre>${esc(body.text || '(message vide)')}</pre>`;
  return `<!doctype html><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data: cid:; style-src 'unsafe-inline' https:; font-src https: data:">
<style>html{background:#fff;color:#1d1b20;font:14px/1.45 'Segoe UI',sans-serif}body{margin:16px;word-wrap:break-word}
pre{white-space:pre-wrap;font:inherit}img{max-width:100%;height:auto}a{color:#6750a4}</style>${content}`;
}
async function readMail(m) {
  mailOpen = m;
  mailView('reader');
  $('.mr-subject').textContent = m.subject || '(sans objet)';
  $('.mr-from').textContent = `${m.from}${m.from !== m.from_addr ? ' <' + m.from_addr + '>' : ''} · ${new Date(m.date * 1000).toLocaleString('fr-FR')}`;
  $('#mr-web').hidden = !m.link;
  const frame = $('.mr-body');
  frame.srcdoc = mailDoc({ text: 'Chargement…' });
  try {
    const body = await invoke('mail_read', { account: m.account, uid: m.uid });
    if (mailOpen !== m) return;
    frame.srcdoc = mailDoc(body);
  } catch (e) {
    if (mailOpen === m) frame.srcdoc = mailDoc({ text: 'Impossible de charger le message : ' + e });
  }
}
$('.mr-body').addEventListener('load', () => {
  const doc = $('.mr-body').contentDocument;
  if (!doc) return;
  doc.addEventListener('click', e => {
    const a = e.target.closest('a[href]');
    if (!a) return;
    e.preventDefault();
    if (/^https?:/i.test(a.href)) invoke('open_url', { url: a.href });
  });
});
$('#mr-back').addEventListener('click', () => { mailOpen = null; mailView('list'); });
$('#mr-web').addEventListener('click', () => { if (mailOpen?.link) { invoke('open_url', { url: mailOpen.link }); setState('collapsed'); } });
$('#mail-refresh').addEventListener('click', refreshMail);
$('#mail-accounts').addEventListener('click', () => mailView('setup'));
$('#ms-back').addEventListener('click', () => mailView('list'));

function renderAccounts() {
  const box = $('.acc-list');
  box.innerHTML = inbox.accounts.length ? '' : '<div class="acc-none">Aucun compte pour l\'instant.</div>';
  inbox.accounts.forEach(a => {
    const el = document.createElement('div');
    el.className = 'acc';
    el.innerHTML = '<span class="ms">account_circle</span><div><b></b><small></small></div><button class="icon-btn small" title="Retirer ce compte"><span class="ms">delete</span></button>';
    el.querySelector('b').textContent = a.email;
    el.querySelector('small').textContent = a.error ? '⚠ ' + a.error : `${a.host} · ${a.unread} non lu${a.unread > 1 ? 's' : ''}`;
    el.querySelector('small').classList.toggle('err', !!a.error);
    const del = el.querySelector('button');
    del.addEventListener('click', async () => {
      if (!del.classList.contains('armed')) { del.classList.add('armed'); del.title = 'Cliquer encore pour retirer'; setTimeout(() => del.classList.remove('armed'), 3000); return; }
      applyInbox(await invoke('mail_remove', { email: a.email }));
    });
    box.append(el);
  });
}
$('.acc-form').addEventListener('submit', async e => {
  e.preventDefault();
  const f = e.currentTarget;
  const btn = f.querySelector('button[type=submit]');
  const err = $('.acc-err');
  err.textContent = 'Connexion…';
  err.classList.remove('err');
  btn.disabled = true;
  try {
    applyInbox(await invoke('mail_add', { email: f.email.value, pass: f.pass.value, host: f.host.value || null }));
    f.reset();
    err.textContent = '';
    mailView('list');
  } catch (ex) {
    err.textContent = String(ex);
    err.classList.add('err');
  } finally {
    btn.disabled = false;
  }
});
$$('.acc-form input').forEach(i => i.addEventListener('focus', () => { pinned = true; }));
$$('[data-url]').forEach(a => a.addEventListener('click', e => { e.preventDefault(); invoke('open_url', { url: a.dataset.url }); }));
listen('mail', ({ payload }) => applyInbox(payload));
invoke('mail_get').then(applyInbox);

// ============================================ média : volume de l'appli
// volume de la session audio Windows de l'appli qui joue (Spotify, Chrome…)
const mpVol = $('#mp-vol');
let mpApp = '';
function showAppVolume(v) {
  $('.mp-vol').hidden = !v;
  if (!v) return;
  const n = Math.round(v.level * 100);
  mpVol.value = n;
  mpVol.style.setProperty('--p', (v.muted ? 0 : n) + '%');
  $('.mp-vol-val').textContent = v.muted ? '–' : n;
  $('#mp-mute .ms').textContent = v.muted || !n ? 'volume_off' : n < 50 ? 'volume_down' : 'volume_up';
  mpVol.dataset.muted = v.muted;
}
function refreshAppVolume() {
  mpApp = hasMedia ? media.app : '';
  if (!mpApp) return showAppVolume(null);
  invoke('app_volume_get', { app: mpApp }).then(showAppVolume);
}
mpVol.addEventListener('input', () => {
  showAppVolume({ level: mpVol.value / 100, muted: false });
  invoke('app_volume_set', { app: mpApp, level: mpVol.value / 100, muted: false });
});
mpVol.addEventListener('wheel', e => {
  e.stopPropagation();
  const v = Math.max(0, Math.min(100, Number(mpVol.value) - Math.sign(e.deltaY) * 5));
  showAppVolume({ level: v / 100, muted: false });
  invoke('app_volume_set', { app: mpApp, level: v / 100, muted: false });
}, { passive: true });
$('#mp-mute').addEventListener('click', () => {
  const muted = mpVol.dataset.muted !== 'true';
  showAppVolume({ level: mpVol.value / 100, muted });
  invoke('app_volume_set', { app: mpApp, muted });
});
listen('media', ({ payload }) => { if (currentTab === 'media' && payload.app !== mpApp) refreshAppVolume(); });

// --- panneaux latéraux (playlists, apparence)
function togglePanel(id) {
  const p = $(id);
  const show = p.hidden;
  $$('.side-panel').forEach(x => (x.hidden = true));
  p.hidden = !show;
}
$$('.side-panel [data-close]').forEach(b => b.addEventListener('click', () => (b.closest('.side-panel').hidden = true)));
$('#mp-lists').addEventListener('click', () => togglePanel('#pl-panel'));
// paroles affichées en bas de l'onglet Média (choix mémorisé dans ce navigateur)
let lyShown = true;
try { lyShown = localStorage.getItem('lyrics') !== 'off'; } catch {}
function showLyrics(on) {
  lyShown = on;
  try { localStorage.setItem('lyrics', on ? 'on' : 'off'); } catch {}
  $('[data-page="media"]').classList.toggle('ly-on', on);
  $('#mp-lyrics').classList.toggle('on', on);
  if (on) { ly.key = ''; loadLyrics(); }
}
$('#mp-lyrics').addEventListener('click', () => showLyrics(!lyShown));

// ================================================ paroles synchronisées
// src/lyrics.rs (lrclib.net) ; la ligne en cours suit la position du lecteur
let ly = { key: '', lines: [], plain: '', state: '' };
let lyOn = -1;
const lyKey = () => `${media.artist}|${media.title}`;
function parseLrc(t) {
  const out = [];
  t.split(/\r?\n/).forEach(row => {
    const tags = [...row.matchAll(/\[(\d+):(\d+(?:[.:]\d+)?)\]/g)];
    if (!tags.length) return;
    const text = row.replace(/\[[^\]]*\]/g, '').trim();
    tags.forEach(m => out.push({ t: +m[1] * 60 + parseFloat(m[2].replace(':', '.')), text }));
  });
  return out.sort((a, b) => a.t - b.t);
}
async function loadLyrics() {
  if (!media.has || !media.title) { ly = { key: lyKey(), lines: [], plain: '', state: 'none' }; return renderLyrics(); }
  const key = lyKey();
  if (ly.key === key && ly.state !== 'error') return;
  ly = { key, lines: [], plain: '', state: 'loading' };
  renderLyrics();
  try {
    const r = await invoke('lyrics_get', { artist: media.artist || '', title: media.title, album: media.album || '', duration: media.duration || 0 });
    if (ly.key !== key) return; // morceau changé entre-temps
    ly.lines = r.synced ? parseLrc(r.synced) : [];
    ly.plain = r.plain;
    ly.state = r.instrumental ? 'instr' : ly.lines.length ? 'synced' : r.plain ? 'plain' : 'none';
  } catch (e) {
    if (ly.key !== key) return;
    // serveurs de paroles surchargés : nouvel essai tout seul dans 30 s
    ly.state = 'error';
    ly.err = 'Serveurs de paroles occupés, nouvel essai dans 30 s…';
    setTimeout(() => { if (ly.key === key && ly.state === 'error') loadLyrics(); }, 30000);
  }
  renderLyrics();
}
function renderLyrics() {
  const box = $('.ly-lines');
  lyOn = -1;
  box.classList.toggle('plain', ly.state !== 'synced');
  const msg = { loading: 'Recherche des paroles…', none: 'Pas de paroles trouvées pour ce morceau.', instr: '♪ Morceau instrumental', error: ly.err || 'Erreur' }[ly.state];
  if (msg) { box.innerHTML = '<div class="sp-hint"></div>'; box.firstChild.textContent = msg; return; }
  box.innerHTML = '';
  const rows = ly.state === 'synced' ? ly.lines : ly.plain.split(/\r?\n/).map(text => ({ text }));
  rows.forEach(l => {
    const d = document.createElement('div');
    d.className = 'ly-line' + (l.text ? '' : ' gap');
    d.textContent = l.text || '♪';
    // clic sur une ligne : le lecteur y saute
    if (l.t != null) d.addEventListener('click', () => {
      invoke('media_action', { action: 'seek', value: l.t });
      media.position = l.t; mediaAt = performance.now();
    });
    box.append(d);
  });
  syncLyrics();
}
function syncLyrics() {
  if (ly.state !== 'synced' || !lyShown) return;
  const p = position() + 0.25; // petite avance : la ligne s'allume avec la voix
  let i = -1;
  while (i + 1 < ly.lines.length && ly.lines[i + 1].t <= p) i++;
  if (i === lyOn) return;
  const box = $('.ly-lines');
  const rows = box.children;
  if (rows[lyOn]) rows[lyOn].classList.remove('on');
  lyOn = i;
  const el = rows[i];
  if (el) {
    el.classList.add('on');
    box.scrollTop = el.offsetTop - box.clientHeight / 2 + el.offsetHeight / 2;
  } else box.scrollTop = 0;
}
setInterval(() => {
  if (state !== 'open' || currentTab !== 'media' || !lyShown) return;
  if (lyKey() !== ly.key) loadLyrics(); else syncLyrics();
}, 200);
showLyrics(lyShown);
$('#wall-style').addEventListener('click', () => togglePanel('#st-panel'));
$$('.side-panel input').forEach(i => i.addEventListener('focus', () => { pinned = true; }));

// ================================================== playlists favorites
// %LOCALAPPDATA%\Ilot\playlists.json : [{ name, url }]
let playlists = [];
const plIcon = url => /spotify/.test(url) ? 'music_note' : /deezer/.test(url) ? 'graphic_eq' : /youtu/.test(url) ? 'smart_display' : 'queue_music';
// les liens open.spotify.com s'ouvrent directement dans l'appli Spotify
const plTarget = url => {
  const m = url.match(/open\.spotify\.com\/(?:intl-\w+\/)?(playlist|album|artist|track)\/(\w+)/);
  return m ? `spotify:${m[1]}:${m[2]}` : url;
};
function renderPlaylists() {
  const box = $('.pl-list');
  box.innerHTML = playlists.length ? '' : '<div class="sp-hint">Aucune playlist enregistrée.</div>';
  playlists.forEach((p, i) => {
    const el = document.createElement('div');
    el.className = 'pl-item';
    el.innerHTML = `<button class="pl-open"><span class="ms">${plIcon(p.url)}</span><span></span></button><button class="icon-btn small" title="Retirer"><span class="ms">close</span></button>`;
    el.querySelector('.pl-open span:last-child').textContent = p.name;
    el.querySelector('.pl-open').title = p.url;
    el.querySelector('.pl-open').addEventListener('click', () => { invoke('open_url', { url: plTarget(p.url) }); setState('collapsed'); });
    el.querySelector('.icon-btn').addEventListener('click', () => {
      playlists.splice(i, 1);
      invoke('store_set', { key: 'playlists', value: playlists });
      renderPlaylists();
    });
    box.append(el);
  });
}
$('.pl-form').addEventListener('submit', e => {
  e.preventDefault();
  const f = e.currentTarget;
  const url = f.url.value.trim();
  if (!/^(https?:\/\/|spotify:|deezer:\/\/)/.test(url)) { f.url.setCustomValidity('Lien http(s) ou spotify: attendu'); f.url.reportValidity(); return; }
  playlists.push({ name: f.name.value.trim(), url });
  invoke('store_set', { key: 'playlists', value: playlists });
  f.reset();
  renderPlaylists();
});
$('.pl-form [name=url]').addEventListener('input', e => e.target.setCustomValidity(''));
invoke('store_get', { key: 'playlists' }).then(l => { if (Array.isArray(l)) playlists = l; renderPlaylists(); });

// ============================================================ apparence
// %LOCALAPPDATA%\Ilot\theme.json ; « auto » = couleur tirée du fond d'écran
let theme = {
  color: 'auto', scheme: 'tonal', dark: true, mediaBg: 'art', islandBg: 'solid', border: 'none', shape: 'round',
  day: '07:00', night: '20:00', anim: 'normal', textSize: '100', contrast: 'normal', motion: 'system', cvd: 'off', notif: 'on', activity: 'on',
  gamemode: 'on', gamePerf: 'on', gameNotif: 'off', dcPill: 'on', matchAlert: 'on', wxfx: 'on', pet: 'blob',
  mixAuto: 'on', away: 'on', pillSize: 'm', pillPos: 'top', screen: 'main',
  petWalk: 'on', clock: 'digital', privacy: 'on',
};
// dark : true, false, 'system' (mode de Windows), 'time' (heures choisies)
// ou 'sun' (lever / coucher du soleil, donnés par la météo)
const sysDark = matchMedia('(prefers-color-scheme: dark)');
const hm = s => { const [h, m] = String(s).split(':').map(Number); return h * 60 + (m || 0); };
function isDark() {
  if (theme.dark === 'system') return sysDark.matches;
  if (theme.dark === 'time' || theme.dark === 'sun') {
    const d = new Date(), now = d.getHours() * 60 + d.getMinutes();
    const [a, b] = theme.dark === 'sun' && sunTimes ? sunTimes : [hm(theme.day), hm(theme.night)];
    return a <= b ? !(now >= a && now < b) : (now >= b && now < a);
  }
  return theme.dark;
}
let appliedDark = null; // clair / sombre réellement appliqué par themeFrom
function checkDarkSchedule() {
  if (appliedDark !== null && isDark() !== appliedDark) themeFrom(currentThumb);
}
sysDark.addEventListener('change', checkDarkSchedule);
setInterval(checkDarkSchedule, 60 * 1000);
const SCHEMES = {
  tonal: ['Doux', SchemeTonalSpot], vibrant: ['Vif', SchemeVibrant], expressive: ['Expressif', SchemeExpressive],
  fidelity: ['Fidèle', SchemeFidelity], content: ['Contenu', SchemeContent], neutral: ['Neutre', SchemeNeutral],
  mono: ['Monochrome', SchemeMonochrome], rainbow: ['Arc-en-ciel', SchemeRainbow], fruit: ['Fruité', SchemeFruitSalad],
};
const OPTS = {
  scheme: Object.entries(SCHEMES).map(([k, [l]]) => [k, l]),
  dark: [[true, 'Sombre'], [false, 'Clair'], ['system', 'Comme Windows'], ['time', 'Selon l’heure'], ['sun', 'Lever / coucher du soleil']],
  anim: [['normal', 'Normale'], ['fast', 'Rapide'], ['soft', 'Douce'], ['calm', 'Sans rebond'], ['off', 'Instantanée']],
  notif: [['on', 'Activées'], ['off', 'Désactivées']],
  activity: [['on', 'Affichées'], ['off', 'Masquées']],
  gamemode: [['on', 'Automatique'], ['off', 'Désactivé']],
  gamePerf: [['on', 'Passer en Performances'], ['off', 'Ne pas toucher']],
  gameNotif: [['off', 'Notifications coupées'], ['on', 'Notifications gardées']],
  dcPill: [['on', 'Affichés'], ['off', 'Masqués']],
  matchAlert: [['on', 'Alerte « partie trouvée »'], ['off', 'Pas d’alerte']],
  mixAuto: [['on', 'Profil de volume « Jeu »'], ['off', 'Volumes inchangés']],
  away: [['on', 'Pause musique + récap'], ['recap', 'Récap seulement'], ['off', 'Désactivé']],
  wxfx: [['on', 'Animée'], ['off', 'Désactivée']],
  pet: [['blob', 'Blob'], ['cat', 'Chat'], ['ghost', 'Fantôme'], ['off', 'Masqué']],
  mediaBg: [['art', 'Pochette floutée'], ['color', 'Couleur'], ['gradient', 'Dégradé'], ['none', 'Aucun']],
  petWalk: [['on', 'Se promène quand tu ne fais rien'], ['off', 'Reste dans la pilule']],
  clock: [['digital', 'Classique'], ['flip', 'À volets'], ['analog', 'À aiguilles'], ['neon', 'Néon'], ['pixel', 'Pixel']],
  privacy: [['on', 'Affiché'], ['off', 'Masqué']],
  textSize: [['100', 'Normale'], ['112', 'Grande'], ['125', 'Très grande']],
  contrast: [['normal', 'Normal'], ['high', 'Élevé']],
  motion: [['system', 'Comme Windows'], ['full', 'Toutes'], ['reduced', 'Réduites']],
  cvd: [['off', 'Standard'], ['rg', 'Daltonien rouge-vert'], ['by', 'Daltonien bleu-jaune']],
  pillSize: [['s', 'Petite'], ['m', 'Moyenne'], ['l', 'Grande']],
  pillPos: [['top', 'En haut'], ['bottom', 'En bas']],
  screen: [['main', 'Écran principal']],
  islandBg: [['aurora', 'Aurore boréale'], ['solid', 'Opaque'], ['black', 'Noir pur'], ['glass', 'Translucide'], ['clear', 'Très transparent'], ['wall', 'Fond d’écran flouté']],
  border: [['none', 'Aucun'], ['line', 'Liseré'], ['glow', 'Lueur'], ['rgb', 'Arc-en-ciel'], ['pulse', 'Pulsation']],
  shape: [['round', 'Arrondie'], ['pill', 'Pilule'], ['square', 'Carrée']],
};
// thèmes prêts : un clic applique couleur + style + fond + contour
const PRESETS = [
  ['Minuit', { color: '#1e88e5', scheme: 'neutral', dark: true, islandBg: 'glass', border: 'line', shape: 'round' }],
  ['Néon', { color: '#d81b60', scheme: 'vibrant', dark: true, islandBg: 'black', border: 'rgb', shape: 'pill' }],
  ['Forêt', { color: '#43a047', scheme: 'tonal', dark: true, islandBg: 'solid', border: 'none', shape: 'round' }],
  ['Coucher de soleil', { color: '#fb8c00', scheme: 'expressive', dark: true, islandBg: 'wall', border: 'glow', shape: 'round' }],
  ['Glace', { color: '#4fc3f7', scheme: 'tonal', dark: false, islandBg: 'clear', border: 'line', shape: 'pill' }],
  ['Rétro', { color: '#c0ca33', scheme: 'fruit', dark: true, islandBg: 'solid', border: 'pulse', shape: 'square' }],
  ['Monochrome', { color: '#9e9e9e', scheme: 'mono', dark: true, islandBg: 'black', border: 'none', shape: 'pill' }],
];
// fond de l'îlot : opacité de la couleur de surface (en %)
const ISLAND_ALPHA = { solid: 100, glass: 80, clear: 55, wall: 50 };
async function applyIslandBg() {
  const mode = theme.islandBg || 'solid';
  const a = ISLAND_ALPHA[mode] ?? 100;
  island.style.setProperty('--island-bg', mode === 'black' ? '#000' : a === 100 ? 'var(--surface)' : `color-mix(in srgb, var(--surface) ${a}%, transparent)`);
  island.classList.toggle('aurora-bg', mode === 'aurora');
  const wall = mode === 'wall' && currentThumb;
  island.classList.toggle('wall-bg', !!wall);
  if (!wall) return;
  // le fond d'écran, calé comme à l'écran (« remplir ») : l'îlot est centré en haut
  try {
    const img = new Image();
    img.src = currentThumb;
    await img.decode();
    const s = Math.max(screen.width / img.naturalWidth, screen.height / img.naturalHeight);
    const w = img.naturalWidth * s, h = img.naturalHeight * s;
    const el = $('.island-wall');
    el.style.backgroundImage = `url("${currentThumb}")`;
    el.style.backgroundSize = `${w}px ${h}px`;
    el.style.backgroundPosition = `center ${WALL_BLEED - (h - screen.height) / 2}px`;
  } catch {}
}
const WALL_BLEED = 30; // débord du calque flouté (évite les bords clairs du flou)
const SWATCHES = ['#6750a4', '#3f51b5', '#1e88e5', '#00bcd4', '#00897b', '#43a047', '#c0ca33', '#fbc02d', '#fb8c00', '#e53935', '#d81b60', '#8e24aa', '#795548', '#607d8b'];

function applyIslandLook() {
  ['line', 'glow', 'rgb', 'pulse'].forEach(k => island.classList.toggle('border-' + k, theme.border === k));
  ['pill', 'square'].forEach(k => island.classList.toggle('shape-' + k, theme.shape === k));
  ['fast', 'soft', 'calm', 'off'].forEach(k => document.documentElement.classList.toggle('anim-' + k, theme.anim === k));
  applyA11y();
}

// ============================== accessibilité (Apparence > Accessibilité)
const reduceMq = matchMedia('(prefers-reduced-motion: reduce)');
reduceMq.addEventListener('change', () => applyA11y());
function applyA11y() {
  const html = document.documentElement;
  html.classList.toggle('hc', theme.contrast === 'high');
  html.classList.toggle('rm', theme.motion === 'reduced' || ((theme.motion || 'system') === 'system' && reduceMq.matches));
  ['rg', 'by'].forEach(k => html.classList.toggle('cvd-' + k, theme.cvd === k));
  const k = (Number(theme.textSize) || 100) / 100;
  if (k !== textK) {
    textK = k;
    island.style.setProperty('--tz', k);
    setBig(big, false);
  }
}

function renderThemePanel() {
  const pr = $('.presets');
  pr.innerHTML = '';
  PRESETS.forEach(([label, p]) => {
    const b = document.createElement('button');
    b.className = 'fchip preset' + (Object.entries(p).every(([k, v]) => theme[k] === v) ? ' on' : '');
    b.innerHTML = `<i class="dot" style="background:${p.color}"></i>${label}`;
    b.addEventListener('click', () => setTheme(p));
    pr.append(b);
  });
  const sw = $('.swatches');
  sw.innerHTML = '';
  const auto = document.createElement('button');
  auto.className = 'sw auto' + (theme.color === 'auto' ? ' on' : '');
  auto.title = 'Automatique (fond d’écran)';
  auto.innerHTML = '<span class="ms">wallpaper</span>';
  auto.addEventListener('click', () => setTheme({ color: 'auto' }));
  sw.append(auto);
  const art = document.createElement('button');
  art.className = 'sw auto' + (theme.color === 'art' ? ' on' : '');
  art.title = 'Pochette du morceau en cours (sinon fond d’écran)';
  art.innerHTML = '<span class="ms">album</span>';
  art.addEventListener('click', () => setTheme({ color: 'art' }));
  sw.append(art);
  SWATCHES.forEach(c => {
    const b = document.createElement('button');
    b.className = 'sw' + (theme.color === c ? ' on' : '');
    b.style.background = c;
    b.addEventListener('click', () => setTheme({ color: c }));
    sw.append(b);
  });
  const custom = document.createElement('label');
  const fixed = theme.color !== 'auto' && theme.color !== 'art';
  custom.className = 'sw custom' + (fixed && !SWATCHES.includes(theme.color) ? ' on' : '');
  custom.title = 'Autre couleur';
  custom.innerHTML = `<span class="ms">colorize</span><input type="color" value="${fixed ? theme.color : '#6750a4'}">`;
  custom.querySelector('input').addEventListener('change', e => setTheme({ color: e.target.value }));
  sw.append(custom);
  $$('.chips[data-opt]').forEach(box => {
    const key = box.dataset.opt;
    box.innerHTML = '';
    OPTS[key].forEach(([v, label]) => {
      const b = document.createElement('button');
      b.className = 'fchip' + (theme[key] === v ? ' on' : '');
      b.textContent = label;
      b.addEventListener('click', () => setTheme({ [key]: v }));
      box.append(b);
    });
  });
  // heures du thème « Selon l'heure »
  const times = $('.sp-times');
  times.hidden = theme.dark !== 'time';
  times.querySelector('[name=day]').value = theme.day;
  times.querySelector('[name=night]').value = theme.night;
}
$$('.sp-times input').forEach(i => i.addEventListener('change', () => { if (i.value) setTheme({ [i.name]: i.value }); }));
function setTheme(patch) {
  theme = { ...theme, ...patch };
  invoke('store_set', { key: 'theme', value: theme });
  renderThemePanel();
  applyMediaBg();
  if ('islandBg' in patch) applyIslandBg();
  applyIslandLook();
  if ('activity' in patch) renderActivity();
  if ('dcPill' in patch) renderDcPill();
  if ('wxfx' in patch) applyWeatherFx();
  if ('pet' in patch) applyPet();
  if ('clock' in patch) tickClock();
  if ('privacy' in patch) renderPrivacy();
  if (['pillSize', 'pillPos', 'screen'].some(k => k in patch)) applyPlacement();
  if ('gamemode' in patch) gameMode(theme.gamemode === 'off' ? null : act.game);
  if (['color', 'scheme', 'dark', 'day', 'night'].some(k => k in patch)) themeFrom(currentThumb);
}
function applyMediaBg() {
  const page = $('[data-page="media"]');
  ['art', 'color', 'gradient', 'none'].forEach(k => page.classList.toggle('bg-' + k, theme.mediaBg === k));
}
invoke('store_get', { key: 'theme' }).then(t => {
  if (t && typeof t === 'object') theme = { ...theme, ...t };
  renderThemePanel();
  applyMediaBg();
  applyIslandBg();
  applyIslandLook();
  applyPlacement();
  renderActivity();
  applyWeatherFx();
  applyPet();
  if (theme.color !== 'auto' || theme.scheme !== 'tonal' || theme.dark !== true) themeFrom(currentThumb);
});

// ========================================================= notifications
// notifications Windows (src/notify.rs) et nouveaux mails : l'îlot s'agrandit
// quelques secondes ; elles passent l'une après l'autre
const NOTIF_MS = 5000;
const notifQ = [];
let notifTimer = null;
// mode absent (plus bas) : notifications gardées pour le retour
const away = { on: false, since: 0, missed: [], paused: false };
function pushNotif(n) {
  if (theme.notif === 'off' || island.classList.contains('hidden')) return;
  if (gameOn && theme.gameNotif !== 'on' && !n.force) return; // mode jeu : pas de notification (sauf bilan)
  if (away.on && !n.recap) { if (away.missed.length < 30) away.missed.push(n); return; } // gardées pour le retour
  if (notifQ.length < 5) notifQ.push(n);
  if (!notifShown) nextNotif();
}
function nextNotif() {
  clearTimeout(notifTimer);
  notifShown = notifQ.shift() || null;
  island.classList.toggle('notif', !!notifShown);
  reportHit();
  if (!notifShown) return;
  const el = $('.pill-notif');
  const img = el.querySelector('img');
  if (notifShown.icon) img.src = notifShown.icon; else img.removeAttribute('src');
  el.querySelector('.pn-sym').textContent = notifShown.sym || 'notifications';
  el.querySelector('.pn-app').textContent = notifShown.app;
  el.querySelector('.pn-title').textContent = notifShown.title;
  el.querySelector('.pn-body').textContent = notifShown.body;
  const act = el.querySelector('.pn-act');
  act.hidden = !notifShown.action;
  act.textContent = notifShown.action || '';
  // relance l'animation d'entrée
  el.classList.remove('in'); void el.offsetWidth; el.classList.add('in');
  notifTimer = setTimeout(nextNotif, notifShown.ms || NOTIF_MS);
}
listen('notif', ({ payload }) => pushNotif(payload));
// survol : la notification reste tant que la souris est dessus
listen('hover', ({ payload }) => {
  if (!notifShown) return;
  clearTimeout(notifTimer);
  if (!payload) notifTimer = setTimeout(nextNotif, 2000);
});

// ==================================================== activités en cours
// téléchargement Steam, jeu en cours (charge / température GPU) : src/activity.rs
let act = { downloads: [] };
const GAMING_LOAD = 60; // % GPU au-delà duquel on considère qu'un jeu tourne
const fmtSize = b => b >= 1024 ** 3 ? (b / 1024 ** 3).toFixed(1).replace('.', ',') + ' Go' : Math.round(b / 1024 ** 2) + ' Mo';
const fmtSpeed = b => b >= 1024 ** 2 ? (b / 1024 ** 2).toFixed(1).replace('.', ',') + ' Mo/s' : Math.round(b / 1024) + ' Ko/s';
function fmtEta(d) {
  if (!d.speed) return '';
  const s = (d.total - d.done) / d.speed;
  return s < 60 ? 'moins d’1 min' : s < 3600 ? Math.round(s / 60) + ' min' : `${Math.floor(s / 3600)} h ${String(Math.round((s % 3600) / 60)).padStart(2, '0')}`;
}
const dlPct = d => Math.min(100, (d.done / d.total) * 100);
const steamCover = appid => (games.find(g => g.id === 'steam:' + appid) || {}).cover || '';
function renderActivity() {
  const on = theme.activity !== 'off';
  const d = on ? (act.downloads || []).find(x => x.active) : null;
  const game = on ? act.game : null;
  const g = on && (game || (act.gpu && act.gpu.load >= GAMING_LOAD)) ? act.gpu : null;
  const chip = $('.mini-act'), peek = $('.peek-act');
  chip.classList.toggle('hot', !d && !!g && g.temp >= 80);
  peek.classList.toggle('hot', !d && !!g && g.temp >= 80);
  if (d) {
    const pct = dlPct(d);
    const cover = steamCover(d.appid);
    const inst = d.phase === 'install';
    chip.innerHTML = `<span class="ms">${inst ? 'install_desktop' : 'download'}</span>${Math.floor(pct)} %`;
    // structure créée une fois par jeu : la barre glisse au lieu d'être redessinée
    if (peek.dataset.dl !== d.appid) {
      peek.dataset.dl = d.appid;
      peek.innerHTML = (cover ? `<img class="pa-cov" src="${cover}" alt="">` : '<span class="ms">download</span>')
        + '<span class="pa-text"><b></b><small></small><span class="pa-bar"><i></i></span></span>';
      peek.querySelector('b').textContent = d.name;
    }
    const eta = fmtEta(d);
    peek.querySelector('small').textContent = `${inst ? 'Installation' : 'Téléchargement'} ${Math.floor(pct)} % · ${fmtSize(d.done)} / ${fmtSize(d.total)}`
      + (d.speed ? ` · ${fmtSpeed(d.speed)}` : '') + (eta ? ` · ${eta}` : '');
    peek.querySelector('.pa-bar i').style.width = pct.toFixed(2) + '%';
  } else if (game) {
    // mode jeu : jaquette, temps de jeu, charge du PC
    peek.dataset.dl = '';
    const cover = (games.find(x => x.id === game.id) || {}).cover;
    const mins = Math.max(0, Math.floor((Date.now() - game.since) / 60000));
    const time = mins < 60 ? `${mins} min` : `${Math.floor(mins / 60)} h ${String(mins % 60).padStart(2, '0')}`;
    // sorti du jeu (file d'attente...) : chrono, l'îlot préviendra quand la partie est trouvée
    const away = game.away ? fmtTime((Date.now() - game.away) / 1000) : '';
    chip.classList.toggle('away', !!away);
    chip.innerHTML = away ? `<span class="ms">hourglass_top</span>${away}` : `<span class="ms">sports_esports</span>${g ? g.temp + '°' : time}`;
    const stats = [g && `GPU ${g.load} % · ${g.temp} °C`, lastSys && `CPU ${Math.round(lastSys.cpu)} %`].filter(Boolean).join(' · ');
    peek.innerHTML = (cover ? `<img class="pa-cov" src="${cover}" alt="">` : '<span class="ms">sports_esports</span>')
      + `<span class="pa-text"><b></b><small>${away ? `En attente depuis ${away}${theme.matchAlert !== 'off' ? ' · alerte quand la partie est trouvée' : ''}`
        : `En jeu depuis ${time}${stats ? ' · ' + stats : ''}`}</small></span>`;
    peek.querySelector('b').textContent = game.name;
  } else if (g) {
    peek.dataset.dl = '';
    const cpu = lastSys ? ` · CPU ${Math.round(lastSys.cpu)} %` : '';
    chip.innerHTML = `<span class="ms">sports_esports</span>${g.temp}°`;
    peek.innerHTML = `<span class="ms">sports_esports</span><span class="pa-text"><b></b><small>GPU ${g.load} % · ${g.temp} °C${cpu}</small></span>`;
    peek.querySelector('b').textContent = g.name;
  }
  const shown = !!(d || game || g);
  chip.hidden = peek.hidden = !shown;
  island.classList.toggle('act', shown);
  if (shown !== actChip) { actChip = shown; reportHit(); }
  updateGameDownloads();
}
// Launcher de jeux : progression posée sur la jaquette du jeu en téléchargement
function updateGameDownloads() {
  const grid = $('.app-grid.games');
  if (!grid) return;
  const by = new Map((act.downloads || []).map(d => ['steam:' + d.appid, d]));
  grid.querySelectorAll('.game[data-id]').forEach(el => {
    const d = by.get(el.dataset.id);
    let ov = el.querySelector('.dl');
    el.classList.toggle('downloading', !!d);
    if (!d) { if (ov) ov.remove(); return; }
    if (!ov) {
      ov = document.createElement('span');
      ov.className = 'dl';
      ov.innerHTML = '<span class="dl-pct"><span class="ms"></span><b></b></span><small></small><span class="dl-bar"><i></i></span>';
      el.append(ov);
    }
    const pct = dlPct(d);
    const inst = d.phase === 'install';
    ov.classList.toggle('paused', !d.active);
    ov.querySelector('.ms').textContent = !d.active ? 'pause' : inst ? 'install_desktop' : 'download';
    ov.querySelector('b').textContent = Math.floor(pct) + ' %';
    ov.querySelector('small').textContent = !d.active ? 'En pause'
      : inst ? 'Installation' : ['Téléchargement', d.speed && fmtSpeed(d.speed), fmtEta(d)].filter(Boolean).join(' · ');
    ov.querySelector('.dl-bar i').style.width = pct.toFixed(2) + '%';
  });
}
listen('activity', ({ payload }) => {
  const before = act.game && act.game.id;
  act = payload;
  if ((act.game && act.game.id) !== before) gameMode(act.game);
  renderActivity();
});
// ============================================================== compagnon
// petite bête dans la pilule repliée : danse sur la musique, met un casque en
// jeu, transpire si le GPU chauffe, dort la nuit, saute de joie quand une
// partie est trouvée. Apparence > Compagnon (Blob, Chat, Fantôme ou Masqué)
const pet = $('.pet');
let petParty = 0; // fin de la fête (partie trouvée)
let petTick = 0;
function applyPet() {
  const on = theme.pet !== 'off';
  pet.hidden = !on;
  ['blob', 'cat', 'ghost'].forEach(k => pet.classList.toggle(k, theme.pet === k));
  if (on !== petShown) { petShown = on; reportHit(); }
}
function petFx(sym) {
  const fx = pet.querySelector('.pet-fx');
  fx.textContent = sym;
  fx.classList.remove('go'); void fx.offsetWidth; fx.classList.add('go');
}
function petMood() {
  const h = new Date().getHours();
  const g = act.gpu;
  if (Date.now() < petParty) return 'party';
  if (notifShown) return 'surprise';
  if (act.game && g && g.temp >= 80) return 'hot';
  if (act.game) return 'game';
  if (media.playing) return 'music';
  if (((h >= 23 || h < 6) || away.on) && state === 'collapsed') return 'sleep';
  return 'idle';
}
setInterval(() => {
  if (!petShown || island.classList.contains('hidden')) return;
  petTick++;
  const mood = petMood();
  ['party', 'surprise', 'hot', 'game', 'music', 'sleep'].forEach(m => pet.classList.toggle(m, m === mood));
  if (mood !== 'music') pet.style.setProperty('--bop', 0);
  if (mood === 'music' && petTick % 3 === 0) petFx(Math.random() < 0.5 ? '♪' : '♫');
  if (mood === 'sleep' && petTick % 3 === 0) petFx('z');
  if (mood === 'hot' && petTick % 4 === 0) petFx('💧');
  if (mood === 'party' && petTick % 2 === 0) petFx('!');
  if (mood === 'idle' || mood === 'game' || mood === 'music') {
    // clignement, coup d'œil, petit saut de temps en temps
    if (Math.random() < 0.3) { pet.classList.add('blink'); setTimeout(() => pet.classList.remove('blink'), 140); }
    if (Math.random() < 0.15) pet.style.setProperty('--look', (Math.random() * 3 - 1.5).toFixed(1) + 'px');
    if (mood === 'idle' && Math.random() < 0.04) { pet.classList.add('hop'); setTimeout(() => pet.classList.remove('hop'), 520); }
    if (mood === 'idle' && Math.random() < 0.02) petFx('♥');
  }
}, 1000);
listen('match-found', () => { petParty = Date.now() + 8000; });
listen('steam-done', () => { petParty = Date.now() + 4000; });

// mise à jour Steam terminée : notification avec bouton Jouer
listen('steam-done', ({ payload: d }) => pushNotif({
  app: 'Steam', sym: 'download_done', icon: steamCover(d.appid), title: `${d.name} est prêt`,
  body: 'Mise à jour terminée', action: 'Jouer', url: `steam://rungameid/${d.appid}`, ms: 12000,
}));

// bilan de session à la fermeture d'un jeu (src/activity.rs) ;
// %LOCALAPPDATA%\Ilot\sessions.json : { list: [...100 dernières], total: { id: secondes } }
const fmtDur = s => { const m = Math.round(s / 60); return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}`; };
listen('game-session', async ({ payload: r }) => {
  if (r.secs < 60) return; // simple lancement / crash
  const st = (await invoke('store_get', { key: 'sessions' }).catch(() => null)) || {};
  const list = Array.isArray(st.list) ? st.list : [];
  const total = st.total && typeof st.total === 'object' ? st.total : {};
  total[r.id] = (total[r.id] || 0) + r.secs;
  list.unshift({ id: r.id, name: r.name, since: r.since, secs: r.secs, cpu: Math.round(r.cpu_avg), gpu: r.gpu_avg, temp: r.temp_max, ram: r.ram_max });
  invoke('store_set', { key: 'sessions', value: { list: list.slice(0, 100), total } });
  const stats = [
    r.gpu_avg >= 0 && `GPU ${r.gpu_avg} %`,
    r.temp_max > 0 && `${r.temp_max} °C max`,
    `CPU ${Math.round(r.cpu_avg)} %`,
    `RAM ${fmtSize(r.ram_max)}`,
  ].filter(Boolean).join(' · ');
  const cover = (games.find(x => x.id === r.id) || {}).cover;
  pushNotif({
    app: 'Bilan de session', sym: 'sports_esports', icon: cover, ms: 15000, tab: 'apps', force: true,
    title: `${r.name} · ${fmtDur(r.secs)}` + (total[r.id] > r.secs + 60 ? ` (total ${fmtDur(total[r.id])})` : ''),
    body: stats,
  });
});

// le temps de jeu affiché avance
setInterval(() => { if (act.game) renderActivity(); }, 30 * 1000);
setInterval(() => { if (act.game && act.game.away) renderActivity(); }, 1000);

// partie trouvée pendant que le joueur est ailleurs (src/activity.rs) : son,
// îlot qui clignote, clic = retour dans le jeu
function chime() {
  try {
    const ac = new AudioContext();
    [[880, 0], [1175, 0.16], [1568, 0.32]].forEach(([f, t]) => {
      const o = ac.createOscillator(), g = ac.createGain();
      o.type = 'sine'; o.frequency.value = f;
      g.gain.setValueAtTime(0.0001, ac.currentTime + t);
      g.gain.exponentialRampToValueAtTime(0.35, ac.currentTime + t + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + t + 0.5);
      o.connect(g).connect(ac.destination);
      o.start(ac.currentTime + t); o.stop(ac.currentTime + t + 0.55);
    });
    setTimeout(() => ac.close(), 1500);
  } catch {}
}
listen('match-found', ({ payload: name }) => {
  if (theme.matchAlert === 'off') return;
  chime();
  island.classList.add('match');
  setTimeout(() => island.classList.remove('match'), 5000);
  const cover = act.game ? (games.find(x => x.id === act.game.id) || {}).cover : '';
  pushNotif({ app: name, sym: 'sports_esports', icon: cover, title: 'Partie trouvée !', body: 'Clique pour retourner dans le jeu',
    action: 'Y aller', cmd: ['game_focus'], ms: 20000, force: true });
});

// ============================================================== mode jeu
// jeu du Launcher lancé : Windows en mode Performances (rétabli à la sortie),
// notifications de l'îlot en silence ; voir Apparence > Mode jeu
let gameOn = null; // { id, power } : mode d'alimentation d'avant le jeu
async function gameMode(game) {
  if (game && theme.gamemode !== 'off') {
    if (gameOn) return;
    gameOn = { id: game.id, power: '' };
    if (theme.gamePerf !== 'off') {
      const before = await invoke('power_get');
      if (before && before !== 'perf' && await invoke('power_set', { mode: 'perf' })) gameOn.power = before;
    }
    if (theme.gameNotif !== 'on') notifQ.length = 0;
    island.classList.add('gaming');
    gameMix(true);
  } else if (gameOn) {
    if (gameOn.power) invoke('power_set', { mode: gameOn.power });
    gameOn = null;
    island.classList.remove('gaming');
    gameMix(false);
  }
  refreshPower();
}

// =================================================================== PC
// --- Discord : RPC (src/discord.rs) si configuré, sinon mélangeur de volume Windows
let dc = { status: 'setup', people: [] };
const DC_STATUS = { setup: 'Mode simple', closed: 'Discord fermé', authorizing: 'Autorise Ilot dans Discord…', ready: 'Connecté', error: 'Erreur' };
const dcRpc = () => dc.status === 'ready';
let dcLocal = { mic: false, out: false }; // sourdines Windows (mode simple)

function renderDiscord() {
  $('.dc-status').textContent = DC_STATUS[dc.status] || dc.status;
  $('.dc-status').classList.toggle('ok', dcRpc());
  $('.dc-status').classList.toggle('bad', dc.status === 'error');
  const mic = dcRpc() ? dc.mute : dcLocal.mic;
  const deaf = dcRpc() ? dc.deaf : dcLocal.out;
  $('#dc-mic').classList.toggle('off', mic);
  $('#dc-mic .ms').textContent = mic ? 'mic_off' : 'mic';
  $('#dc-mic').title = mic ? 'Réactiver le micro' : 'Couper le micro';
  $('#dc-deaf').classList.toggle('off', deaf);
  $('#dc-deaf .ms').textContent = deaf ? 'headset_off' : 'headphones';
  $('#dc-deaf').title = deaf ? 'Réactiver le son' : 'Couper le son (sourdine)';

  const setup = $('.dc-setup');
  const showSetup = dc.status === 'setup' || dc.status === 'error' || setup.dataset.open === '1';
  setup.hidden = !showSetup;
  $('#dc-forget').hidden = dc.status === 'setup';
  $('.dc-err').textContent = dc.status === 'error' ? dc.error : '';
  $('.dc-err').classList.toggle('err', dc.status === 'error');

  const chan = $('.dc-chan');
  const box = $('.dc-people');
  box.innerHTML = '';
  if (showSetup) { chan.textContent = ''; return; }
  if (!dcRpc()) {
    chan.textContent = dc.status === 'authorizing'
      ? 'Une fenêtre d’autorisation s’est ouverte dans Discord : clique sur « Autoriser ».'
      : 'Lance Discord pour voir les personnes du salon.';
    return;
  }
  chan.innerHTML = dc.channel ? `<span class="ms">volume_up</span>` : '';
  chan.append(dc.channel ? dc.channel : 'Pas dans un salon vocal');
  if (dc.error) chan.insertAdjacentHTML('beforeend', ` <small class="err">(${dc.error.replace(/[<>&]/g, '')})</small>`);
  dc.people.forEach(p => {
    if (p.id === dc.me_id) return box.append(selfRow(p));
    const el = document.createElement('div');
    el.className = 'dc-person' + (p.speaking ? ' speaking' : '') + (p.mute ? ' muted' : '');
    el.innerHTML = `<span class="av">${p.avatar ? `<img src="${p.avatar}" alt="">` : ''}</span>
      <div class="dp-main"><div class="dp-name"><b></b><span class="dp-flags"></span></div>
      <input type="range" class="slider" min="0" max="200" value="${Math.round(p.volume)}"></div>
      <span class="dp-val">${Math.round(p.volume)}%</span>
      <button class="icon-btn small" title="${p.mute ? 'Réactiver' : 'Rendre muet (pour moi)'}"><span class="ms">${p.mute ? 'volume_off' : 'volume_up'}</span></button>`;
    el.querySelector('b').textContent = p.name;
    if (!p.avatar) el.querySelector('.av').textContent = (p.name[0] || '?').toUpperCase();
    el.querySelector('.dp-flags').innerHTML = (p.self_mute ? '<span class="ms">mic_off</span>' : '') + (p.self_deaf ? '<span class="ms">headset_off</span>' : '');
    const r = el.querySelector('input');
    r.style.setProperty('--p', (p.volume / 2) + '%');
    r.addEventListener('input', () => {
      r.style.setProperty('--p', (r.value / 2) + '%');
      el.querySelector('.dp-val').textContent = r.value + '%';
      p.volume = Number(r.value);
      invoke('discord_user', { userId: p.id, volume: p.volume });
    });
    r.addEventListener('wheel', e => e.stopPropagation(), { passive: true });
    el.querySelector('button').addEventListener('click', () => invoke('discord_user', { userId: p.id, mute: !p.mute }).then(() => { p.mute = !p.mute; renderDiscord(); }));
    box.append(el);
  });
}
// sa propre ligne : Discord ignore le volume « utilisateur » qu'on s'applique,
// le curseur règle donc le volume du micro (0-100) et le bouton la sourdine micro
function selfRow(p) {
  const el = document.createElement('div');
  const vol = Math.round(dc.mic_volume ?? 100);
  el.className = 'dc-person me' + (p.speaking ? ' speaking' : '') + (dc.mute ? ' muted' : '');
  el.innerHTML = `<span class="av">${p.avatar ? `<img src="${p.avatar}" alt="">` : ''}</span>
    <div class="dp-main"><div class="dp-name"><b></b><span class="dp-flags"><span class="ms" title="Volume de ton micro">mic</span></span></div>
    <input type="range" class="slider" min="0" max="100" value="${vol}" title="Volume de ton micro dans Discord"></div>
    <span class="dp-val">${vol}%</span>
    <button class="icon-btn small" title="${dc.mute ? 'Réactiver le micro' : 'Couper le micro'}"><span class="ms">${dc.mute ? 'mic_off' : 'mic'}</span></button>`;
  el.querySelector('b').textContent = p.name + ' (toi)';
  if (!p.avatar) el.querySelector('.av').textContent = (p.name[0] || '?').toUpperCase();
  const r = el.querySelector('input');
  r.style.setProperty('--p', vol + '%');
  r.addEventListener('input', () => {
    r.style.setProperty('--p', r.value + '%');
    el.querySelector('.dp-val').textContent = r.value + '%';
    dc.mic_volume = Number(r.value);
    invoke('discord_mic', { volume: dc.mic_volume });
  });
  r.addEventListener('wheel', e => e.stopPropagation(), { passive: true });
  el.querySelector('button').addEventListener('click', () => invoke('discord_self', { mute: !dc.mute }));
  return el;
}
// pendant qu'on fait glisser un curseur, on ne reconstruit pas la liste
listen('discord', ({ payload }) => {
  dc = payload;
  renderDcPill();
  if (document.activeElement?.closest?.('.dc-people')) return;
  renderDiscord();
});
invoke('discord_get').then(s => { dc = s; renderDiscord(); renderDcPill(); });

// --- raccourcis dans la pilule : micro + sourdine, quand on est en vocal
// (mode connecté) ou que Discord tourne (mode simple)
let dcRunning = false;
async function checkDcRunning() {
  const [on] = await invoke('procs_running', { names: ['Discord'] }).catch(() => [false]);
  if (on !== dcRunning) { dcRunning = on; renderDcPill(); }
}
checkDcRunning();
setInterval(checkDcRunning, 10 * 1000);
function renderDcPill() {
  const show = theme.dcPill !== 'off' && (dcRpc() ? !!dc.channel : dcRunning);
  const mic = dcRpc() ? dc.mute : dcLocal.mic;
  const deaf = dcRpc() ? dc.deaf : dcLocal.out;
  const mini = $('.mini-dc');
  mini.hidden = !show;
  mini.classList.toggle('off', mic || deaf);
  mini.querySelector('.ms').textContent = deaf ? 'headset_off' : mic ? 'mic_off' : 'mic';
  mini.classList.toggle('speaking', dcRpc() && dc.people.some(p => p.id === dc.me_id && p.speaking));
  const peek = $('.peek-dc');
  peek.hidden = !show;
  const [bm, bd] = peek.querySelectorAll('button');
  bm.classList.toggle('off', mic);
  bm.querySelector('.ms').textContent = mic ? 'mic_off' : 'mic';
  bm.title = mic ? 'Réactiver le micro (Discord)' : 'Couper le micro (Discord)';
  bd.classList.toggle('off', deaf);
  bd.querySelector('.ms').textContent = deaf ? 'headset_off' : 'headphones';
  bd.title = deaf ? 'Réactiver le son (Discord)' : 'Sourdine (Discord)';
  if (show !== dcShown) { dcShown = show; reportHit(); }
}
// mêmes actions que les boutons de l'onglet PC
$$('.peek-dc [data-dc]').forEach(b => b.addEventListener('click', async e => {
  e.stopPropagation();
  $(b.dataset.dc === 'mic' ? '#dc-mic' : '#dc-deaf').click();
  setTimeout(renderDcPill, 150);
}));

$('#dc-mic').addEventListener('click', async () => {
  if (dcRpc()) return invoke('discord_self', { mute: !dc.mute });
  dcLocal.mic = !dcLocal.mic;
  const ok = await invoke('app_volume_set', { app: 'discord', mic: true, muted: dcLocal.mic });
  if (!ok) dcLocal.mic = false;
  renderDiscord();
});
$('#dc-deaf').addEventListener('click', async () => {
  if (dcRpc()) return invoke('discord_self', { deaf: !dc.deaf });
  dcLocal.out = !dcLocal.out;
  const ok = await invoke('app_volume_set', { app: 'discord', muted: dcLocal.out });
  if (!ok) dcLocal.out = false;
  renderDiscord();
});
const dcVol = $('#dc-vol');
function showDcVolume(v) {
  dcVol.disabled = !v;
  const n = v ? Math.round(v.level * 100) : 0;
  dcVol.value = n;
  dcVol.style.setProperty('--p', n + '%');
  $('.dc-vol-val').textContent = v ? n : '–';
  $('.dc-vol').title = v ? 'Volume de Discord (mélangeur Windows)' : 'Discord ne joue pas de son pour l’instant';
  if (v && !dcRpc()) dcLocal.out = v.muted;
}
dcVol.addEventListener('input', () => {
  showDcVolume({ level: dcVol.value / 100, muted: false });
  invoke('app_volume_set', { app: 'discord', level: dcVol.value / 100 });
});
dcVol.addEventListener('wheel', e => e.stopPropagation(), { passive: true });
$('#dc-settings').addEventListener('click', () => {
  const s = $('.dc-setup');
  s.dataset.open = s.dataset.open === '1' ? '' : '1';
  renderDiscord();
});
$('.dc-setup').addEventListener('submit', async e => {
  e.preventDefault();
  const f = e.currentTarget;
  try {
    await invoke('discord_setup', { clientId: f.cid.value, secret: f.secret.value });
    f.reset();
    f.dataset.open = '';
    $('.dc-err').textContent = '';
  } catch (ex) {
    $('.dc-err').textContent = String(ex);
    $('.dc-err').classList.add('err');
  }
});
$('#dc-forget').addEventListener('click', () => { invoke('discord_forget'); $('.dc-setup').dataset.open = ''; });
$$('.dc-setup input').forEach(i => i.addEventListener('focus', () => { pinned = true; }));

// --- logiciels constructeur : nom dans le menu Démarrer + exécutable de leur interface
const HARDWARE = [
  { match: /^msi center/i, exe: 'DCv2', label: 'MSI Center', icon: 'memory' },
  { match: /^armoury crate/i, exe: 'ArmouryCrate', label: 'Armoury Crate', icon: 'developer_board' },
  { match: /^logitech g hub/i, exe: 'lghub', label: 'Logitech G HUB', icon: 'mouse' },
];
async function renderHardware() {
  const list = HARDWARE.map(h => ({ ...h, app: apps.find(a => h.match.test(a.name)) }));
  const running = await invoke('procs_running', { names: list.map(h => h.exe) });
  const box = $('.hw-list');
  box.innerHTML = '';
  list.forEach((h, i) => {
    const b = document.createElement('button');
    b.className = 'hw' + (running[i] ? ' on' : '') + (h.app ? '' : ' missing');
    b.innerHTML = (h.app?.icon ? `<img src="${h.app.icon}" alt="">` : `<span class="ms">${h.icon}</span>`) + '<span class="hw-name"></span><i></i>';
    b.querySelector('.hw-name').textContent = h.label;
    b.querySelector('i').textContent = !h.app ? 'non installé' : running[i] ? 'ouvert' : '';
    b.disabled = !h.app;
    b.addEventListener('click', () => { invoke('app_launch', { id: h.app.id }); setState('collapsed'); });
    b.addEventListener('contextmenu', e => {
      e.preventDefault();
      if (h.app) invoke('app_folder', { id: h.app.id, name: h.app.name }).then(ok => ok && setState('collapsed'));
    });
    box.append(b);
  });
}

// --- mode d'alimentation de Windows 11
async function refreshPower() {
  const m = await invoke('power_get');
  $$('.pw-modes button').forEach(b => b.classList.toggle('on', b.dataset.pw === m));
  $('.pw-note').textContent = m ? '' : 'Mode non disponible avec le plan d’alimentation actuel (il faut « Utilisation normale »).';
}
$$('.pw-modes button').forEach(b => b.addEventListener('click', async () => {
  $$('.pw-modes button').forEach(x => x.classList.toggle('on', x === b));
  if (!await invoke('power_set', { mode: b.dataset.pw })) refreshPower();
}));

// --- mélangeur : volume de chaque appli / jeu qui a une session audio (src/audio.rs)
const MIX_NAMES = {
  '@system': 'Sons système', msedge: 'Microsoft Edge', msedgewebview2: 'Edge WebView', chrome: 'Google Chrome',
  firefox: 'Firefox', opera: 'Opera', brave: 'Brave', spotify: 'Spotify', discord: 'Discord', steam: 'Steam',
  steamwebhelper: 'Steam', vlc: 'VLC', obs64: 'OBS', robloxplayerbeta: 'Roblox', javaw: 'Minecraft (Java)',
};
const mixName = exe => MIX_NAMES[exe] || games.find(g => g.name && norm(g.name).replace(/\s/g, '') === exe)?.name
  || exe.charAt(0).toUpperCase() + exe.slice(1);
async function refreshMixer() {
  const list = await invoke('mixer_get');
  // pendant qu'on fait glisser un curseur, on ne reconstruit pas la liste
  if (document.activeElement?.closest?.('.mix-list')) return;
  const box = $('.mix-list');
  if (!list.length) { box.innerHTML = '<div class="sp-hint">Aucune appli ne joue de son.</div>'; return; }
  box.innerHTML = '';
  list.sort((x, y) => y.active - x.active || (x.exe === '@system') - (y.exe === '@system') || mixName(x.exe).localeCompare(mixName(y.exe), 'fr'));
  list.forEach(a => {
    const el = document.createElement('div');
    el.className = 'mix' + (a.active ? ' active' : '') + (a.muted ? ' muted' : '');
    const n = Math.round(a.level * 100);
    el.innerHTML = (a.icon ? `<img src="${a.icon}" alt="">` : `<span class="ms">${a.exe === '@system' ? 'notifications' : 'music_note'}</span>`)
      + `<div class="mix-main"><span class="mix-name"></span><input type="range" class="slider" min="0" max="100" value="${n}"></div>`
      + `<span class="mix-val">${n}</span>`
      + `<button class="icon-btn small" title="${a.muted ? 'Réactiver' : 'Couper le son'}"><span class="ms">${a.muted ? 'volume_off' : 'volume_up'}</span></button>`;
    el.querySelector('.mix-name').textContent = mixName(a.exe);
    el.title = a.active ? 'Joue du son en ce moment' : '';
    const r = el.querySelector('input');
    r.style.setProperty('--p', n + '%');
    r.addEventListener('input', () => {
      r.style.setProperty('--p', r.value + '%');
      el.querySelector('.mix-val').textContent = r.value;
      invoke('mixer_set', { exe: a.exe, level: r.value / 100 });
    });
    // relâché : on rend la main au rafraîchissement automatique
    r.addEventListener('change', () => r.blur());
    r.addEventListener('wheel', e => e.stopPropagation(), { passive: true });
    el.querySelector('button').addEventListener('click', async () => {
      await invoke('mixer_set', { exe: a.exe, muted: !a.muted });
      refreshMixer();
    });
    box.append(el);
  });
}

// ============================================ pochette 3D (onglet Média)
{
  const art = $('.mp-art');
  art.addEventListener('mousemove', e => {
    const r = art.getBoundingClientRect();
    const px = (e.clientX - r.left) / r.width, py = (e.clientY - r.top) / r.height;
    art.classList.add('tilt');
    art.style.setProperty('--ry', ((px - 0.5) * 22).toFixed(1) + 'deg');
    art.style.setProperty('--rx', ((0.5 - py) * 22).toFixed(1) + 'deg');
    art.style.setProperty('--gx', (px * 100).toFixed(0) + '%');
    art.style.setProperty('--gy', (py * 100).toFixed(0) + '%');
  });
  art.addEventListener('mouseleave', () => {
    art.classList.remove('tilt');
    art.style.setProperty('--rx', '0deg');
    art.style.setProperty('--ry', '0deg');
  });
}

// ============================== taille / position / écran de l'îlot (src/prefs.rs)
function applyPlacement() {
  const h = document.documentElement;
  placement.k = PILL_SCALE[theme.pillSize] || 1;
  placement.bottom = theme.pillPos === 'bottom';
  ['s', 'l'].forEach(k => h.classList.toggle('pill-' + k, theme.pillSize === k));
  h.classList.toggle('pos-bottom', theme.pillPos === 'bottom');
  const mon = theme.screen === 'main' ? null : Number(theme.screen);
  invoke('set_placement', { bottom: theme.pillPos === 'bottom', monitor: Number.isInteger(mon) ? mon : null });
  reportHit();
}
invoke('monitors_list').then(list => {
  if (list.length < 2) return;
  OPTS.screen = [['main', 'Écran principal'], ...list.map((m, i) => [String(i), m.name + (m.primary ? ' · principal' : '')])];
  renderThemePanel();
}).catch(() => {});

// ============================== raccourcis clavier globaux (src/prefs.rs)
const KEY_ACTIONS = [
  ['toggle', 'Ouvrir / fermer l’îlot'], ['play', 'Lecture / pause'], ['next', 'Morceau suivant'], ['captions', 'Sous-titres en direct'],
  ...$$('#tabs button').map(b => [b.dataset.tab, b.querySelector('span:not(.ms)').textContent]),
];
let keyMap = {};
let keyBad = [];
let keyRec = null;
// « Ctrl+Alt+KeyM » -> « Ctrl+Alt+M »
const keyLabel = c => c.replace(/Key([A-Z])/g, '$1').replace(/Digit(\d)/g, '$1').replace(/Numpad/g, 'Pavé ');
function renderKeys() {
  const box = $('.keys');
  box.innerHTML = '';
  KEY_ACTIONS.forEach(([id, label]) => {
    const row = document.createElement('div');
    row.className = 'key-row' + (keyBad.includes(id) ? ' bad' : '');
    row.innerHTML = '<span></span><button></button>';
    row.querySelector('span').textContent = label;
    const b = row.querySelector('button');
    b.textContent = keyRec === id ? 'Appuie…' : keyMap[id] ? keyLabel(keyMap[id]) : '—';
    b.classList.toggle('set', !!keyMap[id]);
    b.classList.toggle('rec', keyRec === id);
    b.title = keyBad.includes(id) ? 'Déjà pris par une autre appli : choisis-en un autre'
      : 'Clic puis appuie sur la combinaison · Échap : annuler · Retour arrière : effacer';
    b.addEventListener('click', () => { keyRec = keyRec === id ? null : id; pinned = true; renderKeys(); });
    box.append(row);
  });
}
async function saveKeys() {
  keyBad = await invoke('shortcuts_set', { map: keyMap }).catch(() => []);
  renderKeys();
}
addEventListener('keydown', e => {
  if (!keyRec) return;
  e.preventDefault();
  e.stopPropagation();
  if (e.key === 'Escape') { keyRec = null; return renderKeys(); }
  if (e.key === 'Backspace' || e.key === 'Delete') { delete keyMap[keyRec]; keyRec = null; return saveKeys(); }
  if (['Control', 'Alt', 'Shift', 'Meta', 'AltGraph'].includes(e.key)) return;
  const mods = [e.ctrlKey && 'Ctrl', e.altKey && 'Alt', e.shiftKey && 'Shift', e.metaKey && 'Super'].filter(Boolean);
  // une touche seule bloquerait la frappe partout dans Windows (sauf F1-F24)
  if (!mods.length && !/^F\d+$/.test(e.code)) { showOsd('keyboard', null, 'Ajoute Ctrl, Alt ou Maj'); return; }
  keyMap[keyRec] = [...mods, e.code].join('+');
  keyRec = null;
  saveKeys();
}, true);
invoke('shortcuts_get').then(m => { keyMap = m || {}; renderKeys(); });
listen('shortcut', ({ payload: a }) => {
  if (a === 'play') return invoke('media_action', { action: 'toggle' });
  if (a === 'captions') return toggleCaptions();
  if (a === 'next') return invoke('media_action', { action: 'next' });
  if (a === 'toggle') return state === 'open' ? close() : (pinned = true, open(currentTab));
  if (state === 'open' && currentTab === a) return close();
  pinned = true;
  open(a);
});

// ========================================== sauvegarde des réglages (src/prefs.rs)
const LOCAL_KEYS = ['palette', 'lyrics'];
$('#bk-export').addEventListener('click', async () => {
  const local = {};
  LOCAL_KEYS.forEach(k => { try { const v = localStorage.getItem(k); if (v != null) local[k] = v; } catch {} });
  const path = await invoke('settings_export', { local }).catch(() => null);
  showOsd(path ? 'download_done' : 'error', null, path ? 'Réglages exportés dans Téléchargements' : 'Export impossible');
});
$('#bk-import input').addEventListener('change', async e => {
  const f = e.target.files[0];
  e.target.value = '';
  if (!f) return;
  try {
    const local = await invoke('settings_import', { content: await f.text() });
    if (local && typeof local === 'object') Object.entries(local).forEach(([k, v]) => { try { localStorage.setItem(k, v); } catch {} });
    const keys = await invoke('shortcuts_get');
    await invoke('shortcuts_set', { map: keys || {} });
    showOsd('upload', null, 'Réglages restaurés');
    setTimeout(() => location.reload(), 900);
  } catch (ex) {
    showOsd('error', null, String(ex));
  }
});

// ================================== voyant caméra / micro (src/privacy.rs)
let priv = { cam: [], mic: [] };
function renderPrivacy() {
  const el = $('.mini-priv');
  const on = theme.privacy !== 'off' && (priv.cam.length || priv.mic.length);
  el.hidden = !on;
  el.classList.toggle('cam', priv.cam.length > 0);
  el.classList.toggle('mic', priv.mic.length > 0);
  el.title = [priv.cam.length && `Caméra : ${priv.cam.join(', ')}`, priv.mic.length && `Micro : ${priv.mic.join(', ')}`].filter(Boolean).join('\n');
  if (!!on !== privShown) { privShown = !!on; reportHit(); }
}
listen('privacy', ({ payload }) => {
  // une appli qui allume la caméra : notification (le micro, lui, sert tout le temps en vocal)
  const fresh = payload.cam.filter(a => !priv.cam.includes(a));
  priv = payload;
  renderPrivacy();
  if (fresh.length && theme.privacy !== 'off') {
    pushNotif({ app: 'Confidentialité', sym: 'videocam', title: `${fresh.join(', ')} utilise ta caméra`, body: 'Le voyant vert reste allumé tant qu’elle filme', ms: 7000, force: true });
  }
});

// ================================== convertisseur de sensibilité (onglet PC)
// degrés tournés par « point » de souris à la sensibilité 1
const SENS_GAMES = [
  ['apex', 'Apex Legends', 0.022], ['cs2', 'Counter-Strike 2', 0.022], ['valorant', 'Valorant', 0.07],
  ['ow2', 'Overwatch 2', 0.0066], ['cod', 'Call of Duty (MW / Warzone)', 0.0066], ['tf2', 'Titanfall 2', 0.022],
  ['gmod', 'Garry’s Mod', 0.022], ['quake', 'Quake Champions', 0.022],
];
const sensSel = $('#sens-game'), sensVal = $('#sens-val'), sensDpi = $('#sens-dpi');
sensSel.innerHTML = SENS_GAMES.map(([id, name]) => `<option value="${id}">${name}</option>`).join('');
try {
  const s = JSON.parse(localStorage.getItem('sens') || '{}');
  if (s.game) sensSel.value = s.game;
  sensVal.value = s.val ?? '';
  sensDpi.value = s.dpi ?? 800;
} catch { sensDpi.value = 800; }
function renderSens() {
  const src = SENS_GAMES.find(g => g[0] === sensSel.value);
  const v = parseFloat(sensVal.value), dpi = parseFloat(sensDpi.value);
  try { localStorage.setItem('sens', JSON.stringify({ game: sensSel.value, val: sensVal.value, dpi: sensDpi.value })); } catch {}
  const out = $('.sens-out'), cm = $('.sens-cm');
  out.innerHTML = '';
  if (!(v > 0) || !(dpi > 0)) { cm.textContent = 'Entre ta sensi et le DPI de ta souris.'; return; }
  const deg = v * src[2]; // degrés par point
  const cm360 = 360 / (deg * dpi) * 2.54;
  cm.innerHTML = `<b>${cm360.toFixed(1).replace('.', ',')} cm</b> pour un tour complet (360°)`;
  SENS_GAMES.filter(g => g[0] !== src[0]).forEach(([, name, yaw]) => {
    const val = (deg / yaw).toFixed(3).replace(/\.?0+$/, '');
    const b = document.createElement('button');
    b.innerHTML = `<span></span><b>${val}</b>`;
    b.querySelector('span').textContent = name;
    b.title = 'Copier';
    b.addEventListener('click', () => {
      invoke('clip_copy', { text: val });
      b.classList.add('done');
      setTimeout(() => b.classList.remove('done'), 1000);
    });
    out.append(b);
  });
}
[sensSel, sensVal, sensDpi].forEach(i => i.addEventListener('input', renderSens));
$$('.sens-in input').forEach(i => i.addEventListener('wheel', e => e.stopPropagation(), { passive: true }));
renderSens();

// ================================== compagnon baladeur (ui/pet.html, src/prefs.rs)
// après 90 s sans clavier ni souris, il descend de la pilule et se promène
// au-dessus de la barre des tâches ; il remonte dès que tu reviens
const PET_IDLE = 90;
const emitEv = window.__TAURI__.event.emit;
let petOut = false;
function petCfg(on, idle = 0) {
  const cs = getComputedStyle(document.documentElement);
  const c = k => cs.getPropertyValue('--' + k).trim();
  emitEv('pet-cfg', {
    on, species: theme.pet, sleepy: idle > 600 || new Date().getHours() < 6,
    primary: c('primary'), 'on-primary': c('on-primary'), surface: c('surface'), 'on-surface': c('on-surface'),
  });
}
setInterval(async () => {
  const can = theme.petWalk !== 'off' && theme.pet !== 'off' && !gameOn && state === 'collapsed'
    && !island.classList.contains('hidden') && !notifShown;
  const idle = await invoke('idle_secs').catch(() => 0);
  if (can && idle >= PET_IDLE) {
    if (!petOut) {
      petOut = true;
      island.classList.add('pet-out');
      await invoke('pet_walk', { on: true });
      setTimeout(() => petCfg(true, idle), 700); // la fenêtre vient d'être créée
    } else petCfg(true, idle);
  } else if (petOut && (!can || idle < 3)) {
    petOut = false;
    petCfg(false);
    setTimeout(() => { invoke('pet_walk', { on: false }); island.classList.remove('pet-out'); }, 750);
  }
}, 4000);

// ============================== sous-titres en direct (src/captions.rs, ui/captions.html)
let capOn = false;
async function toggleCaptions(on = !capOn) {
  capOn = await invoke('captions_set', { on });
  $('#tr-live').classList.toggle('on', capOn);
  showOsd('closed_caption', null, capOn ? 'Sous-titres en direct activés' : 'Sous-titres coupés');
}
$('#tr-live').addEventListener('click', () => toggleCaptions());
invoke('captions_on').then(v => { capOn = v; $('#tr-live').classList.toggle('on', v); });

// ============================== extinction programmée (onglet PC)
// { action, at (ms) } ou { action, wait: 'media' | 'steam' } ; gardé dans localStorage
const OFF_LABEL = { shutdown: 'Extinction', sleep: 'Mise en veille', restart: 'Redémarrage' };
let off = null;
let offAction = 'shutdown';
let offCalm = 0; // secondes sans média / sans téléchargement
try { off = JSON.parse(localStorage.getItem('offTimer') || 'null'); } catch {}
// heure dépassée pendant que l'îlot était fermé : surtout ne pas éteindre au démarrage
if (off?.at && off.at < Date.now() + 5000) off = null;
const saveOff = () => { try { localStorage.setItem('offTimer', JSON.stringify(off)); } catch {} };
function setOff(v) {
  off = v;
  offCalm = 0;
  saveOff();
  renderOff();
  if (v) showOsd('timer', null, v.at ? `${OFF_LABEL[v.action]} à ${new Date(v.at).toTimeString().slice(0, 5)}` : `${OFF_LABEL[v.action]} : ${v.wait === 'media' ? 'à la fin du média' : 'après les MAJ Steam'}`);
}
const fmtLeft = ms => { const s = Math.max(0, Math.round(ms / 1000)); return s >= 3600 ? `${Math.floor(s / 3600)} h ${String(Math.floor(s % 3600 / 60)).padStart(2, '0')}` : `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
function renderOff() {
  $$('.off-acts button').forEach(b => b.classList.toggle('on', b.dataset.a === (off?.action || offAction)));
  const st = $('.off-state');
  st.hidden = !off;
  if (off) st.querySelector('b').textContent = off.at
    ? `${OFF_LABEL[off.action]} dans ${fmtLeft(off.at - Date.now())}`
    : `${OFF_LABEL[off.action]} ${off.wait === 'media' ? 'à la fin du média' : 'à la fin des MAJ Steam'}`;
  // pilule : minuteur visible dans les 30 dernières minutes
  const mini = $('.mini-off');
  const show = !!off?.at && off.at - Date.now() < 30 * 60 * 1000;
  mini.hidden = !show;
  if (show) mini.querySelector('b').textContent = fmtLeft(off.at - Date.now());
  if (show !== offShown) { offShown = show; reportHit(); }
}
$$('.off-acts button').forEach(b => b.addEventListener('click', () => {
  offAction = b.dataset.a;
  if (off) { off.action = offAction; saveOff(); }
  renderOff();
}));
$$('.off-presets [data-m]').forEach(b => b.addEventListener('click', () => setOff({ action: offAction, at: Date.now() + b.dataset.m * 60000 })));
$$('.off-presets [data-w]').forEach(b => b.addEventListener('click', () => setOff({ action: offAction, wait: b.dataset.w })));
$('#off-time').addEventListener('change', e => {
  const [h, m] = e.target.value.split(':').map(Number);
  if (isNaN(h)) return;
  const d = new Date(); d.setHours(h, m, 0, 0);
  if (d <= new Date()) d.setDate(d.getDate() + 1); // heure passée : demain
  setOff({ action: offAction, at: d.getTime() });
});
$('#off-cancel').addEventListener('click', () => { setOff(null); showOsd('timer_off', null, 'Extinction annulée'); });
let offWarned = false;
setInterval(() => {
  if (!off) return;
  if (off.wait) {
    // fin du média / des téléchargements : 1 min de calme, puis compte à rebours de 60 s
    const busy = off.wait === 'media' ? media.playing : (act.downloads || []).length > 0;
    offCalm = busy ? 0 : offCalm + 1;
    if (offCalm >= 60) { off = { action: off.action, at: Date.now() + 60000 }; saveOff(); }
  }
  if (off.at) {
    const left = off.at - Date.now();
    if (left <= 60000 && !offWarned) {
      offWarned = true;
      pushNotif({ app: 'Extinction programmée', sym: 'power_settings_new', title: `${OFF_LABEL[off.action]} dans 1 minute`,
        body: 'Clique pour annuler', action: 'Annuler', fn: () => setOff(null), ms: 55000, force: true });
    }
    if (left > 60000) offWarned = false;
    if (left <= 0) {
      const a = off.action;
      setOff(null);
      invoke('power_action', { action: a });
      return;
    }
  }
  renderOff();
}, 1000);
renderOff();

// --- profils de volume : { jeu: { exe: niveau }, chill: {...} } dans mixprofiles.json
const MIX_PROFILES = [['jeu', 'Jeu', 'sports_esports'], ['chill', 'Chill', 'self_improvement']];
let mixProfiles = {};
invoke('store_get', { key: 'mixprofiles' }).then(p => { if (p && typeof p === 'object') mixProfiles = p; renderMixProfiles(); });
function renderMixProfiles(on) {
  const box = $('.mix-prof');
  box.innerHTML = '';
  MIX_PROFILES.forEach(([id, label, icon]) => {
    const has = mixProfiles[id] && Object.keys(mixProfiles[id]).length;
    const el = document.createElement('div');
    el.className = 'mp-prof' + (has ? '' : ' unset') + (on === id ? ' on' : '');
    el.innerHTML = `<button class="mp-apply" title="${has ? 'Appliquer' : 'Pas encore enregistré : clique sur la disquette'}"><span class="ms">${icon}</span>${label}</button>`
      + `<button class="mp-save" title="Enregistrer les volumes actuels comme « ${label} »"><span class="ms">save</span></button>`;
    el.querySelector('.mp-apply').addEventListener('click', async () => {
      if (!has) return;
      await applyMixProfile(mixProfiles[id]);
      renderMixProfiles(id);
      refreshMixer();
    });
    el.querySelector('.mp-save').addEventListener('click', async () => {
      const list = await invoke('mixer_get');
      mixProfiles[id] = Object.fromEntries(list.map(a => [a.exe, a.muted ? 0 : Math.round(a.level * 100) / 100]));
      invoke('store_set', { key: 'mixprofiles', value: mixProfiles });
      renderMixProfiles(id);
      showOsd('save', null, `Profil « ${label} » enregistré`);
    });
    box.append(el);
  });
}
async function applyMixProfile(p) {
  const list = await invoke('mixer_get');
  for (const a of list) {
    if (!(a.exe in p)) continue;
    await invoke('mixer_set', { exe: a.exe, level: p[a.exe], muted: p[a.exe] === 0 });
  }
}
// mode jeu : profil « Jeu » au lancement, volumes d'avant rétablis à la fermeture
let mixBefore = null;
async function gameMix(on) {
  if (theme.mixAuto === 'off') return;
  if (on && !mixBefore && mixProfiles.jeu) {
    const list = await invoke('mixer_get');
    mixBefore = Object.fromEntries(list.map(a => [a.exe, a.muted ? 0 : a.level]));
    await applyMixProfile(mixProfiles.jeu);
    // le son du jeu n'apparaît parfois qu'après quelques secondes
    setTimeout(() => gameOn && applyMixProfile(mixProfiles.jeu), 20000);
  } else if (!on && mixBefore) {
    await applyMixProfile(mixBefore);
    mixBefore = null;
  }
}

// --- santé du PC (src/health.rs) : disques, pilote NVIDIA, nettoyage
let healthAt = 0;
async function refreshHealth(force) {
  if (!force && Date.now() - healthAt < 60 * 1000) return;
  healthAt = Date.now();
  const h = await invoke('health_get').catch(() => null);
  if (!h) return;
  const dk = $('.hl-disks');
  dk.innerHTML = '';
  h.disks.forEach(d => {
    const used = 1 - d.free / d.total;
    const bad = d.health && d.health !== 'Healthy';
    const el = document.createElement('div');
    el.className = 'hl-disk' + (d.free / d.total < 0.1 ? ' low' : '') + (bad ? ' bad' : '');
    el.innerHTML = `<span class="ms">${d.media === 'HDD' ? 'album' : 'hard_drive'}</span><b></b><small></small><div class="bar"><i></i></div>`;
    el.querySelector('b').textContent = `${d.mount} ${d.name}`;
    el.querySelector('small').textContent = `${fmtSize(d.free)} libres` + (bad ? ' · ⚠ ' + (d.health === 'Warning' ? 'à surveiller' : 'en panne') : '');
    el.querySelector('i').style.width = (used * 100).toFixed(1) + '%';
    el.title = `${fmtSize(d.total - d.free)} utilisés sur ${fmtSize(d.total)}` + (d.media ? ` · ${d.media}` : '')
      + (d.health ? ` · état : ${d.health === 'Healthy' ? 'sain' : d.health}` : '');
    dk.append(el);
  });
  const dv = $('.hl-drv');
  const drv = h.driver;
  dv.hidden = !drv.installed;
  if (drv.installed) {
    const newer = drv.latest && verGt(drv.latest, drv.installed);
    dv.className = 'hl-drv' + (newer ? ' new' : '');
    dv.innerHTML = `<span class="ms">${newer ? 'system_update' : 'verified'}</span><span></span>`;
    dv.querySelector('span:last-child').textContent = newer
      ? `Nouveau pilote NVIDIA ${drv.latest}`
      : `Pilote NVIDIA à jour (${drv.installed})`;
    dv.title = drv.gpu + (newer ? ` · installé : ${drv.installed} · clic : page des pilotes` : "");
    dv.onclick = newer ? () => invoke('open_url', { url: 'https://www.nvidia.com/fr-fr/drivers/' }) : null;
  }
  const cl = $('.hl-clean');
  const checked = new Set($$('.hl-clean input:checked').map(i => i.value));
  const first = !cl.children.length;
  cl.innerHTML = '';
  h.clean.forEach(c => {
    const l = document.createElement('label');
    l.innerHTML = `<input type="checkbox" value="${c.id}"><span></span><small>${fmtSize(c.bytes)}</small>`;
    l.querySelector('span').textContent = c.label;
    const box = l.querySelector('input');
    // la corbeille n'est jamais cochée d'office
    box.checked = c.bytes > 0 && (first ? c.id !== 'recycle' : checked.has(c.id));
    box.disabled = !c.bytes;
    box.addEventListener('change', updateCleanBtn);
    cl.append(l);
  });
  updateCleanBtn();
}
const verGt = (a, b) => {
  const x = a.split('.').map(Number), y = b.split('.').map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0);
  return false;
};
function updateCleanBtn() {
  $('.hl-go').disabled = !$$('.hl-clean input:checked').length;
}
$('.hl-go').addEventListener('click', async () => {
  const ids = $$('.hl-clean input:checked').map(i => i.value);
  const btn = $('.hl-go');
  btn.disabled = true;
  btn.querySelector('span:last-child').textContent = 'Nettoyage…';
  const freed = await invoke('health_clean', { ids }).catch(() => 0);
  btn.querySelector('span:last-child').textContent = 'Nettoyer';
  showOsd('cleaning_services', null, `${fmtSize(freed)} libérés`);
  refreshHealth(true);
});
listen('disk-low', ({ payload: d }) => pushNotif({
  app: 'Santé du PC', sym: 'hard_drive', title: `Disque ${d.mount} presque plein`,
  body: `Plus que ${fmtSize(d.free)} libres sur ${fmtSize(d.total)}`, action: 'Voir', tab: 'pc', ms: 12000,
}));

// --- mode absent : 10 min sans clavier ni souris (hors jeu) ; la musique se
// met en pause, les notifications attendent le retour
const AWAY_SECS = 10 * 60;
const VIDEO_APPS = /chrome|msedge|firefox|opera|brave|vlc|mpc|potplayer|netflix|disney|prime|twitch|youtube/i;
setInterval(async () => {
  if (theme.away === 'off') return;
  const idle = await invoke('idle_secs').catch(() => 0);
  if (!away.on && idle >= AWAY_SECS && !gameOn && !island.classList.contains('hidden')) {
    away.on = true;
    away.since = Date.now() - idle * 1000;
    away.missed = [];
    away.paused = false;
    island.classList.add('away');
    // une vidéo se regarde sans toucher la souris : on ne coupe que la musique
    if (theme.away === 'on' && hasMedia && media.playing && !VIDEO_APPS.test(media.app)) {
      invoke('media_action', { action: 'toggle' });
      away.paused = true;
    }
  } else if (away.on && idle < 5) {
    away.on = false;
    island.classList.remove('away');
    const secs = (Date.now() - away.since) / 1000;
    const missed = away.missed.splice(0);
    if (!missed.length && !away.paused) return;
    const byApp = {};
    missed.forEach(n => { byApp[n.app] = (byApp[n.app] || 0) + 1; });
    const parts = Object.entries(byApp).map(([a, c]) => c > 1 ? `${a} ×${c}` : a);
    pushNotif({
      app: 'Pendant ton absence', sym: 'waving_hand', recap: true, ms: 10000,
      title: `Re ! Absent ${fmtDur(secs)}`,
      body: (missed.length ? `${missed.length} notification${missed.length > 1 ? 's' : ''} : ${parts.join(', ')}` : 'Aucune notification')
        + (away.paused ? ' · musique en pause' : ''),
      ...(away.paused ? { action: 'Reprendre', cmd: ['media_action', { action: 'toggle' }] } : {}),
    });
    // puis les notifications elles-mêmes (les 4 dernières)
    missed.slice(-4).forEach(n => pushNotif({ ...n, recap: true }));
  }
}, 5000);

// --- état des services (src/status.rs) : page officielle + test depuis le PC
const SV_FR = { minor: 'perturbations', major: 'panne partielle', critical: 'panne majeure', maintenance: 'maintenance' };
let svPrev = {};
function svLevel(x) {
  if (x.ms == null) return 'down';
  if (x.official === 'major' || x.official === 'critical') return 'down';
  if (x.official === 'minor' || x.official === 'maintenance' || x.ms > 2500) return 'warn';
  return 'ok';
}
function renderServices(list) {
  const box = $('.sv-list');
  box.innerHTML = '';
  list.forEach(x => {
    const lv = svLevel(x);
    const b = document.createElement('button');
    b.className = 'sv ' + lv;
    b.innerHTML = '<i></i><span></span><small></small>';
    b.querySelector('span').textContent = x.name;
    b.querySelector('small').textContent = x.ms == null ? 'HS' : x.ms + ' ms';
    b.title = [
      x.official ? `Officiel : ${x.official === 'none' ? 'tout fonctionne' : SV_FR[x.official] || x.official}${x.desc ? ` (${x.desc})` : ''}` : 'Pas de page d’état officielle',
      x.ms == null ? 'Injoignable depuis ce PC' : `Répond en ${x.ms} ms depuis ce PC`,
      'Clic : page d’état',
    ].join('\n');
    b.addEventListener('click', () => invoke('open_url', { url: x.page }));
    box.append(b);
  });
  // tout injoignable = c'est la connexion ; un seul HS alors que l'officiel dit OK = souci local
  const down = list.filter(x => x.ms == null);
  const note = $('.sv-note');
  note.className = 'sv-note';
  if (list.length && down.length === list.length) {
    note.textContent = 'Aucun service ne répond : ta connexion Internet semble coupée.';
    note.classList.add('bad');
  } else if (down.some(x => x.official === 'none')) {
    note.textContent = `${down.filter(x => x.official === 'none').map(x => x.name).join(', ')} : tout va bien chez eux, le blocage vient sûrement de ta connexion (essaie WARP).`;
    note.classList.add('bad');
  } else note.textContent = '';
  // notification quand un service tombe (pas au premier relevé)
  const first = !Object.keys(svPrev).length;
  list.forEach(x => {
    const lv = svLevel(x);
    if (!first && lv === 'down' && svPrev[x.id] !== 'down') {
      pushNotif({ app: 'État des services', sym: 'cloud_off', title: `${x.name} en panne`,
        body: x.ms == null ? 'Injoignable depuis ton PC' : SV_FR[x.official] || x.desc, tab: 'pc', ms: 9000 });
    }
    if (!first && lv === 'ok' && svPrev[x.id] === 'down') {
      pushNotif({ app: 'État des services', sym: 'cloud_done', title: `${x.name} est de retour`, body: 'Le service répond de nouveau', ms: 6000 });
    }
    svPrev[x.id] = lv;
  });
}
listen('services', ({ payload }) => renderServices(payload));
let svAt = 0;
function refreshServices() {
  if (Date.now() - svAt < 60 * 1000) return;
  svAt = Date.now();
  invoke('services_get').then(renderServices).catch(() => {});
}
$('#sv-refresh').addEventListener('click', async () => {
  const b = $('#sv-refresh');
  b.classList.add('spin');
  await invoke('services_get', { fresh: true }).then(renderServices).catch(() => {});
  b.classList.remove('spin');
});

let pcTimer = null;
function refreshPc() {
  refreshServices();
  refreshHealth();
  renderHardware();
  if (!document.activeElement?.closest?.('.out-list')) refreshOutputs();
  refreshPower();
  refreshMixer();
  invoke('app_volume_get', { app: 'discord' }).then(v => { showDcVolume(v); renderDiscord(); });
}

// ========================================================= presse-papiers
function renderClips(list) {
  clipCount = list.length ? `${list.length} élément${list.length > 1 ? 's' : ''}` : 'Historique vide';
  if (clipView === 'hist') $('.clip-count').textContent = clipCount;
  const box = $('.clip-list');
  box.innerHTML = list.length ? '' : '<div class="empty">Copiez du texte : il apparaîtra ici.</div>';
  list.forEach(t => {
    const el = document.createElement('button');
    el.className = 'clip';
    const p = document.createElement('p');
    p.textContent = t.length > 600 ? t.slice(0, 600) + '…' : t;
    el.append(p);
    el.insertAdjacentHTML('beforeend', '<span class="ms to-note" title="Ajouter au bloc-notes">note_add</span><span class="ms ok">check</span>');
    el.querySelector('.to-note').addEventListener('click', e => {
      e.stopPropagation();
      addToNotes(t);
      el.classList.add('done');
      setTimeout(() => el.classList.remove('done'), 1200);
    });
    el.addEventListener('click', () => {
      invoke('clip_copy', { text: t });
      el.classList.add('done');
      setTimeout(() => el.classList.remove('done'), 1200);
    });
    box.append(el);
  });
}
listen('clips', ({ payload }) => renderClips(payload));
invoke('clips_get').then(renderClips);
$('#clip-clear').addEventListener('click', () => invoke('clips_clear'));

// ============================================================== bloc-notes
// dans l'onglet presse-papiers ; enregistré dans %LOCALAPPDATA%\Ilot\notes.json
const notes = $('.notes');
let clipView = 'hist';
let clipCount = '';
let noteTimer = null;
function showClipView(v) {
  clipView = v;
  $$('.clip-seg button').forEach(b => b.classList.toggle('on', b.dataset.v === v));
  $('.clip-list').hidden = v !== 'hist';
  notes.hidden = v !== 'notes';
  $('#clip-clear').hidden = v !== 'hist';
  $('#note-copy').hidden = v !== 'notes';
  noteStatus();
  if (v === 'notes') notes.focus();
}
function noteStatus(msg) {
  if (clipView !== 'notes') { $('.clip-count').textContent = clipCount; return; }
  const n = notes.value.length;
  $('.clip-count').textContent = msg || (n ? `${n} caractère${n > 1 ? 's' : ''}` : 'Bloc-notes vide');
}
function saveNotes() {
  clearTimeout(noteTimer);
  noteTimer = setTimeout(async () => {
    const ok = await invoke('store_set', { key: 'notes', value: { text: notes.value } });
    noteStatus(ok ? 'Enregistré' : 'Erreur d’enregistrement');
    setTimeout(() => noteStatus(), 1500);
  }, 400);
}
function addToNotes(t) {
  const v = notes.value.replace(/\s+$/, '');
  notes.value = (v ? v + '\n\n' : '') + t;
  saveNotes();
}
notes.addEventListener('input', () => { noteStatus(); saveNotes(); });
// on écrit : l'îlot reste ouvert même si la souris sort
notes.addEventListener('focus', () => { pinned = true; });
$$('.clip-seg button').forEach(b => b.addEventListener('click', () => showClipView(b.dataset.v)));
$('#note-copy').addEventListener('click', () => {
  invoke('clip_copy', { text: notes.value });
  noteStatus('Copié');
  setTimeout(() => noteStatus(), 1200);
});
invoke('store_get', { key: 'notes' }).then(n => { if (n && typeof n.text === 'string') notes.value = n.text; noteStatus(); });

// ============================================================ soundboard
// moteur côté Rust (src/soundboard.rs) : vrai micro + sons -> micro virtuel ;
// sons décodés ici (mp3, wav, ogg...) en PCM 48 kHz stéréo ; liste dans sounds.json
const SB_RATE = 48000;
const SB_MAX_S = 30; // durée maxi d'un son
let sb = { list: [], cfg: { on: false, cable: '', mic: '', monitor: true, mic_gain: 1, exclusive: true } };
let sbDevs = { outputs: [], inputs: [] };
let sbPlaying = new Set();
const sbSave = () => invoke('store_set', { key: 'sounds', value: sb });
const sbCfgSend = () => invoke('sb_config', { cfg: { on: sb.cfg.on, cable: sb.cfg.cable, mic: sb.cfg.mic, monitor: sb.cfg.monitor, mic_gain: sb.cfg.mic_gain } });
// micro du câble : même nom entre parenthèses que la sortie
// (« Haut-parleurs (Steam Streaming Microphone) » -> « Microphone (Steam Streaming Microphone) »)
const inner = n => (n.match(/\(([^()]*(?:\([^()]*\)[^()]*)*)\)\s*$/) || [, n])[1];
const cableInput = out => out && sbDevs.inputs.find(i => inner(i.name) === inner(out.name));
const CABLE_RE = [/CABLE Input/i, /Steam Streaming Microphone/i, /Voicemod/i, /virtual|virtuel/i];
function sbPickCable() {
  for (const re of CABLE_RE) {
    const o = sbDevs.outputs.find(d => re.test(d.name) && cableInput(d));
    if (o) return o.id;
  }
  return '';
}

async function sbDecode(buf) {
  const ac = new OfflineAudioContext(2, 1, SB_RATE);
  const audio = await ac.decodeAudioData(buf); // rééchantillonné à 48 kHz
  const len = Math.min(audio.length, SB_RATE * SB_MAX_S);
  const L = audio.getChannelData(0), R = audio.numberOfChannels > 1 ? audio.getChannelData(1) : L;
  let peak = 0;
  for (let i = 0; i < len; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  // niveaux homogènes : crête ramenée à -1 dB
  const k = peak > 0.001 ? 0.89 / peak : 1;
  const out = new Float32Array(len * 2);
  for (let i = 0; i < len; i++) { out[i * 2] = L[i] * k; out[i * 2 + 1] = R[i] * k; }
  return { pcm: out, dur: len / SB_RATE };
}
const SB_COLORS = ['primary', 'secondary', 'tertiary'];
async function sbImport(name, buf) {
  try {
    const { pcm, dur } = await sbDecode(buf);
    const id = 's' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    await invoke('sb_save', new Uint8Array(pcm.buffer), { headers: { id } });
    sb.list.push({ id, name: name.replace(/\.[^.]+$/, '').slice(0, 40), dur, vol: 1, color: SB_COLORS[sb.list.length % 3] });
    sbSave();
    renderSounds();
  } catch (e) {
    $('.sb-hint').textContent = `⚠ ${name} : format non reconnu`;
  }
}
$('#sb-add').addEventListener('click', () => $('#sb-file').click());
$('#sb-file').addEventListener('change', async e => {
  for (const f of e.target.files) await sbImport(f.name, await f.arrayBuffer());
  e.target.value = '';
});
// fichiers déposés sur l'onglet (voir tauri://drag-drop)
async function sbImportPaths(paths) {
  for (const p of paths.filter(p => /\.(mp3|wav|ogg|m4a|flac|opus|aac|webm)$/i.test(p))) {
    try { await sbImport(baseName(p), await invoke('sb_read', { path: p })); }
    catch (e) { $('.sb-hint').textContent = '⚠ ' + e; }
  }
}

function sbPlay(s) {
  if (sbPlaying.has(s.id)) return invoke('sb_stop', { id: s.id });
  invoke('sb_play', { id: s.id, volume: s.vol ?? 1, exclusive: sb.cfg.exclusive });
}
function renderSounds() {
  const grid = $('.sb-grid');
  grid.innerHTML = '';
  if (!sb.list.length) {
    grid.innerHTML = '<div class="empty">Aucun son. « Ajouter » ou dépose des fichiers audio ici (mp3, wav, ogg…).</div>';
    return;
  }
  sb.list.forEach(s => {
    const b = document.createElement('button');
    b.className = `sb-pad c-${s.color || 'primary'}` + (sbPlaying.has(s.id) ? ' playing' : '');
    b.dataset.id = s.id;
    b.style.setProperty('--dur', (s.dur || 1) + 's');
    b.innerHTML = '<span class="ms">graphic_eq</span><b></b><small></small><i class="sb-prog"></i>';
    b.querySelector('b').textContent = s.name;
    b.querySelector('small').textContent = `${(s.dur || 0).toFixed(1).replace('.', ',')} s` + ((s.vol ?? 1) !== 1 ? ` · ${Math.round(s.vol * 100)} %` : '');
    b.addEventListener('click', () => sbPlay(s));
    b.addEventListener('contextmenu', e => { e.preventDefault(); soundMenu(s, e); });
    grid.append(b);
  });
}
function soundMenu(s, e) {
  showCtx(e, box => {
    ctxTitle(box, s.name);
    ctxItem(box, 'edit', 'Renommer', () => askName(e, 'Nom du son', s.name, name => { s.name = name; sbSave(); renderSounds(); }));
    [0.5, 0.75, 1, 1.5].forEach(v => ctxItem(box, (s.vol ?? 1) === v ? 'check' : 'volume_up', `Volume ${v * 100} %`, () => { hideCtx(); s.vol = v; sbSave(); renderSounds(); }));
    ctxItem(box, 'palette', 'Changer de couleur', () => { hideCtx(); s.color = SB_COLORS[(SB_COLORS.indexOf(s.color) + 1) % 3]; sbSave(); renderSounds(); });
    box.insertAdjacentHTML('beforeend', '<hr class="ctx-sep">');
    ctxItem(box, 'delete', 'Supprimer', ev => {
      const b = ev.currentTarget;
      if (!b.classList.contains('armed')) { b.classList.add('armed'); b.lastChild.textContent = 'Confirmer'; return; }
      hideCtx();
      sb.list = sb.list.filter(x => x !== s);
      invoke('sb_delete', { id: s.id });
      sbSave();
      renderSounds();
    }, 'danger');
  });
}
listen('sb-playing', ({ payload }) => {
  sbPlaying = new Set(payload);
  $$('.sb-pad').forEach(b => b.classList.toggle('playing', sbPlaying.has(b.dataset.id)));
});
$('#sb-stop').addEventListener('click', () => invoke('sb_stop', {}));

// --- activation et réglages
function renderSbState() {
  const on = sb.cfg.on && !!sb.cfg.cable;
  const btn = $('#sb-on');
  btn.classList.toggle('on', on);
  btn.querySelector('.ms').textContent = on ? 'mic' : 'mic_off';
  btn.lastChild.textContent = on ? 'Active dans Discord' : 'Désactivée';
  const out = sbDevs.outputs.find(d => d.id === sb.cfg.cable);
  const inp = cableInput(out);
  $('.sb-in-name').textContent = inp ? `« ${inp.name} »` : 'le micro du câble virtuel';
  $('.sb-hint').textContent = !sb.cfg.cable ? 'Aucun micro virtuel trouvé : choisis-le dans les réglages'
    : on ? `Dans Discord, micro : ${inp ? inp.name : '(câble virtuel)'}`
      : 'Désactivée : les sons ne sont joués que pour toi';
}
function renderSbPanel() {
  const opt = (d, sel) => `<option value="${d.id}"${d.id === sel ? ' selected' : ''}></option>`;
  const cable = $('#sb-cable');
  cable.innerHTML = '<option value="">— Aucun —</option>' + sbDevs.outputs.map(d => opt(d, sb.cfg.cable)).join('');
  [...cable.options].slice(1).forEach((o, i) => (o.textContent = sbDevs.outputs[i].name));
  // le micro du câble ne peut pas être « ton vrai micro » (larsen)
  const cin = cableInput(sbDevs.outputs.find(d => d.id === sb.cfg.cable));
  const mics = sbDevs.inputs.filter(d => d !== cin);
  const mic = $('#sb-mic');
  mic.innerHTML = '<option value="">Micro par défaut de Windows</option>' + mics.map(d => opt(d, sb.cfg.mic)).join('');
  [...mic.options].slice(1).forEach((o, i) => (o.textContent = mics[i].name));
  const g = Math.round((sb.cfg.mic_gain ?? 1) * 100);
  $('#sb-gain').value = g;
  $('#sb-gain').style.setProperty('--p', g / 2 + '%');
  $('.sb-gain-val').textContent = g + ' %';
  const chips = (key, opts) => {
    const box = $(`[data-sb="${key}"]`);
    box.innerHTML = '';
    opts.forEach(([v, label]) => {
      const b = document.createElement('button');
      b.className = 'fchip' + (sb.cfg[key] === v ? ' on' : '');
      b.textContent = label;
      b.addEventListener('click', () => { sb.cfg[key] = v; sbSave(); sbCfgSend(); renderSbPanel(); });
      box.append(b);
    });
  };
  chips('monitor', [[true, 'Oui'], [false, 'Non']]);
  chips('exclusive', [[true, 'Un à la fois'], [false, 'Superposer']]);
  renderSbState();
}
$('#sb-cable').addEventListener('change', e => { sb.cfg.cable = e.target.value; sbSave(); sbCfgSend(); renderSbPanel(); });
$('#sb-mic').addEventListener('change', e => { sb.cfg.mic = e.target.value; sbSave(); sbCfgSend(); });
$('#sb-gain').addEventListener('input', e => {
  sb.cfg.mic_gain = e.target.value / 100;
  e.target.style.setProperty('--p', e.target.value / 2 + '%');
  $('.sb-gain-val').textContent = e.target.value + ' %';
});
$('#sb-gain').addEventListener('change', () => { sbSave(); sbCfgSend(); });
$('#sb-setup').addEventListener('click', async () => { await refreshSbDevices(); renderSbPanel(); togglePanel('#sb-panel'); });
$('#sb-on').addEventListener('click', async () => {
  if (!sb.cfg.cable) { await refreshSbDevices(); renderSbPanel(); togglePanel('#sb-panel'); return; }
  sb.cfg.on = !sb.cfg.on;
  sbSave();
  sbCfgSend();
  renderSbState();
});
async function refreshSbDevices() {
  sbDevs = await invoke('sb_devices').catch(() => ({ outputs: [], inputs: [] }));
  // premier lancement : câble trouvé tout seul, micro réel = micro par défaut
  if (!sb.cfg.cable || !sbDevs.outputs.some(d => d.id === sb.cfg.cable)) {
    const c = sbPickCable();
    if (c !== sb.cfg.cable) { sb.cfg.cable = c; sbSave(); sbCfgSend(); }
  }
}
invoke('store_get', { key: 'sounds' }).then(async v => {
  if (v && typeof v === 'object') sb = { list: v.list || [], cfg: { ...sb.cfg, ...(v.cfg || {}) } };
  await refreshSbDevices();
  renderSounds();
  renderSbState();
  sbCfgSend(); // soundboard active au démarrage si elle l'était
});

// ============================================================ traduction
// src/translate.rs ; langues choisies gardées dans translate.json
const LANGS = [
  ['auto', 'Détecter la langue'], ['fr', 'Français'], ['en', 'Anglais'], ['es', 'Espagnol'], ['de', 'Allemand'],
  ['it', 'Italien'], ['pt', 'Portugais'], ['nl', 'Néerlandais'], ['pl', 'Polonais'], ['ru', 'Russe'], ['uk', 'Ukrainien'],
  ['tr', 'Turc'], ['ar', 'Arabe'], ['hi', 'Hindi'], ['ja', 'Japonais'], ['ko', 'Coréen'], ['zh-CN', 'Chinois'],
];
const langName = c => (LANGS.find(([k]) => k === c || k.split('-')[0] === c) || [, c])[1];
const trFrom = $('#tr-from'), trTo = $('#tr-to'), trIn = $('.tr-in'), trOut = $('.tr-out');
trFrom.innerHTML = LANGS.map(([k, l]) => `<option value="${k}">${l}</option>`).join('');
trTo.innerHTML = LANGS.slice(1).map(([k, l]) => `<option value="${k}">${l}</option>`).join('');
trFrom.value = 'auto';
trTo.value = 'fr';
invoke('store_get', { key: 'translate' }).then(t => {
  if (t && t.from) trFrom.value = t.from;
  if (t && t.to) trTo.value = t.to;
});
const saveLangs = () => invoke('store_set', { key: 'translate', value: { from: trFrom.value, to: trTo.value } });
let trSeq = 0;
let trTimer = null;
let trDetected = ''; // dernière langue détectée (« Détecter la langue »)
async function runTranslate() {
  const text = trIn.value;
  $('.tr-count').textContent = `${text.length} / 4500`;
  const seq = ++trSeq;
  if (!text.trim()) { trOut.textContent = ''; $('.tr-det').textContent = ''; return; }
  $('.tr-res').classList.add('busy');
  try {
    let r = await invoke('translate', { text, from: trFrom.value, to: trTo.value });
    // texte déjà dans la langue visée (« Détecter ») : on traduit vers l'anglais
    let to = trTo.value;
    if (trFrom.value === 'auto' && r.detected && r.detected.split('-')[0] === to.split('-')[0]) {
      to = to === 'en' ? 'fr' : 'en';
      r = await invoke('translate', { text, from: 'auto', to });
    }
    if (seq !== trSeq) return; // une saisie plus récente a pris le relais
    trDetected = r.detected || '';
    trOut.textContent = r.text;
    $('.tr-det').textContent = (trFrom.value === 'auto' && r.detected ? `Détecté : ${langName(r.detected)} · ` : '') + `vers ${langName(to)}`;
  } catch (e) {
    if (seq === trSeq) { trOut.textContent = ''; $('.tr-det').textContent = '⚠ ' + e; }
  } finally {
    if (seq === trSeq) $('.tr-res').classList.remove('busy');
  }
}
trIn.addEventListener('input', () => { clearTimeout(trTimer); trTimer = setTimeout(runTranslate, 450); });
trIn.addEventListener('keydown', e => { if (e.key !== 'Escape') e.stopPropagation(); });
[trFrom, trTo].forEach(s => s.addEventListener('change', () => { saveLangs(); runTranslate(); }));
$('#tr-swap').addEventListener('click', () => {
  // « Détecter » n'a pas de sens comme langue d'arrivée : on prend la langue détectée
  const known = c => LANGS.slice(1).some(([k]) => k === c);
  const from = trFrom.value !== 'auto' ? trFrom.value : known(trDetected) ? trDetected : (trTo.value === 'fr' ? 'en' : 'fr');
  trFrom.value = trTo.value;
  trTo.value = from;
  if (trOut.textContent) trIn.value = trOut.textContent;
  saveLangs();
  runTranslate();
});
$('#tr-paste').addEventListener('click', async () => {
  const [last] = await invoke('clips_get');
  if (!last) return;
  trIn.value = last.slice(0, 4500);
  runTranslate();
  trIn.focus();
});
$('#tr-clear').addEventListener('click', () => { trIn.value = ''; runTranslate(); trIn.focus(); });
$('#tr-copy').addEventListener('click', async () => {
  if (!trOut.textContent) return;
  await invoke('clip_copy', { text: trOut.textContent });
  const b = $('#tr-copy .ms');
  b.textContent = 'check';
  setTimeout(() => (b.textContent = 'content_copy'), 1200);
});

// ========================================================= fonds d'écran
// deux sources : les fonds Windows et ceux de Wallpaper Engine (si installé)
let wallSrc = 'win';
let wallsLoaded = false;
let we = { installed: false, running: false, current: '' };
let currentThumb = '';
const wallCache = {};
const KIND = { scene: 'Scène', video: 'Vidéo', web: 'Web', application: 'Appli' };
const samePath = (a, b) => !!a && !!b && a.replace(/\//g, '\\').toLowerCase() === b.replace(/\//g, '\\').toLowerCase();

function wallNote() {
  $('.wall-note').textContent = wallSrc === 'win' && we.running
    ? 'Masqué par Wallpaper Engine'
    : we.installed ? '' : "Les couleurs suivent le fond d'écran";
  $('#wall-folder').hidden = wallSrc !== 'win';
}

async function loadWalls(force) {
  wallsLoaded = true;
  wallNote();
  const src = wallSrc;
  const grid = $('.wall-grid');
  if (force || !wallCache[src]) {
    grid.innerHTML = '<div class="empty">Chargement…</div>';
    wallCache[src] = await invoke(src === 'we' ? 'we_walls' : 'walls_get');
    if (src !== wallSrc) return; // l'utilisateur a changé d'onglet entre-temps
  }
  renderWalls();
}

function renderWalls() {
  const list = wallCache[wallSrc] || [];
  const grid = $('.wall-grid');
  grid.innerHTML = list.length ? '' : wallSrc === 'we'
    ? '<div class="empty">Aucun fond Wallpaper Engine trouvé.</div>'
    : '<div class="empty">Ajoutez des images dans Images\\Wallpapers.</div>';
  list.forEach(w => {
    const el = document.createElement('button');
    const cur = wallSrc === 'we' ? samePath(w.path, we.current) : w.cur;
    el.className = 'wall' + (cur ? ' cur' : '');
    el.dataset.path = w.path;
    el.innerHTML = `<img src="${w.thumb}" alt="" loading="lazy"><span class="ms">check</span><i class="spin"></i>`;
    if (w.title) {
      const cap = document.createElement('span');
      cap.className = 'cap';
      const b = document.createElement('b');
      b.textContent = w.title;
      cap.append(b);
      if (KIND[w.kind]) cap.insertAdjacentHTML('beforeend', `<i>${KIND[w.kind]}</i>`);
      el.append(cap);
      el.title = w.title;
    } else {
      el.title = w.path.split('\\').pop();
    }
    el.addEventListener('click', () => pickWall(w, el));
    grid.append(el);
  });
}

async function pickWall(w, el) {
  if (el.classList.contains('cur') || $('.wall.applying')) return;
  el.classList.add('applying');
  const isWe = wallSrc === 'we';
  // la palette ne suit que le fond réellement visible
  if (isWe || !we.running) themeFrom(w.thumb);
  const ok = await invoke(isWe ? 'we_set' : 'wall_set', { path: w.path });
  // WE met un instant à charger le fond : on garde l'indicateur un peu
  if (isWe) await new Promise(r => setTimeout(r, 700));
  el.classList.remove('applying');
  if (!ok) { if (currentThumb) themeFrom(currentThumb); return; }
  if (isWe) { we.current = w.path; we.running = true; }
  else (wallCache.win || []).forEach(x => (x.cur = x === w));
  if (isWe || !we.running) { currentThumb = w.thumb; applyIslandBg(); }
  $$('.wall').forEach(x => x.classList.toggle('cur', x === el));
  wallNote();
}

$$('.wall-seg button').forEach(b => b.addEventListener('click', () => {
  if (b.dataset.src === wallSrc) return;
  wallSrc = b.dataset.src;
  $$('.wall-seg button').forEach(x => x.classList.toggle('on', x === b));
  loadWalls();
}));
$('#wall-refresh').addEventListener('click', () => loadWalls(true));
$('#wall-folder').addEventListener('click', () => { invoke('walls_open_folder'); setState('collapsed'); });

// fond actif (WE s'il tourne, sinon Windows) -> palette
async function syncWall() {
  we = await invoke('we_state');
  $('.wall-seg').hidden = !we.installed;
  const w = await invoke('wall_current');
  if (w && w.thumb !== currentThumb) {
    currentThumb = w.thumb;
    themeFrom(w.thumb);
    applyIslandBg();
  }
  if (wallsLoaded) { wallNote(); if (wallCache[wallSrc]) renderWalls(); }
}
// changement fait dans Wallpaper Engine, ou WE lancé / quitté
listen('wall-changed', syncWall);
(async () => {
  await syncWall();
  if (we.installed && we.running) {
    wallSrc = 'we';
    $$('.wall-seg button').forEach(x => x.classList.toggle('on', x.dataset.src === 'we'));
    if (wallsLoaded) loadWalls();
  }
})();

// ======================================================== Material You
const ROLES = {
  primary: 'primary', 'on-primary': 'onPrimary',
  'primary-container': 'primaryContainer', 'on-primary-container': 'onPrimaryContainer',
  secondary: 'secondary', 'secondary-container': 'secondaryContainer', 'on-secondary-container': 'onSecondaryContainer',
  tertiary: 'tertiary', 'tertiary-container': 'tertiaryContainer', 'on-tertiary-container': 'onTertiaryContainer',
  surface: 'surface', 'surface-c-low': 'surfaceContainerLow', 'surface-c': 'surfaceContainer',
  'surface-c-high': 'surfaceContainerHigh', 'surface-c-highest': 'surfaceContainerHighest',
  'on-surface': 'onSurface', 'on-surface-variant': 'onSurfaceVariant',
  outline: 'outline', 'outline-variant': 'outlineVariant', error: 'error', 'on-error': 'onError',
};
function applyPalette(p) {
  for (const [k, v] of Object.entries(p)) document.documentElement.style.setProperty('--' + k, v);
}
// couleur source : celle du fond d'écran (src), ou celle choisie dans Apparence
async function themeFrom(src) {
  try {
    let argb;
    // « Pochette » : couleur du morceau en cours, sinon celle du fond d'écran
    if (theme.color === 'art' && currentArt) src = currentArt;
    if (theme.color !== 'auto' && theme.color !== 'art') argb = argbFromHex(theme.color);
    else {
      if (!src) return;
      const img = new Image();
      img.src = src;
      await img.decode();
      argb = await sourceColorFromImage(img);
    }
    const Scheme = (SCHEMES[theme.scheme] || SCHEMES.tonal)[1];
    const dark = isDark();
    const scheme = new Scheme(Hct.fromInt(argb), dark, 0);
    appliedDark = dark;
    const p = {};
    for (const [css, role] of Object.entries(ROLES)) p[css] = hexFromArgb(MDC[role].getArgb(scheme));
    applyPalette(p);
    try { localStorage.setItem('palette', JSON.stringify(p)); } catch {}
  } catch (e) {
    console.warn('thème', e);
  }
}

// ============================================================== démarrage
try {
  const saved = JSON.parse(localStorage.getItem('palette') || 'null');
  if (saved) applyPalette(saved);
} catch {}
tickClock();
renderCal();
showTab('home');
reportHit();
invoke('startup_tab').then(t => { if (t) { pinned = true; open(t); } });
