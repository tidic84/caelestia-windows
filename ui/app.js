import {
  Hct, SchemeTonalSpot, SchemeVibrant, SchemeExpressive, SchemeFidelity, SchemeContent,
  SchemeMonochrome, SchemeNeutral, SchemeRainbow, SchemeFruitSalad,
  MaterialDynamicColors as MDC, sourceColorFromImage, hexFromArgb,
} from './vendor/mcu.js';
import { calc, looksLikeMath, fmtNumber } from './calc.js';
import { searchEmoji } from './emoji.js';
import { eventsBetween } from './ical.js';

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const island = $('#island');
const norm = s => s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const store = {
  get(k, d = null) { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} },
};

// Réglages (remplacés par ceux du backend au démarrage)
let cfg = {
  variant: 'tonalspot', mode: 'dark', win_accent: false, win_mode: false, city: null, icals: [],
  rotate_min: 0, notif_popups: true, dnd: false, osd: true,
};
async function setCfg(patch) {
  Object.assign(cfg, patch);
  onSettings();
  cfg = { ...cfg, ...(await invoke('settings_set', { patch })) };
}

// ======================================================= état de l'îlot
// collapsed -> (survol) peek -> (clic / molette) open
// En replié, une « activité » (OSD, notification…) peut agrandir la pilule.
const OPEN = { w: 740, h: 540 };
const EAR = 22;
let state = 'collapsed';
let hovered = false;
let pinned = false; // ouvert au clavier : ne se referme pas en sortant la souris
let leaveTimer = null;
let hasMedia = false;
let fullscreen = false;
let act = null;
let actTimer = null;
let weather = null;

function sizeFor(s) {
  if (s === 'open') return OPEN;
  if (s === 'peek') return hasMedia ? { w: 420, h: 66 } : { w: weather ? 320 : 250, h: 50 };
  if (act) return act.size;
  let w = hasMedia ? 200 : 132;
  w += $$('.pill-mini .ind:not(.ind-timer):not([hidden])').length * 24;
  if (!$('.ind-timer').hidden) w += 70;
  return { w, h: 30 };
}

function applySize() {
  const { w, h } = sizeFor(state);
  island.style.width = w + 'px';
  island.style.height = h + 'px';
  island.classList.toggle('act', !!act && state === 'collapsed');
  reportHit();
}

function reportHit() {
  const { w, h } = sizeFor(state);
  const x = (innerWidth - w) / 2 - EAR;
  // un peu de marge sous l'îlot replié pour l'attraper facilement
  invoke('set_hit', { x, y: 0, w: w + EAR * 2, h: h + (state === 'collapsed' ? 6 : 2) });
}

function setState(s) {
  if (s === state) return;
  state = s;
  island.classList.remove('collapsed', 'peek', 'open');
  island.classList.add(s);
  if (s !== 'open') { pinned = false; closeSheets(); }
  if (s !== 'collapsed' && act) endActivity(false);
  if (s === 'open') onOpen();
  applySize();
  updateViz();
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
    if (state === 'collapsed' && !act) setState('peek');
  } else if (state === 'peek') {
    leaveTimer = setTimeout(() => setState('collapsed'), 120);
  } else if (state === 'open' && !pinned) {
    leaveTimer = setTimeout(() => setState('collapsed'), 450);
  }
});
listen('fullscreen', ({ payload }) => {
  fullscreen = payload;
  island.classList.toggle('hidden', payload);
  if (payload) { setState('collapsed'); endActivity(); }
  updateViz();
});
listen('blur', () => {
  if (state === 'open' && !hovered) setState('collapsed');
});
listen('open', ({ payload }) => { pinned = true; open(payload); });
listen('launcher', () => {
  if (state === 'open' && currentTab === 'apps') return setState('collapsed');
  pinned = true;
  open('apps');
  setTimeout(() => $('#q').focus(), 60);
});

$('#pill').addEventListener('click', e => {
  if (e.target.closest('[data-media]')) return;
  if (act) {
    const tab = act.tab;
    const onClick = act.onClick;
    endActivity(false);
    if (onClick) return onClick();
    return open(tab || null);
  }
  open(hasMedia && currentTab === 'home' ? 'home' : null);
});
island.addEventListener('wheel', e => {
  if (state !== 'open' && e.deltaY > 0) open();
  else if (state === 'open' && e.deltaY < 0 && e.target.closest('#tabs')) close();
}, { passive: true });
addEventListener('keydown', e => {
  if (e.key !== 'Escape' || state !== 'open') return;
  if ($('.sheet.on')) return closeSheets();
  if ($('.cal-card.day')) return $('.cal-card').classList.remove('day');
  close();
});
addEventListener('resize', reportHit);

// ============================================================== activités
const ACT_SIZE = { osd: { w: 300, h: 40 }, small: { w: 290, h: 40 }, notif: { w: 420, h: 66 }, shot: { w: 300, h: 62 } };

function showActivity(a) {
  if (state !== 'collapsed' || fullscreen) return;
  const same = act && act.kind === a.kind && a.kind === 'osd';
  act = { ...a, size: ACT_SIZE[a.size || a.kind] || ACT_SIZE.small };
  const box = $('.pill-act');
  if (same) {
    // l'OSD se met à jour sans rejouer l'animation
    box.querySelector('.ms').textContent = a.icon;
    box.querySelector('.act-bar i').style.width = a.value * 100 + '%';
    box.querySelector('b').textContent = a.label;
  } else {
    box.className = 'pill-act act-' + a.kind;
    box.innerHTML = a.html;
  }
  applySize();
  clearTimeout(actTimer);
  actTimer = setTimeout(() => endActivity(), a.ms || 2600);
}
function endActivity(resize = true) {
  clearTimeout(actTimer);
  if (!act) return;
  act = null;
  if (resize) applySize();
  else island.classList.remove('act');
  if (hovered && state === 'collapsed') setState('peek');
}
function simpleActivity(icon, title, sub = '', extra = {}) {
  showActivity({
    kind: 'small',
    html: `<span class="ms">${icon}</span><span class="act-text"><b>${esc(title)}</b>${sub ? `<small>${esc(sub)}</small>` : ''}</span>`,
    ...extra,
  });
}

listen('osd', ({ payload: o }) => {
  if (o.kind === 'volume' && state === 'open') showVolume(o.value, o.muted);
  if (!cfg.osd) return;
  const v = o.muted ? 0 : o.value;
  const icon = o.kind === 'brightness'
    ? (v < 0.34 ? 'brightness_low' : v < 0.67 ? 'brightness_medium' : 'brightness_high')
    : (o.muted || v === 0 ? 'volume_off' : v < 0.5 ? 'volume_down' : 'volume_up');
  showActivity({
    kind: 'osd', icon, value: v, label: o.muted ? '–' : String(Math.round(v * 100)), ms: 1600,
    html: `<span class="ms">${icon}</span><span class="act-bar"><i style="width:${v * 100}%"></i></span><b>${o.muted ? '–' : Math.round(v * 100)}</b>`,
  });
});

listen('activity', ({ payload: a }) => {
  switch (a.kind) {
    case 'caps':
      simpleActivity(a.on ? 'keyboard_capslock_badge' : 'keyboard_capslock', a.on ? 'Verr. Maj activé' : 'Verr. Maj désactivé', '', { ms: 1400 });
      break;
    case 'power':
      simpleActivity(a.on ? 'battery_charging_full' : 'battery_full', a.on ? 'En charge' : 'Sur batterie', a.battery >= 0 ? a.battery + ' %' : '');
      break;
    case 'bt':
      simpleActivity(a.on ? 'bluetooth_connected' : 'bluetooth_disabled', a.name, a.on ? 'Connecté' : 'Déconnecté', { tab: 'ctrl' });
      break;
    case 'shot':
      showActivity({
        kind: 'shot', ms: 3200, tab: 'clips',
        html: `<img src="${a.thumb}" alt=""><span class="act-text"><b>Image copiée</b><small>Dans le presse-papiers</small></span>`,
      });
      break;
  }
});

// ================================================================ onglets
let currentTab = 'home';
const TABS = $$('#tabs button').map(b => b.dataset.tab);

