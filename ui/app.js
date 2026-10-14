import {
  Hct, SchemeTonalSpot, MaterialDynamicColors as MDC, sourceColorFromImage, hexFromArgb,
} from './vendor/mcu.js';

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const island = $('#island');

// ======================================================= état de l'îlot
// collapsed -> (survol) peek -> (clic / molette) open
const SIZE = {
  collapsed: m => ({ w: m ? 200 : 132, h: 30 }),
  peek: m => (m ? { w: 420, h: 66 } : { w: 250, h: 50 }),
  open: () => ({ w: 740, h: 484 }),
};
const EAR = 22;
let state = 'collapsed';
let hovered = false;
let pinned = false; // ouvert au clavier : ne se referme pas en sortant la souris
let leaveTimer = null;
let hasMedia = false;

function reportHit() {
  const { w, h } = SIZE[state](hasMedia);
  const x = (innerWidth - w) / 2 - EAR;
  // un peu de marge sous l'îlot replié pour l'attraper facilement
  invoke('set_hit', { x, y: 0, w: w + EAR * 2, h: h + (state === 'collapsed' ? 6 : 2) });
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
  } else if (state === 'open' && !pinned) {
    leaveTimer = setTimeout(() => setState('collapsed'), 450);
  }
});
listen('fullscreen', ({ payload }) => {
  island.classList.toggle('hidden', payload);
  if (payload) setState('collapsed');
});
listen('blur', () => {
  if (state === 'open' && !hovered) setState('collapsed');
});
listen('launcher', () => {
  if (state === 'open' && currentTab === 'apps') return setState('collapsed');
  pinned = true;
  open('apps');
  setTimeout(() => $('#q').focus(), 60);
});

$('#pill').addEventListener('click', e => {
  if (e.target.closest('[data-media]')) return;
  open(hasMedia && currentTab === 'home' ? 'home' : null);
});
island.addEventListener('wheel', e => {
  if (state !== 'open' && e.deltaY > 0) open();
  else if (state === 'open' && e.deltaY < 0 && e.target.closest('#tabs')) close();
}, { passive: true });
addEventListener('keydown', e => {
  if (e.key === 'Escape' && state === 'open') close();
});
addEventListener('resize', reportHit);

// ================================================================ onglets
let currentTab = 'home';
const TABS = $$('#tabs button').map(b => b.dataset.tab);

function showTab(tab) {
  const dir = TABS.indexOf(tab) > TABS.indexOf(currentTab) ? 1 : -1;
  currentTab = tab;
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

function onOpen() {
  moveIndicator();
  refreshVolume();
  onTab(currentTab);
}
function onTab(tab) {
  if (tab === 'walls' && !wallsLoaded) loadWalls();
  if (tab === 'apps') renderApps();
}

// ================================================================ horloge
const fmtDate = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
const fmtShort = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
function tickClock() {
  const d = new Date();
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  $('.mini-clock').textContent = $('.peek-clock').textContent = `${hh}:${mm}`;
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
    grid.insertAdjacentHTML('beforeend',
      `<span class="d${out ? ' out' : ''}${today ? ' today' : ''}${we ? ' we' : ''}">${day.getDate()}</span>`);
    day.setDate(day.getDate() + 1);
  }
}
$$('[data-cal]').forEach(b => b.addEventListener('click', () => {
  calOffset += Number(b.dataset.cal);
  renderCal();
}));

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

