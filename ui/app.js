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
let appSel = 0;
let appView = [];
const norm = s => s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
function renderApps() {
  const q = norm($('#q').value.trim());
  appView = !q ? apps : apps
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
  if (!apps.length) { grid.innerHTML = '<div class="empty">Chargement des applications…</div>'; return; }
  if (!appView.length) { grid.innerHTML = '<div class="empty">Aucune application</div>'; return; }
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
    grid.append(el);
  });
}
function launch(a) {
  invoke('app_launch', { id: a.id });
  $('#q').value = '';
  setState('collapsed');
}
$('#q').addEventListener('input', () => { appSel = 0; renderApps(); });
$('#q').addEventListener('keydown', e => {
  const cols = 7;
  const moves = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: cols, ArrowUp: -cols };
  if (e.key in moves) {
    e.preventDefault();
    appSel = Math.max(0, Math.min(appView.length - 1, appSel + moves[e.key]));
    $$('.app').forEach((el, i) => el.classList.toggle('sel', i === appSel));
    $$('.app')[appSel]?.scrollIntoView({ block: 'nearest' });
  } else if (e.key === 'Enter' && appView[appSel]) {
    launch(appView[appSel]);
  }
});
listen('apps', ({ payload }) => { apps = payload; if (currentTab === 'apps') renderApps(); });
invoke('apps_get').then(l => { if (l.length) apps = l; });

// ========================================================= presse-papiers
function renderClips(list) {
  $('.clip-count').textContent = list.length ? `${list.length} élément${list.length > 1 ? 's' : ''}` : 'Historique vide';
  const box = $('.clip-list');
  box.innerHTML = list.length ? '' : '<div class="empty">Copiez du texte : il apparaîtra ici.</div>';
  list.forEach(t => {
    const el = document.createElement('button');
    el.className = 'clip';
    const p = document.createElement('p');
    p.textContent = t.length > 600 ? t.slice(0, 600) + '…' : t;
    el.append(p);
    el.insertAdjacentHTML('beforeend', '<span class="ms">check</span>');
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

$$('.seg button').forEach(b => b.addEventListener('click', () => {
  if (b.dataset.src === wallSrc) return;
  wallSrc = b.dataset.src;
  $$('.seg button').forEach(x => x.classList.toggle('on', x === b));
  loadWalls();
}));
$('#wall-refresh').addEventListener('click', () => loadWalls(true));
$('#wall-folder').addEventListener('click', () => { invoke('walls_open_folder'); setState('collapsed'); });

// fond actif (WE s'il tourne, sinon Windows) -> palette
async function syncWall() {
  we = await invoke('we_state');
  $('.seg').hidden = !we.installed;
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
    $$('.seg button').forEach(x => x.classList.toggle('on', x.dataset.src === 'we'));
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