function showTab(tab) {
  const dir = TABS.indexOf(tab) > TABS.indexOf(currentTab) ? 1 : -1;
  if (tab !== currentTab) closeSheets();
  currentTab = tab;
  $$('#tabs button').forEach(b => b.classList.toggle('on', b.dataset.tab === tab));
  $$('.page').forEach(p => {
    const on = p.dataset.page === tab;
    p.style.setProperty('--dx', `${on ? 0 : -dir * 24}px`);
    p.classList.toggle('on', on);
  });
  moveIndicator();
  onTab(tab);
  updateViz();
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
  if (state !== 'open') return;
  if (tab === 'walls' && !wallsLoaded) loadWalls();
  if (tab === 'apps') renderApps();
  if (tab === 'settings') loadSettings();
  if (tab === 'ctrl') enterCtrl();
  if (tab === 'home') refreshEvents();
}

// ================================================================ horloge
const fmtDate = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
const fmtShort = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
const fmtHM = new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit' });
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
let icalTexts = [];
let icalAt = 0;
let monthEvents = [];
const fmtMonth = new Intl.DateTimeFormat('fr-FR', { month: 'long', year: 'numeric' });
const dayKey = d => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;

function calRange() {
  const now = new Date();
  const first = new Date(now.getFullYear(), now.getMonth() + calOffset, 1);
  const start = new Date(first);
  start.setDate(1 - ((first.getDay() + 6) % 7)); // lundi en premier
  const end = new Date(start);
  end.setDate(start.getDate() + 42);
  return { first, start, end };
}

function renderCal() {
  const now = new Date();
  const { first, start, end } = calRange();
  monthEvents = icalTexts.length ? eventsBetween(icalTexts, start, end) : [];
  const busy = new Set();
  for (const e of monthEvents) {
    const d = new Date(Math.max(e.start, start));
    while (d < e.end && d < end) { busy.add(dayKey(d)); d.setDate(d.getDate() + 1); d.setHours(0, 0, 0, 0); }
    if (e.end - e.start <= 0) busy.add(dayKey(e.start));
  }
  $('.cal-title').textContent = fmtMonth.format(first);
  const grid = $('.cal-grid');
  grid.innerHTML = ['L', 'M', 'M', 'J', 'V', 'S', 'D'].map(d => `<span class="dow">${d}</span>`).join('');
  const day = new Date(start);
  for (let i = 0; i < 42; i++) {
    const out = day.getMonth() !== first.getMonth();
    const today = day.toDateString() === now.toDateString();
    const we = i % 7 >= 5;
    const el = document.createElement('button');
    el.className = `d${out ? ' out' : ''}${today ? ' today' : ''}${we ? ' we' : ''}${busy.has(dayKey(day)) ? ' ev' : ''}`;
    el.textContent = day.getDate();
    const d = new Date(day);
    el.addEventListener('click', () => showDay(d));
    grid.append(el);
    day.setDate(day.getDate() + 1);
  }
}

const fmtDay = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
function showDay(d) {
  const from = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const to = new Date(from); to.setDate(to.getDate() + 1);
  const evs = (icalTexts.length ? eventsBetween(icalTexts, from, new Date(to - 1)) : []).filter(e => e.end > from && e.start < to);
  $('.cal-day-title').textContent = fmtDay.format(from);
  const box = $('.cal-events');
  if (!evs.length) {
    box.innerHTML = `<div class="empty small">${cfg.icals.length ? 'Aucun événement' : 'Ajoutez un agenda iCal dans les réglages pour voir vos événements.'}</div>`;
  } else {
    box.innerHTML = '';
    for (const e of evs) {
      const el = document.createElement('div');
      el.className = 'event';
      const when = e.allDay || (e.start <= from && e.end >= to) ? 'Journée' : `${fmtHM.format(e.start)} – ${fmtHM.format(e.end)}`;
      el.innerHTML = `<i></i><span><b></b><small></small></span>`;
      el.querySelector('b').textContent = e.title || 'Sans titre';
      el.querySelector('small').textContent = e.location ? `${when} · ${e.location}` : when;
      box.append(el);
    }
  }
  $('.cal-card').classList.add('day');
}
$('#cal-back').addEventListener('click', () => $('.cal-card').classList.remove('day'));
$$('[data-cal]').forEach(b => b.addEventListener('click', () => {
  calOffset += Number(b.dataset.cal);
  renderCal();
}));

async function refreshEvents(force) {
  if (!cfg.icals.length) { if (icalTexts.length) { icalTexts = []; renderCal(); } return; }
  if (!force && Date.now() - icalAt < 15 * 60000) return;
  icalAt = Date.now();
  const texts = await Promise.all(cfg.icals.map(u => invoke('http_get', { url: u }).catch(() => '')));
  icalTexts = texts.filter(Boolean);
  renderCal();
}
setInterval(() => refreshEvents(), 15 * 60000);

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
  if (had !== hasMedia) applySize();
  const title = hasMedia ? m.title || 'Sans titre' : 'Rien en lecture';
  $('.peek-title').textContent = $('.hm-title').textContent = $('.mp-title').textContent = title;
  $('.peek-artist').textContent = $('.hm-artist').textContent = $('.mp-artist').textContent = hasMedia ? m.artist : '';
  $('.mp-album').textContent = hasMedia ? m.album : '';
  $('.mp-app').textContent = hasMedia ? m.app : '';
  $$('.play-icon').forEach(i => (i.textContent = m.playing ? 'pause' : 'play_arrow'));
  updateProgress();
  updateViz();
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

// ============================================================ visualiseur
// Le backend capture le son du PC (loopback) et envoie 24 bandes (0..100).
let vizOn = false;
let bands = new Array(24).fill(0);
let shown = new Array(24).fill(0);
let vizColor = '#cfbdfe';
let vizFade = null;

function updateViz() {
  const visible = state !== 'open' || currentTab === 'home' || currentTab === 'media';
  const want = !!(hasMedia && media.playing && !fullscreen && visible);
  if (want === vizOn) return;
  vizOn = want;
  invoke('viz_set', { on: want });
  if (!want) fadeViz();
}
// le dessin suit les trames du backend (~30 par seconde) : requestAnimationFrame
// est ralenti par WebView2 quand la fenêtre transparente est jugée masquée
listen('viz', ({ payload }) => {
  bands = payload;
  clearInterval(vizFade);
  vizFade = null;
  drawViz(vizOn ? bands : bands.map(() => 0));
});
function fadeViz() {
  clearInterval(vizFade);
  vizFade = setInterval(() => {
    if (drawViz(bands.map(() => 0)) < 0.01) {
      clearInterval(vizFade);
      vizFade = null;
      island.classList.remove('live');
      $$('.viz').forEach(c => c.getContext('2d').clearRect(0, 0, c.width, c.height));
      $$('.eq i').forEach(el => (el.style.height = ''));
    }
  }, 33);
}

function drawViz(target) {
  let energy = 0;
  for (let i = 0; i < shown.length; i++) {
    const t = (target[i] || 0) / 100;
    // monte d'un coup, retombe en douceur
    shown[i] = t > shown[i] ? t : shown[i] + (t - shown[i]) * 0.3;
    energy += shown[i];
  }
  island.classList.add('live');
  // égaliseur de la pilule : 3 groupes de bandes
  $$('.eq i').forEach((el, k) => {
    const g = shown.slice(k * 8, k * 8 + 8);
    const v = g.reduce((a, b) => a + b, 0) / g.length;
    el.style.height = 3 + v * 9 + 'px';
  });
  if (state === 'open') {
    const c = currentTab === 'media' ? $('.viz-media') : currentTab === 'home' ? $('.viz-home') : null;
    if (c) paintBars(c);
  }
  return energy;
}

function paintBars(c) {
  const g = c.getContext('2d');
  const { width: W, height: H } = c;
  g.clearRect(0, 0, W, H);
  g.fillStyle = vizColor;
  const n = shown.length;
  const gap = W / n * 0.28;
  const bw = W / n - gap;
  for (let i = 0; i < n; i++) {
    const h = Math.max(bw * 0.6, shown[i] * H);
    const x = i * (bw + gap) + gap / 2;
    const r = Math.min(bw / 2, h / 2);
    g.beginPath();
    g.roundRect(x, H - h, bw, h, [r, r, 0, 0]);
    g.fill();
  }
}

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
function fmtUptime(s) {
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d) return `${d} j ${h} h`;
  if (h) return `${h} h ${String(m).padStart(2, '0')}`;
  return `${m} min`;
}
listen('sys', ({ payload: r }) => {
  gauge('cpu', r.cpu / 100, Math.round(r.cpu) + ' %');
  gauge('mem', r.mem_used / r.mem_total, `${gb(r.mem_used)} / ${gb(r.mem_total)} Go`);
  if (r.disk_total) gauge('disk', r.disk_used / r.disk_total, `${gb(r.disk_used)} / ${gb(r.disk_total)} Go`);
  const bat = $('.gauge[data-g="bat"]');
  bat.hidden = r.battery < 0;
  if (r.battery >= 0) gauge('bat', r.battery / 100, r.battery + (r.charging ? ' % ⚡' : ' %'));
  $('.uptime').textContent = 'Allumé depuis ' + fmtUptime(r.uptime);
});