function applyArt(src) {
  $$('.mini-art, .peek-art, .disc-art, .mp-art img').forEach(i => {
    if (src) i.src = src; else i.removeAttribute('src');
  });
  $('.mp-bg').style.backgroundImage = src ? `url("${src}")` : 'none';
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
const vol = $('#vol');
let volBusy = false;
function showVolume(level, muted) {
  const v = Math.round(level * 100);
  vol.value = v;
  vol.style.setProperty('--p', (muted ? 0 : v) + '%');
  $('.vol-val').textContent = muted ? '–' : v;
  $('.vol-icon').textContent = muted || v === 0 ? 'volume_off' : v < 50 ? 'volume_down' : 'volume_up';
  vol.dataset.muted = muted;
}
function refreshVolume() {
  invoke('volume_get').then(v => showVolume(v.level, v.muted));
}
vol.addEventListener('input', () => {
  showVolume(vol.value / 100, false);
  if (volBusy) return;
  volBusy = true;
  invoke('volume_set', { level: vol.value / 100, muted: false }).finally(() => (volBusy = false));
});
vol.addEventListener('change', () => invoke('volume_set', { level: vol.value / 100, muted: false }));
vol.addEventListener('wheel', e => {
  e.stopPropagation();
  const v = Math.max(0, Math.min(100, Number(vol.value) - Math.sign(e.deltaY) * 5));
  showVolume(v / 100, false);
  invoke('volume_set', { level: v / 100, muted: false });
}, { passive: true });
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
listen('sys', ({ payload: r }) => {
  gauge('cpu', r.cpu / 100, Math.round(r.cpu) + ' %');
  gauge('mem', r.mem_used / r.mem_total, `${gb(r.mem_used)} / ${gb(r.mem_total)} Go`);
  if (r.disk_total) gauge('disk', r.disk_used / r.disk_total, `${gb(r.disk_used)} / ${gb(r.disk_total)} Go`);
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
  const pool = inGames ? games : folder ? apps.filter(a => folder.apps.includes(a.id)) : apps;
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
      ? '<div class="empty">Dossier vide : clic droit sur une application pour l\'ajouter ici.</div>'
      : '<div class="empty">Aucune application</div>';
    return;
  }
  grid.innerHTML = '';
  appView.forEach((a, i) => {
    const el = document.createElement('button');
    el.className = 'app' + (q && i === appSel ? ' sel' : '');
    el.title = a.name;
    el.innerHTML = a.icon ? `<img src="${a.icon}" alt="">` : `<div class="ph">${a.name[0] || '?'}</div>`;
    const label = document.createElement('span');
    label.textContent = a.name;
    el.append(label);
    el.addEventListener('click', () => launch(a));
    el.addEventListener('contextmenu', e => { e.preventDefault(); appMenu(a, e); });
    grid.append(el);
  });
}

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
    el.title = g.name;
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
}
function gameMenu(g, e) {
  showCtx(e, box => {
    ctxTitle(box, g.name);
    ctxItem(box, 'play_arrow', 'Lancer', () => { hideCtx(); launch(g); });
    ctxItem(box, 'folder_open', 'Ouvrir le dossier du jeu', () => openFolder(() => invoke('game_folder', { id: g.id })));
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
    b.innerHTML = `<span class="ms">${icon}</span>`;
    const n = document.createElement('span');
    n.textContent = name;
    b.append(n);
    if (count != null) b.insertAdjacentHTML('beforeend', `<i>${count}</i>`);
    b.addEventListener('click', () => { folders.sel = id; saveFolders(); renderApps(); });
    bar.append(b);
    return b;
  };
  chip('', 'grid_view', 'Toutes');
  chip(GAMES, 'stadia_controller', 'Launcher', games.length || null).classList.add('games-chip');
  folders.list.forEach(f => {
    const n = f.apps.filter(id => apps.some(a => a.id === id)).length;
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
  const page = $('[data-page="apps"]').getBoundingClientRect();
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
    ctxItem(box, 'folder_open', 'Ouvrir l’emplacement', () => openFolder(() => invoke('app_folder', { id: a.id, name: a.name })));
    box.insertAdjacentHTML('beforeend', '<hr class="ctx-sep">');
    folders.list.forEach(f => {
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

function folderMenu(f, e) {
  showCtx(e, box => {
    ctxTitle(box, f.name);
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
    folders = { list: saved.list, sel: saved.sel || '' };
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
  if (a.source) invoke('game_launch', { id: a.id });
  else invoke('app_launch', { id: a.id });
  $('#q').value = '';
  setState('collapsed');
}
$('#q').addEventListener('input', () => { appSel = 0; renderApps(); });
$('#q').addEventListener('keydown', e => {
  const cols = folders.sel === GAMES ? 6 : 7;
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
  if (isWe || !we.running) currentThumb = w.thumb;
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
async function themeFrom(src) {
  try {
    const img = new Image();
    img.src = src;
    await img.decode();
    const argb = await sourceColorFromImage(img);
    const scheme = new SchemeTonalSpot(Hct.fromInt(argb), true, 0);
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