// ============================================================ utilisateur
invoke('user_info').then(u => {
  $('.user-name').textContent = u.name || 'Bonjour';
  const img = $('.avatar img');
  if (u.avatar) img.src = u.avatar;
  $('.avatar span').textContent = (u.name || '?').trim()[0]?.toUpperCase() || '?';
  $('.avatar').classList.toggle('has', !!u.avatar);
});

// ================================================================= météo
// Open-Meteo : gratuit, sans clé. Codes météo OMM -> icône + libellé.
const WMO = {
  0: ['clear_day', 'Ciel dégagé'], 1: ['partly_cloudy_day', 'Plutôt dégagé'], 2: ['partly_cloudy_day', 'Partiellement nuageux'],
  3: ['cloud', 'Couvert'], 45: ['foggy', 'Brouillard'], 48: ['foggy', 'Brouillard givrant'],
  51: ['rainy_light', 'Bruine légère'], 53: ['rainy_light', 'Bruine'], 55: ['rainy_light', 'Bruine dense'],
  56: ['weather_mix', 'Bruine verglaçante'], 57: ['weather_mix', 'Bruine verglaçante'],
  61: ['rainy_light', 'Pluie faible'], 63: ['rainy', 'Pluie'], 65: ['rainy_heavy', 'Forte pluie'],
  66: ['weather_mix', 'Pluie verglaçante'], 67: ['weather_mix', 'Pluie verglaçante'],
  71: ['weather_snowy', 'Neige faible'], 73: ['weather_snowy', 'Neige'], 75: ['snowing_heavy', 'Forte neige'], 77: ['weather_snowy', 'Grains de neige'],
  80: ['rainy_light', 'Averses'], 81: ['rainy', 'Averses'], 82: ['rainy_heavy', 'Fortes averses'],
  85: ['weather_snowy', 'Averses de neige'], 86: ['snowing_heavy', 'Averses de neige'],
  95: ['thunderstorm', 'Orage'], 96: ['thunderstorm', 'Orage et grêle'], 99: ['thunderstorm', 'Orage et grêle'],
};
const NIGHT = { clear_day: 'clear_night', partly_cloudy_day: 'partly_cloudy_night' };

async function refreshWeather() {
  const c = cfg.city;
  if (!c) { weather = null; renderWeather(); return; }
  try {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${c.lat}&longitude=${c.lon}`
      + '&current=temperature_2m,apparent_temperature,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1';
    const j = JSON.parse(await invoke('http_get', { url }));
    const [icon, label] = WMO[j.current.weather_code] || ['cloud', '—'];
    weather = {
      icon: j.current.is_day ? icon : NIGHT[icon] || icon, label,
      temp: Math.round(j.current.temperature_2m), feels: Math.round(j.current.apparent_temperature),
      min: Math.round(j.daily.temperature_2m_min[0]), max: Math.round(j.daily.temperature_2m_max[0]),
    };
  } catch (e) {
    console.warn('météo', e);
  }
  renderWeather();
}
function renderWeather() {
  const w = weather;
  $('.wx-icon').textContent = w ? w.icon : 'location_on';
  $('.wx-temp').textContent = w ? `${w.temp}°` : '';
  $('.wx-desc').textContent = w ? w.label : 'Météo';
  $('.wx-place').textContent = w ? `${cfg.city.name} · ${w.min}° / ${w.max}°` : cfg.city ? cfg.city.name : 'Choisir une ville';
  $('.peek-wx').hidden = !w;
  if (w) {
    $('.peek-wx .ms').textContent = w.icon;
    $('.peek-wx b').textContent = `${w.temp}°`;
  }
  if (state === 'peek') applySize();
}
$('.wx-card').addEventListener('click', () => {
  showTab('settings');
  setTimeout(() => $('#city-q').scrollIntoView({ block: 'center', behavior: 'smooth' }), 80);
});
setInterval(refreshWeather, 20 * 60000);

// ================================================================ session
const SESSION_ACTIONS = { lock: 'Verrouiller', sleep: 'Veille', logout: 'Déconnexion', restart: 'Redémarrer', shutdown: 'Éteindre' };
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

// ============================================================= contrôles
let net = { radios: { wifi: null, bluetooth: null }, ssid: '', bt_devices: [] };
let caffeine = false;
let mixerTimer = null;
let winLight = false;

function tile(name) { return $(`.tile[data-tile="${name}"]`); }
function setTile(name, on, sub, hidden = false) {
  const t = tile(name);
  t.hidden = hidden;
  t.classList.toggle('on', !!on);
  t.querySelector('small').textContent = sub;
}
function renderTiles() {
  const r = net.radios;
  setTile('wifi', r.wifi, r.wifi ? net.ssid || 'Non connecté' : 'Désactivé', r.wifi === null);
  const devs = net.bt_devices;
  setTile('bt', r.bluetooth, r.bluetooth ? (devs.length ? devs.join(', ') : 'Activé') : 'Désactivé', r.bluetooth === null);
  setTile('caf', caffeine, caffeine ? 'Veille bloquée' : 'Veille normale');
  setTile('dnd', cfg.dnd, cfg.dnd ? 'Activé' : 'Désactivé');
  const dark = isDark();
  setTile('dark', dark, cfg.mode === 'auto' ? `Auto (${dark ? 'sombre' : 'clair'})` : dark ? 'Activé' : 'Désactivé');
  tile('dark').querySelector('.ms').textContent = dark ? 'dark_mode' : 'light_mode';
  renderTimerTile();
}
listen('net', ({ payload }) => { net = payload; renderTiles(); });
listen('caffeine', ({ payload }) => { caffeine = payload; renderTiles(); updateIndicators(); });

async function enterCtrl() {
  renderTiles();
  invoke('net_get').then(n => { net = n; renderTiles(); });
  invoke('brightness_get').then(b => {
    $('.bright-row').hidden = !b;
    if (b) showBright(b.level);
  });
  refreshOut();
  refreshMixer();
  clearInterval(mixerTimer);
  mixerTimer = setInterval(() => {
    if (state !== 'open' || currentTab !== 'ctrl') return clearInterval(mixerTimer);
    refreshMixer();
  }, 2000);
}

async function toggleRadio(kind) {
  const key = kind === 'wifi' ? 'wifi' : 'bluetooth';
  const on = !net.radios[key];
  net.radios[key] = on;
  renderTiles();
  await invoke('radio_set', { kind, on });
  net = await invoke('net_get');
  renderTiles();
}
async function toggleCaffeine() {
  caffeine = await invoke('caffeine_set', { on: !caffeine });
  renderTiles();
  updateIndicators();
}
function toggleDnd() {
  setCfg({ dnd: !cfg.dnd });
}

$('[data-tile="wifi"] .tile-main').addEventListener('click', () => toggleRadio('wifi'));
$('[data-tile="wifi"] .tile-more').addEventListener('click', () => openSheet('wifi'));
$('[data-tile="bt"] .tile-main').addEventListener('click', () => toggleRadio('bluetooth'));
$('[data-tile="caf"] .tile-main').addEventListener('click', toggleCaffeine);
$('[data-tile="dnd"] .tile-main').addEventListener('click', toggleDnd);
$('[data-tile="dark"] .tile-main').addEventListener('click', () => setCfg({ mode: isDark() ? 'light' : 'dark' }));
$('[data-tile="timer"] .tile-main').addEventListener('click', () => {
  if (timer.running || timer.remaining < timer.total) timerToggle();
  else openSheet('timer');
});
$('[data-tile="timer"] .tile-more').addEventListener('click', () => openSheet('timer'));

// --- feuilles (réseaux, sorties audio, minuteur)
function openSheet(name) {
  $$('.sheet').forEach(s => s.classList.toggle('on', s.dataset.sheet === name));
  if (name === 'wifi') loadWifi();
  if (name === 'out') refreshOut(true);
  if (name === 'timer') renderTimer();
}
function closeSheets() {
  $$('.sheet.on').forEach(s => s.classList.remove('on'));
}
$$('[data-close-sheet]').forEach(b => b.addEventListener('click', closeSheets));

// --- Wi-Fi
const WIFI_ICON = s => (s > 66 ? 'wifi' : s > 33 ? 'wifi_2_bar' : 'wifi_1_bar');
let wifiBusy = false;
async function loadWifi(scan = true) {
  const box = $('.wifi-list');
  if (net.radios.wifi === false) {
    box.innerHTML = '<div class="empty small">Le Wi-Fi est désactivé.</div>';
    return;
  }
  if (!box.children.length || box.querySelector('.empty')) box.innerHTML = '<div class="empty small">Recherche des réseaux…</div>';
  renderWifi(await invoke('wifi_list', { scan: false }));
  if (scan) {
    $('#wifi-scan').classList.add('spinning');
    renderWifi(await invoke('wifi_list', { scan: true }));
    $('#wifi-scan').classList.remove('spinning');
  }
}
function renderWifi(list) {
  const box = $('.wifi-list');
  if (wifiBusy) return;
  if (!list.length) { box.innerHTML = '<div class="empty small">Aucun réseau trouvé.</div>'; return; }
  box.innerHTML = '';
  for (const n of list) {
    const el = document.createElement('div');
    el.className = 'net' + (n.connected ? ' on' : '');
    el.innerHTML = `<button class="net-main"><span class="ms">${WIFI_ICON(n.signal)}</span><span class="net-text"><b></b><small></small></span>${n.secure ? '<span class="ms lock">lock</span>' : ''}</button>`;
    el.querySelector('b').textContent = n.ssid;
    el.querySelector('small').textContent = n.connected ? 'Connecté' : n.known ? 'Enregistré' : n.secure ? 'Sécurisé' : 'Ouvert';
    el.querySelector('.net-main').addEventListener('click', () => {
      if (n.connected) return wifiDisconnect(el);
      if (n.secure && !n.known) return askPassword(el, n);
      wifiConnect(el, n.ssid);
    });
    box.append(el);
  }
}
function askPassword(el, n) {
  if (el.querySelector('form')) return;
  const f = document.createElement('form');
  f.className = 'net-pass';
  f.innerHTML = '<input type="password" placeholder="Mot de passe" autocomplete="off"><button class="icon-btn filled small" type="submit"><span class="ms">arrow_forward</span></button>';
  f.addEventListener('submit', e => {
    e.preventDefault();
    wifiConnect(el, n.ssid, f.querySelector('input').value);
  });
  el.append(f);
  invoke('grab_focus');
  f.querySelector('input').focus();
}
async function wifiConnect(el, ssid, password) {
  wifiBusy = true;
  el.querySelector('small').textContent = 'Connexion…';
  el.classList.add('busy');
  try {
    await invoke('wifi_connect', { ssidName: ssid, password: password ?? null });
    await new Promise(r => setTimeout(r, 4000));
  } catch (e) {
    wifiBusy = false;
    el.classList.remove('busy');
    if (e === 'password') return askPassword(el, { ssid });
    el.querySelector('small').textContent = String(e);
    return;
  }
  wifiBusy = false;
  net = await invoke('net_get');
  renderTiles();
  loadWifi(false);
}
async function wifiDisconnect(el) {
  el.querySelector('small').textContent = 'Déconnexion…';
  await invoke('wifi_disconnect');
  await new Promise(r => setTimeout(r, 1500));
  net = await invoke('net_get');
  renderTiles();
  loadWifi(false);
}
$('#wifi-scan').addEventListener('click', () => loadWifi(true));

// --- luminosité
const bright = $('#bright');
let brightBusy = false;
let brightPending = null;
function showBright(level) {
  const v = Math.round(level * 100);
  bright.value = v;
  bright.style.setProperty('--p', v + '%');
  $('.bright-val').textContent = v;
}
async function pushBright() {
  // DDC/CI est lent : on n'envoie que la dernière valeur demandée
  if (brightBusy) return;
  brightBusy = true;
  while (brightPending !== null) {
    const v = brightPending;
    brightPending = null;
    await invoke('brightness_set', { level: v });
  }
  brightBusy = false;
}
bright.addEventListener('input', () => {
  showBright(bright.value / 100);
  brightPending = bright.value / 100;
  pushBright();
});

// --- sortie audio et mélangeur
async function refreshOut(sheet) {
  const list = await invoke('audio_devices');
  const cur = list.find(d => d.default);
  $('.out-name').textContent = cur ? cur.name : 'Sortie audio';
  if (!sheet) return;
  const box = $('.out-list');
  box.innerHTML = list.length ? '' : '<div class="empty small">Aucune sortie audio.</div>';
  for (const d of list) {
    const el = document.createElement('button');
    el.className = 'net' + (d.default ? ' on' : '');
    el.innerHTML = `<span class="net-main"><span class="ms">${/casque|headphone|headset|écouteur|airpods|buds/i.test(d.name) ? 'headphones' : 'speaker'}</span><span class="net-text"><b></b></span>${d.default ? '<span class="ms">check</span>' : ''}</span>`;
    el.querySelector('b').textContent = d.name;
    el.addEventListener('click', async () => {
      await invoke('audio_set_default', { id: d.id });
      await refreshOut(true);
      refreshVolume();
      refreshMixer();
    });
    box.append(el);
  }
}
$('.out-btn').addEventListener('click', () => openSheet('out'));

let mixDragging = false;
async function refreshMixer() {
  if (mixDragging) return;
  const list = await invoke('mixer_get');
  const box = $('.mix-list');
  const pids = list.map(a => a.pids.join('+')).join(',');
  if (box.dataset.pids !== pids) {
    box.dataset.pids = pids;
    box.innerHTML = list.length ? '' : '<div class="empty small">Aucune application ne joue de son.</div>';
    for (const a of list) {
      const el = document.createElement('div');
      el.className = 'mix';
      el.dataset.pid = a.pids[0];
      el.innerHTML = `<button class="mix-icon" title="Couper / rétablir">${a.icon ? `<img src="${a.icon}" alt="">` : '<span class="ms">notifications</span>'}<span class="ms mute-x">volume_off</span></button>
        <span class="mix-name"></span><input type="range" class="slider" min="0" max="100"><span class="row-val"></span>`;
      el.querySelector('.mix-name').textContent = a.name;
      const r = el.querySelector('input');
      r.addEventListener('pointerdown', () => (mixDragging = true));
      r.addEventListener('pointerup', () => (mixDragging = false));
      r.addEventListener('input', () => {
        showMix(el, r.value / 100, false);
        invoke('mixer_set', { pids: a.pids, level: r.value / 100, muted: false });
      });
      el.querySelector('.mix-icon').addEventListener('click', () => {
        const m = !el.classList.contains('muted');
        showMix(el, r.value / 100, m);
        invoke('mixer_set', { pids: a.pids, muted: m });
      });
      box.append(el);
    }
  }
  for (const a of list) {
    const el = box.querySelector(`.mix[data-pid="${a.pids[0]}"]`);
    if (el) showMix(el, a.level, a.muted);
  }
}
function showMix(el, level, muted) {
  const v = Math.round(level * 100);
  const r = el.querySelector('input');
  r.value = v;
  r.style.setProperty('--p', (muted ? 0 : v) + '%');
  el.querySelector('.row-val').textContent = muted ? '–' : v;
  el.classList.toggle('muted', muted);
}

// ========================================================== notifications
let notifs = [];
const fmtTimeOfDay = new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit' });
function ago(ms) {
  const s = (Date.now() - ms) / 1000;
  if (s < 60) return "à l'instant";
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  const d = new Date(ms);
  if (d.toDateString() === new Date().toDateString()) return fmtTimeOfDay.format(d);
  const y = new Date(); y.setDate(y.getDate() - 1);
  if (d.toDateString() === y.toDateString()) return 'hier';
  return d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });
}
function appFor(id) {
  const low = (id || '').toLowerCase();
  const a = apps.find(x => x.id.toLowerCase() === low);
  if (a) return { name: a.name, icon: a.icon };
  const short = (id || '').split(/[\\/!]/).pop().replace(/\.exe$/i, '').replace(/_[a-z0-9]{13}$/i, '');
  const b = apps.find(x => norm(x.name) === norm(short));
  return { name: b?.name || short || 'Application', icon: b?.icon || '' };
}
function renderNotifs() {
  const box = $('.notif-list');
  const n = notifs.length;
  $('.notif-count').textContent = n ? n : '';
  const badge = $('#tabs .badge');
  badge.hidden = !n;
  badge.textContent = n > 9 ? '9+' : n;
  if (!n) {
    box.innerHTML = `<div class="empty small"><span class="ms big">${cfg.dnd ? 'do_not_disturb_on' : 'notifications_none'}</span>${cfg.dnd ? 'Ne pas déranger est activé' : 'Aucune notification'}</div>`;
    return;
  }
  box.innerHTML = '';
  for (const x of notifs) {
    const app = appFor(x.app);
    const el = document.createElement('div');
    el.className = 'notif';
    const pic = x.image || app.icon;
    el.innerHTML = `${pic ? `<img src="${pic}" alt="">` : '<span class="ms nicon">notifications</span>'}
      <div class="notif-text"><div class="notif-meta"><span></span><i></i></div><b></b><p></p></div>
      <button class="icon-btn small notif-x" title="Masquer"><span class="ms">close</span></button>`;
    el.querySelector('.notif-meta span').textContent = app.name;
    el.querySelector('.notif-meta i').textContent = ago(x.time);
    el.querySelector('b').textContent = x.title;
    el.querySelector('p').textContent = x.body;
    el.querySelector('.notif-x').addEventListener('click', e => {
      e.stopPropagation();
      el.classList.add('gone');
      setTimeout(() => invoke('notifs_dismiss', { id: x.id }), 200);
    });
    el.addEventListener('click', () => { invoke('notif_open', { appId: x.app }); setState('collapsed'); });
    box.append(el);
  }
}
listen('notifs', ({ payload }) => { notifs = payload; renderNotifs(); });
invoke('notifs_get').then(l => { notifs = l; renderNotifs(); });
listen('notif', ({ payload: x }) => {
  if (!cfg.notif_popups || cfg.dnd) return;
  const app = appFor(x.app);
  const pic = x.image || app.icon;
  showActivity({
    kind: 'notif', ms: 5200, onClick: () => open('ctrl'),
    html: `${pic ? `<img src="${pic}" alt="">` : '<span class="ms">notifications</span>'}<span class="act-text"><b>${esc(x.title)}</b><small>${esc(app.name)}${x.body ? ' · ' + esc(x.body) : ''}</small></span>`,
  });
});
$('#notif-clear').addEventListener('click', () => {
  $$('.notif').forEach((el, i) => setTimeout(() => el.classList.add('gone'), i * 30));
  setTimeout(() => invoke('notifs_dismiss', { id: null }), 220);
});
setInterval(() => { if (state === 'open' && currentTab === 'ctrl') renderNotifs(); }, 60000);

// =============================================================== minuteur
// Minuteur simple ou Pomodoro (25 min de travail / 5 min de pause).
let timer = store.get('timer', { total: 300000, remaining: 300000, end: 0, running: false, pomo: null });
const POMO = { focus: 25 * 60000, break: 5 * 60000 };
const fmtMs = ms => {
  const s = Math.ceil(ms / 1000);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  return h ? `${h}:${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}` : `${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
};
const timerLeft = () => (timer.running ? Math.max(0, timer.end - Date.now()) : timer.remaining);
function saveTimer() { store.set('timer', timer); }

function timerSet(ms, pomo = null) {
  timer = { total: ms, remaining: ms, end: 0, running: false, pomo };
  saveTimer();
  renderTimer();
}
function timerStart() {
  if (timer.remaining <= 0) timer.remaining = timer.total;
  timer.end = Date.now() + timer.remaining;
  timer.running = true;
  audio();
  saveTimer();
  renderTimer();
}
function timerPause() {
  timer.remaining = timerLeft();
  timer.running = false;
  saveTimer();
  renderTimer();
}
function timerToggle() { timer.running ? timerPause() : timerStart(); }
function timerReset() { timerSet(timer.pomo ? POMO.focus : timer.total, null); }
function startPomodoro() { timerSet(POMO.focus, 'focus'); timerStart(); }
function startTimer(min) { timerSet(min * 60000); timerStart(); }

function timerDone() {
  beep();
  if (timer.pomo) {
    const next = timer.pomo === 'focus' ? 'break' : 'focus';
    simpleActivity(next === 'break' ? 'self_improvement' : 'psychology', next === 'break' ? 'Pause !' : 'Au travail !',
      next === 'break' ? '5 minutes de repos' : '25 minutes de concentration', { ms: 6000, tab: 'ctrl' });
    timerSet(POMO[next], next);
    timerStart();
  } else {
    simpleActivity('alarm', 'Minuteur terminé', fmtMs(timer.total), { ms: 8000, tab: 'ctrl' });
    timer.running = false;
    timer.remaining = timer.total;
    saveTimer();
    renderTimer();
  }
}

const TCIRC = 2 * Math.PI * 54;
function renderTimer() {
  const left = timerLeft();
  $('.timer-time').textContent = fmtMs(left);
  $('.timer-phase').textContent = timer.pomo === 'focus' ? 'Concentration' : timer.pomo === 'break' ? 'Pause' : timer.running ? 'En cours' : left < timer.total ? 'En pause' : '';
  $('.timer-face .val').style.strokeDashoffset = TCIRC * (1 - left / Math.max(1, timer.total));
  $('#timer-go .ms').textContent = timer.running ? 'pause' : 'play_arrow';
  renderTimerTile();
  updateIndicators();
}
function renderTimerTile() {
  const active = timer.running || timer.remaining < timer.total;
  setTile('timer', timer.running, active ? `${fmtMs(timerLeft())}${timer.running ? '' : ' · en pause'}` : 'Arrêté');
}
setInterval(() => {
  if (!timer.running) return;
  if (timerLeft() <= 0) return timerDone();
  $('.ind-timer b').textContent = fmtMs(timerLeft());
  if (state === 'open' && currentTab === 'ctrl') renderTimer();
}, 250);

$$('.timer-presets button').forEach(b => b.addEventListener('click', () => timerSet(Number(b.dataset.min) * 60000)));
$('#timer-go').addEventListener('click', timerToggle);
$('#timer-reset').addEventListener('click', timerReset);
$('#timer-plus').addEventListener('click', () => adjustTimer(60000));
$('#timer-minus').addEventListener('click', () => adjustTimer(-60000));
$('#pomodoro').addEventListener('click', startPomodoro);
function adjustTimer(d) {
  const left = Math.max(60000, timerLeft() + d);
  timer.total = Math.max(timer.total + d, left);
  if (timer.running) timer.end = Date.now() + left; else timer.remaining = left;
  saveTimer();
  renderTimer();
}

let actx = null;
function audio() {
  try { actx = actx || new AudioContext(); actx.resume(); } catch {}
  return actx;
}
function beep() {
  const a = audio();
  if (!a) return;
  [0, 0.25, 0.5, 1.1, 1.35, 1.6].forEach(t => {
    const o = a.createOscillator();
    const g = a.createGain();
    o.frequency.value = 880;
    g.gain.setValueAtTime(0.0001, a.currentTime + t);
    g.gain.exponentialRampToValueAtTime(0.25, a.currentTime + t + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, a.currentTime + t + 0.18);
    o.connect(g).connect(a.destination);
    o.start(a.currentTime + t);
    o.stop(a.currentTime + t + 0.2);
  });
}

// --- indicateurs dans la pilule repliée
function updateIndicators() {
  const before = $$('.pill-mini .ind:not([hidden])').length;
  $('.ind-caf').hidden = !caffeine;
  $('.ind-dnd').hidden = !cfg.dnd;
  $('.ind-timer').hidden = !timer.running;
  $('.ind-timer b').textContent = fmtMs(timerLeft());
  if ($$('.pill-mini .ind:not([hidden])').length !== before && state === 'collapsed') applySize();
}

// =================================================================== apps
let apps = [];
let appSel = 0;
let appView = [];
let listItems = [];
let listSel = 0;
let listMode = 'apps';

const VARIANTS = [
  { id: 'tonalspot', label: 'Tonal Spot', C: SchemeTonalSpot },
  { id: 'vibrant', label: 'Vibrant', C: SchemeVibrant },
  { id: 'expressive', label: 'Expressive', C: SchemeExpressive },
  { id: 'fidelity', label: 'Fidélité', C: SchemeFidelity },
  { id: 'content', label: 'Contenu', C: SchemeContent },
  { id: 'rainbow', label: 'Arc-en-ciel', C: SchemeRainbow },
  { id: 'fruitsalad', label: 'Salade de fruits', C: SchemeFruitSalad },
  { id: 'neutral', label: 'Neutre', C: SchemeNeutral },
  { id: 'monochrome', label: 'Monochrome', C: SchemeMonochrome },
];

function commands(q) {
  const num = parseInt((q.match(/\d+/) || [])[0], 10);
  const list = [
    { icon: 'shuffle', title: "Fond d'écran au hasard", keys: 'fond ecran aleatoire hasard wallpaper random', run: () => invoke('wall_random') },
    ...VARIANTS.map(v => ({ icon: 'palette', title: `Variante de couleurs : ${v.label}`, keys: `variante couleurs theme palette ${v.id} ${v.label}`, run: () => setCfg({ variant: v.id }), stay: true })),
    { icon: 'dark_mode', title: 'Mode sombre', keys: 'mode sombre dark nuit theme', run: () => setCfg({ mode: 'dark' }), stay: true },
    { icon: 'light_mode', title: 'Mode clair', keys: 'mode clair light jour theme', run: () => setCfg({ mode: 'light' }), stay: true },
    { icon: 'brightness_auto', title: 'Mode automatique (suit Windows)', keys: 'mode auto automatique theme windows', run: () => setCfg({ mode: 'auto' }), stay: true },
    { icon: 'coffee', title: caffeine ? 'Désactiver la caféine' : 'Caféine : empêcher la mise en veille', keys: 'cafeine caffeine veille sleep reveille', run: toggleCaffeine },
    { icon: 'do_not_disturb_on', title: cfg.dnd ? 'Désactiver Ne pas déranger' : 'Activer Ne pas déranger', keys: 'ne pas deranger dnd silence notifications', run: toggleDnd },
    ...(num > 0
      ? [{ icon: 'timer', title: `Minuteur ${num} min`, keys: `minuteur timer ${num}`, run: () => startTimer(num) }]
      : [5, 10, 25].map(m => ({ icon: 'timer', title: `Minuteur ${m} min`, keys: `minuteur timer ${m}`, run: () => startTimer(m) }))),
    { icon: 'nest_eco_leaf', title: 'Pomodoro (25 / 5 min)', keys: 'pomodoro concentration focus travail', run: startPomodoro },
    ...(timer.running ? [{ icon: 'timer_off', title: 'Arrêter le minuteur', keys: 'arreter minuteur stop timer', run: timerReset }] : []),
    ...(net.radios.wifi !== null ? [{ icon: 'wifi', title: net.radios.wifi ? 'Couper le Wi-Fi' : 'Activer le Wi-Fi', keys: 'wifi wi-fi reseau', run: () => toggleRadio('wifi') }] : []),
    ...(net.radios.bluetooth !== null ? [{ icon: 'bluetooth', title: net.radios.bluetooth ? 'Couper le Bluetooth' : 'Activer le Bluetooth', keys: 'bluetooth bt', run: () => toggleRadio('bluetooth') }] : []),
    { icon: 'tune', title: 'Contrôles', keys: 'controles reglages rapides son melangeur sortie audio', run: () => open('ctrl'), stay: true },
    { icon: 'settings', title: 'Réglages', keys: 'reglages parametres settings options', run: () => open('settings'), stay: true },
    { icon: 'content_paste_off', title: "Vider l'historique du presse-papiers", keys: 'vider effacer presse-papiers clipboard', run: () => invoke('clips_clear') },
    { icon: 'notifications_off', title: 'Effacer les notifications', keys: 'effacer notifications', run: () => invoke('notifs_dismiss', { id: null }) },
    { icon: 'lock', title: 'Verrouiller', keys: 'verrouiller lock session', run: () => invoke('session_action', { action: 'lock' }) },
    { icon: 'bedtime', title: 'Mettre en veille', keys: 'veille sleep suspendre', run: () => invoke('session_action', { action: 'sleep' }) },
    { icon: 'logout', title: 'Se déconnecter', keys: 'deconnexion logout session', danger: true, run: () => invoke('session_action', { action: 'logout' }) },
    { icon: 'restart_alt', title: 'Redémarrer', keys: 'redemarrer restart reboot', danger: true, run: () => invoke('session_action', { action: 'restart' }) },
    { icon: 'power_settings_new', title: 'Éteindre', keys: 'eteindre shutdown arreter', danger: true, run: () => invoke('session_action', { action: 'shutdown' }) },
  ];
  const words = norm(q.replace(/\d+/g, '')).split(/\s+/).filter(Boolean);
  if (!words.length) return list;
  return list.filter(c => {
    const hay = norm(c.title + ' ' + c.keys);
    return words.every(w => hay.split(/[\s:()/]+/).some(h => h.startsWith(w)));
  });
}

function renderApps() {
  const raw = $('#q').value;
  const t = raw.trimStart();
  const pre = t[0];
  const grid = $('.app-grid');
  const listBox = $('.cmd-list');
  $('.search-icon').textContent = { '>': 'terminal', '=': 'calculate', ':': 'mood', '?': 'travel_explore' }[pre] || 'search';

  if (pre === '>' || pre === '=' || pre === ':' || pre === '?') {
    grid.hidden = true;
    listBox.hidden = false;
    const q = t.slice(1).trim();
    if (pre === ':') return renderEmoji(q);
    if (pre === '>') listItems = commands(q);
    else if (pre === '=') {
      const v = q ? calc(q) : null;
      listItems = v === null
        ? [{ icon: 'calculate', title: q ? 'Expression invalide' : 'Tapez un calcul', sub: '+ − × ÷ % ^ ( ) sqrt sin cos ln log pi', run: null }]
        : [{ icon: 'calculate', title: fmtNumber(v), sub: `${q} · Entrée pour copier`, run: () => invoke('clip_text', { text: String(v) }), stay: false, big: true }];
    } else {
      listItems = q
        ? [{ icon: 'travel_explore', title: `Rechercher « ${q} » sur le web`, sub: 'Ouvre le navigateur', run: () => invoke('open_url', { url: 'https://www.google.com/search?q=' + encodeURIComponent(q) }) }]
        : [{ icon: 'travel_explore', title: 'Tapez votre recherche', sub: '', run: null }];
    }
    listMode = 'list';
    renderList();
    return;
  }

  listBox.hidden = true;
  grid.hidden = false;
  listMode = 'apps';
  const q = norm(t.trim());
  appView = !q ? apps : apps
    .map(a => {
      const n = norm(a.name);
      const score = n.startsWith(q) ? 0 : n.split(/[\s\-_.]/).some(w => w.startsWith(q)) ? 1 : n.includes(q) ? 2 : 9;
      return { a, score };
    })
    .filter(x => x.score < 9)
    .sort((x, y) => x.score - y.score)
    .map(x => x.a);
  // un calcul tapé directement s'affiche en tête
  const mathRow = looksLikeMath(t.trim()) ? calc(t.trim()) : null;
  appSel = Math.min(appSel, Math.max(0, appView.length - 1));
  if (!apps.length) { grid.innerHTML = '<div class="empty">Chargement des applications…</div>'; return; }
  grid.innerHTML = '';
  if (mathRow !== null) {
    const m = document.createElement('button');
    m.className = 'calc-row';
    m.innerHTML = `<span class="ms">calculate</span><b>= ${fmtNumber(mathRow)}</b><small>Ctrl+Entrée pour copier</small>`;
    m.addEventListener('click', () => { invoke('clip_text', { text: String(mathRow) }); m.classList.add('done'); });
    grid.append(m);
  }
  if (!appView.length) { grid.insertAdjacentHTML('beforeend', '<div class="empty">Aucune application</div>'); return; }
  appView.forEach((a, i) => {
    const el = document.createElement('button');
    el.className = 'app' + (q && i === appSel ? ' sel' : '');
    el.title = a.name;
    el.innerHTML = a.icon ? `<img src="${a.icon}" alt="">` : `<div class="ph">${esc(a.name[0] || '?')}</div>`;
    const label = document.createElement('span');
    label.textContent = a.name;
    el.append(label);
    el.addEventListener('click', () => launch(a));
    grid.append(el);
  });
}

function renderList() {
  const box = $('.cmd-list');
  box.className = 'cmd-list';
  box.innerHTML = '';
  listSel = Math.min(listSel, Math.max(0, listItems.length - 1));
  if (!listItems.length) { box.innerHTML = '<div class="empty">Aucune commande</div>'; return; }
  listItems.forEach((c, i) => {
    const el = document.createElement('button');
    el.className = 'cmd' + (i === listSel ? ' sel' : '') + (c.danger ? ' danger' : '') + (c.big ? ' big' : '') + (c.run ? '' : ' inert');
    el.innerHTML = `<span class="ms">${c.icon}</span><span class="cmd-text"><b></b>${c.sub ? '<small></small>' : ''}</span>`;
    el.querySelector('b').textContent = c.title;
    if (c.sub) el.querySelector('small').textContent = c.sub;
    el.addEventListener('click', () => runItem(i));
    box.append(el);
  });
}

function runItem(i) {
  const c = listItems[i];
  if (!c || !c.run) return;
  if (c.danger && !c.armed) {
    listItems.forEach(x => (x.armed = false));
    c.armed = true;
    const el = $$('.cmd')[i];
    el.classList.add('armed');
    el.querySelector('.cmd-text').insertAdjacentHTML('beforeend', '<small>Encore une fois pour confirmer</small>');
    return;
  }
  c.run();
  if (!c.stay) {
    $('#q').value = '';
    setState('collapsed');
  } else {
    $('#q').value = '';
    renderApps();
  }
}

function renderEmoji(q) {
  listMode = 'emoji';
  const box = $('.cmd-list');
  box.className = 'cmd-list emoji-grid';
  listItems = searchEmoji(q).slice(0, 200);
  listSel = Math.min(listSel, Math.max(0, listItems.length - 1));
  box.innerHTML = listItems.length ? '' : '<div class="empty">Aucun emoji</div>';
  listItems.forEach((x, i) => {
    const el = document.createElement('button');
    el.className = 'emo' + (i === listSel ? ' sel' : '');
    el.textContent = x.e;
    el.title = x.words.split(' ').slice(0, 3).join(' ');
    el.addEventListener('click', () => pickEmoji(x.e, el));
    box.append(el);
  });
}
function pickEmoji(e, el) {
  invoke('clip_text', { text: e });
  el?.classList.add('done');
  setTimeout(() => { $('#q').value = ''; setState('collapsed'); }, 250);
}

function launch(a) {
  invoke('app_launch', { id: a.id });
  $('#q').value = '';
  setState('collapsed');
}
$('#q').addEventListener('input', () => { appSel = 0; listSel = 0; renderApps(); });
$('#q').addEventListener('keydown', e => {
  if (listMode === 'list' || listMode === 'emoji') {
    const cols = listMode === 'emoji' ? 12 : 1;
    const moves = listMode === 'emoji'
      ? { ArrowRight: 1, ArrowLeft: -1, ArrowDown: cols, ArrowUp: -cols }
      : { ArrowDown: 1, ArrowUp: -1 };
    if (e.key in moves) {
      e.preventDefault();
      listSel = Math.max(0, Math.min(listItems.length - 1, listSel + moves[e.key]));
      $$('.cmd-list > button').forEach((el, i) => el.classList.toggle('sel', i === listSel));
      $$('.cmd-list > button')[listSel]?.scrollIntoView({ block: 'nearest' });
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (listMode === 'emoji') { if (listItems[listSel]) pickEmoji(listItems[listSel].e, $$('.emo')[listSel]); }
      else runItem(listSel);
    }
    return;
  }
  const cols = 7;
  const moves = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: cols, ArrowUp: -cols };
  if (e.key in moves) {
    e.preventDefault();
    appSel = Math.max(0, Math.min(appView.length - 1, appSel + moves[e.key]));
    $$('.app').forEach((el, i) => el.classList.toggle('sel', i === appSel));
    $$('.app')[appSel]?.scrollIntoView({ block: 'nearest' });
  } else if (e.key === 'Enter' && e.ctrlKey && $('.calc-row')) {
    $('.calc-row').click();
  } else if (e.key === 'Enter' && appView[appSel]) {
    launch(appView[appSel]);
  }
});
listen('apps', ({ payload }) => { apps = payload; if (currentTab === 'apps') renderApps(); renderNotifs(); });
invoke('apps_get').then(l => { if (l.length) { apps = l; renderNotifs(); } });

// ========================================================= presse-papiers
function renderClips(list) {
  $('.clip-count').textContent = list.length ? `${list.length} élément${list.length > 1 ? 's' : ''}` : 'Historique vide';
  const box = $('.clip-list');
  box.innerHTML = list.length ? '' : '<div class="empty">Copiez du texte ou une image : ils apparaîtront ici.</div>';
  list.forEach(c => {
    const el = document.createElement('button');
    el.className = 'clip' + (c.text === null || c.text === undefined ? ' img' : '');
    if (c.text !== null && c.text !== undefined) {
      const p = document.createElement('p');
      p.textContent = c.text.length > 600 ? c.text.slice(0, 600) + '…' : c.text;
      el.append(p);
    } else {
      el.innerHTML = `<img src="${c.thumb}" alt=""><small>${c.w} × ${c.h}</small>`;
    }
    el.insertAdjacentHTML('beforeend', '<span class="ms">check</span>');
    el.addEventListener('click', () => {
      invoke('clip_copy', { id: c.id });
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

$$('.seg button[data-src]').forEach(b => b.addEventListener('click', () => {
  if (b.dataset.src === wallSrc) return;
  wallSrc = b.dataset.src;
  $$('.seg button[data-src]').forEach(x => x.classList.toggle('on', x === b));
  loadWalls();
}));
$('#wall-refresh').addEventListener('click', () => loadWalls(true));
$('#wall-folder').addEventListener('click', () => { invoke('walls_open_folder'); setState('collapsed'); });
$('#wall-random').addEventListener('click', async () => {
  const b = $('#wall-random');
  b.disabled = true;
  await invoke('wall_random');
  b.disabled = false;
});

// fond actif (WE s'il tourne, sinon Windows) -> palette
async function syncWall() {
  we = await invoke('we_state');
  $('.page[data-page="walls"] .seg').hidden = !we.installed;
  const w = await invoke('wall_current');
  if (w && w.thumb !== currentThumb) {
    currentThumb = w.thumb;
    themeFrom(w.thumb);
  }
  if (wallsLoaded) {
    // le fond a pu changer ailleurs (rotation, WE) : on relit la liste Windows
    if (wallSrc === 'win' && wallCache.win) wallCache.win.forEach(x => (x.cur = w && samePath(x.path, w.path)));
    wallNote();
    if (wallCache[wallSrc]) renderWalls();
  }
}
// changement fait dans Wallpaper Engine, rotation, ou WE lancé / quitté
listen('wall-changed', syncWall);
(async () => {
  await syncWall();
  if (we.installed && we.running) {
    wallSrc = 'we';
    $$('.seg button[data-src]').forEach(x => x.classList.toggle('on', x.dataset.src === 'we'));
    if (wallsLoaded) loadWalls();
  }
})();

// ================================================================ réglages
const autostart = $('#set-autostart');
async function loadSettings() {
  const s = await invoke('settings_get');
  autostart.checked = s.autostart;
  renderMonitors(s.monitors, s.monitor);
  Object.assign(cfg, s);
  renderSettings();
}
function renderMonitors(list, chosen) {
  const box = $('.mon-list');
  box.innerHTML = '';
  // l'écran choisi peut être débranché : on retombe alors sur « Automatique »
  const cur = list.some(m => m.id === chosen) ? chosen : null;
  const primary = list.find(m => m.primary);
  const items = [{ id: null, label: 'Automatique', sub: primary ? `Écran principal (${primary.label})` : 'Écran principal', icon: 'auto_awesome' }]
    .concat(list.map(m => ({
      id: m.id, label: m.label, icon: 'monitor',
      sub: `${m.width} × ${m.height}${m.primary ? ' · principal' : ''}`,
    })));
  items.forEach(m => {
    const el = document.createElement('button');
    el.className = 'mon' + (m.id === cur ? ' on' : '');
    el.innerHTML = `<span class="ms">${m.icon}</span><b></b><small></small>`;
    el.querySelector('b').textContent = m.label;
    el.querySelector('small').textContent = m.sub;
    el.addEventListener('click', async () => {
      $$('.mon').forEach(x => x.classList.toggle('on', x === el));
      await invoke('settings_monitor', { id: m.id });
    });
    box.append(el);
  });
}
autostart.addEventListener('change', async () => {
  autostart.disabled = true;
  autostart.checked = await invoke('settings_autostart', { on: autostart.checked });
  autostart.disabled = false;
});

function renderSettings() {
  $$('#set-mode button').forEach(b => b.classList.toggle('on', b.dataset.mode === cfg.mode));
  $('#set-win-accent').checked = cfg.win_accent;
  $('#set-win-mode').checked = cfg.win_mode;
  $('#set-notif').checked = cfg.notif_popups;
  $('#set-osd').checked = cfg.osd;
  $$('#set-rotate button').forEach(b => b.classList.toggle('on', Number(b.dataset.v) === cfg.rotate_min));
  $('.city-cur').textContent = cfg.city ? cfg.city.name : 'Aucune ville choisie';
  renderVariants();
  renderIcals();
}

function renderVariants() {
  const box = $('.variant-list');
  box.innerHTML = '';
  const src = sourceArgb ?? 0xff6750a4;
  const dark = isDark();
  for (const v of VARIANTS) {
    const s = new v.C(Hct.fromInt(src), dark, 0);
    const el = document.createElement('button');
    el.className = 'variant' + (v.id === cfg.variant ? ' on' : '');
    const dots = ['primary', 'secondary', 'tertiary'].map(r => `<i style="background:${hexFromArgb(MDC[r].getArgb(s))}"></i>`).join('');
    el.innerHTML = `<span class="dots" style="background:${hexFromArgb(MDC.surfaceContainerHigh.getArgb(s))}">${dots}</span><small></small>`;
    el.querySelector('small').textContent = v.label;
    el.addEventListener('click', () => setCfg({ variant: v.id }));
    box.append(el);
  }
}
$$('#set-mode button').forEach(b => b.addEventListener('click', () => setCfg({ mode: b.dataset.mode })));
$('#set-win-accent').addEventListener('change', e => {
  if (e.target.checked) store.set('winAccent', null); // force la réapplication
  setCfg({ win_accent: e.target.checked });
});
$('#set-win-mode').addEventListener('change', e => setCfg({ win_mode: e.target.checked }));
$('#set-notif').addEventListener('change', e => setCfg({ notif_popups: e.target.checked }));
$('#set-osd').addEventListener('change', e => setCfg({ osd: e.target.checked }));
$$('#set-rotate button').forEach(b => b.addEventListener('click', () => setCfg({ rotate_min: Number(b.dataset.v) })));

// --- ville (géocodage Open-Meteo)
let cityTimer = null;
$('#city-q').addEventListener('input', () => {
  clearTimeout(cityTimer);
  cityTimer = setTimeout(searchCity, 350);
});
$('#city-q').addEventListener('focus', () => invoke('grab_focus'));
async function searchCity() {
  const q = $('#city-q').value.trim();
  const box = $('.city-list');
  if (q.length < 2) { box.innerHTML = ''; return; }
  try {
    const j = JSON.parse(await invoke('http_get', { url: `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(q)}&count=6&language=fr` }));
    box.innerHTML = (j.results || []).length ? '' : '<div class="empty small">Aucune ville trouvée</div>';
    for (const r of j.results || []) {
      const el = document.createElement('button');
      el.className = 'city';
      el.innerHTML = '<span class="ms">location_on</span><b></b><small></small>';
      el.querySelector('b').textContent = r.name;
      el.querySelector('small').textContent = [r.admin1, r.country].filter(Boolean).join(', ');
      el.addEventListener('click', async () => {
        box.innerHTML = '';
        $('#city-q').value = '';
        await setCfg({ city: { name: r.name, lat: r.latitude, lon: r.longitude } });
        refreshWeather();
      });
      box.append(el);
    }
  } catch (e) {
    box.innerHTML = `<div class="empty small">Recherche impossible (${esc(e)})</div>`;
  }
}

// --- agendas iCal
function renderIcals() {
  const box = $('.ical-list');
  box.innerHTML = '';
  cfg.icals.forEach((u, i) => {
    const el = document.createElement('div');
    el.className = 'ical';
    el.innerHTML = '<span class="ms">calendar_month</span><span class="ical-url"></span><button class="icon-btn small" title="Retirer"><span class="ms">close</span></button>';
    // l'adresse est secrète : on n'en montre que le début
    el.querySelector('.ical-url').textContent = u.replace(/^(https?:\/\/[^/]+\/).{0,}$/, '$1…') + (u.length > 40 ? '  ' + u.slice(-12) : '');
    el.querySelector('button').addEventListener('click', async () => {
      await setCfg({ icals: cfg.icals.filter((_, k) => k !== i) });
      refreshEvents(true);
    });
    box.append(el);
  });
}
$('.ical-add').addEventListener('submit', async e => {
  e.preventDefault();
  const input = $('#ical-url');
  const u = input.value.trim();
  if (!/^(https|webcal):\/\//i.test(u)) { input.classList.add('bad'); setTimeout(() => input.classList.remove('bad'), 800); return; }
  input.value = '';
  await setCfg({ icals: [...cfg.icals, u] });
  refreshEvents(true);
});
$('#ical-url').addEventListener('focus', () => invoke('grab_focus'));

// les réglages ont changé (ici ou par une commande)
function onSettings() {
  applyTheme();
  updateIndicators();
  renderTiles();
  renderNotifs();
  if (state === 'open' && currentTab === 'settings') renderSettings();
}
listen('settings', ({ payload }) => {
  const icalsChanged = JSON.stringify(payload.icals) !== JSON.stringify(cfg.icals);
  const cityChanged = JSON.stringify(payload.city) !== JSON.stringify(cfg.city);
  Object.assign(cfg, payload);
  onSettings();
  if (icalsChanged) refreshEvents(true);
  if (cityChanged) refreshWeather();
});

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
let sourceArgb = store.get('source', null);

function isDark() {
  return cfg.mode === 'auto' ? !winLight : cfg.mode !== 'light';
}
function applyPalette(p) {
  for (const [k, v] of Object.entries(p)) document.documentElement.style.setProperty('--' + k, v);
  vizColor = p.primary || vizColor;
}
function applyTheme() {
  const dark = isDark();
  document.documentElement.classList.toggle('light', !dark);
  if (sourceArgb === null) return;
  const V = VARIANTS.find(v => v.id === cfg.variant) || VARIANTS[0];
  const scheme = new V.C(Hct.fromInt(sourceArgb), dark, 0);
  const p = {};
  for (const [css, role] of Object.entries(ROLES)) p[css] = hexFromArgb(MDC[role].getArgb(scheme));
  applyPalette(p);
  store.set('palette', p);
  syncWindows(scheme, dark);
}
function syncWindows(scheme, dark) {
  if (cfg.win_mode && cfg.mode !== 'auto' && winLight === dark) {
    winLight = !dark;
    invoke('win_theme_apply', { light: !dark, palette: null });
  }
  if (cfg.win_accent) {
    // 8 teintes de la plus claire à la plus foncée ; la 4e est l'accent
    const pal = scheme.primaryPalette;
    const list = [90, 78, 62, 50, 40, 28, 14].map(t => pal.tone(t) & 0xffffff);
    list.push(scheme.tertiaryPalette.tone(55) & 0xffffff);
    const key = list.join(',');
    if (key !== store.get('winAccent')) {
      store.set('winAccent', key);
      invoke('win_theme_apply', { light: null, palette: list });
    }
  }
}
async function themeFrom(src) {
  try {
    const img = new Image();
    img.src = src;
    await img.decode();
    sourceArgb = await sourceColorFromImage(img);
    store.set('source', sourceArgb);
    applyTheme();
    if (state === 'open' && currentTab === 'settings') renderVariants();
  } catch (e) {
    console.warn('thème', e);
  }
}
listen('win-theme', ({ payload }) => {
  winLight = payload;
  if (cfg.mode === 'auto') { applyTheme(); renderTiles(); }
});

// ============================================================== démarrage
const savedPalette = store.get('palette');
if (savedPalette) applyPalette(savedPalette);
tickClock();
renderCal();
showTab('home');
applySize();
renderTimer();
(async () => {
  winLight = await invoke('win_theme_get');
  const s = await invoke('settings_get');
  Object.assign(cfg, s);
  caffeine = await invoke('caffeine_get');
  onSettings();
  refreshWeather();
  refreshEvents(true);
})();
invoke('startup_tab').then(t => { if (t) { pinned = true; open(t); } });
