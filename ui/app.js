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
  variant: 'tonalspot', mode: 'dark', win_accent: false, win_mode: false, island_bg: 'solid', city: null, icals: [],
  rotate_min: 0, notif_popups: true, dnd: false, osd: true, bar: false, hide_taskbar: true,
  bar_islands: true, bar_tasks: false, bar_autohide: true, win_key: false,
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
const BAR_H = 30;
let state = 'collapsed';
let hovered = false;
let pinned = false; // ouvert au clavier : ne se referme pas en sortant la souris
let leaveTimer = null;
let hasMedia = false;
let fullscreen = false;
let barPeek = false; // barre affichée (masquage automatique)
let atTop = false;   // souris dans la bande du haut de l'écran
let barTimer = null;
const barAuto = () => !!(cfg.bar && cfg.bar_autohide);
const barVisible = () => !!cfg.bar && !fullscreen && (!cfg.bar_autohide || barPeek);
const barDocked = () => barVisible() && !cfg.bar_islands;
let act = null;
let actTimer = null;
let weather = null;

function sizeFor(s) {
  if (s === 'open') return big ? bigSize() : OPEN;
  if (s === 'peek') return hasMedia ? { w: 420, h: 66 } : { w: weather ? 320 : 250, h: 50 };
  if (act) return act.size;
  let w = hasMedia ? 200 : 132;
  w += $$('.pill-mini .ind:not(.ind-timer):not([hidden])').length * 24;
  if (!$('.ind-timer').hidden) w += 70;
  return { w, h: 30 };
}

// avec la barre (pleine et affichée), les coins concaves ne poussent que
// sous son bord
const earFor = h => (barDocked() ? Math.max(0, Math.min(EAR, h - BAR_H)) : EAR);

function applySize() {
  const { w, h } = sizeFor(state);
  island.style.width = w + 'px';
  island.style.height = h + 'px';
  island.style.setProperty('--ear', earFor(h) + 'px');
  island.classList.toggle('act', !!act && state === 'collapsed');
  reportHit();
}

function reportHit() {
  const { w, h } = sizeFor(state);
  const ear = earFor(h);
  const x = (innerWidth - w) / 2 - ear;
  // l'îlot d'abord (survol), puis la barre ; un peu de marge sous l'îlot
  // replié pour l'attraper facilement
  const rects = [{ x, y: 0, w: w + ear * 2, h: h + (state === 'collapsed' ? 6 : 2) }];
  if (barVisible()) {
    if (!cfg.bar_islands) rects.push({ x: 0, y: 0, w: innerWidth, h: BAR_H });
    // îlots séparés : les clics passent entre eux
    else for (const el of $$('.bar-side > *')) {
      const r = el.getBoundingClientRect();
      if (r.width) rects.push({ x: r.left - 2, y: 0, w: r.width + 4, h: BAR_H });
    }
    if (pvKey) {
      const r = $('#task-preview').getBoundingClientRect();
      rects.push({ x: r.left, y: r.top, w: r.width, h: r.height });
    }
  }
  // masquage auto : une bande au bord de l'écran affiche la barre, qui reste
  // tant que la souris est dessus
  const top = barAuto() && !fullscreen ? (barPeek ? BAR_H + 8 : 2) : 0;
  invoke('set_hit', { rects, top });
}

function setState(s) {
  if (s === state) return;
  if (state === 'open') invoke('release_focus');
  state = s;
  island.classList.remove('collapsed', 'peek', 'open');
  island.classList.add(s);
  if (s !== 'open') { pinned = false; closeSheets(); if (!atTop) hideBarLater(); }
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
  } else if (state === 'open' && !pinned && !locked) {
    leaveTimer = setTimeout(() => setState('collapsed'), 450);
  }
});
listen('fullscreen', ({ payload }) => {
  fullscreen = payload;
  island.classList.toggle('hidden', payload);
  refreshBar();
  if (payload) { setState('collapsed'); endActivity(); }
  updateViz();
});
listen('blur', () => {
  if (state === 'open' && !hovered && !locked) setState('collapsed');
});

// ------------------------------------------- agrandir / verrouiller le panneau
// enregistré dans %LOCALAPPDATA%\Ilot\layout.json : { big, locked }
let big = false;
let locked = false; // verrouillé : ne se replie pas quand la souris sort
// panneau agrandi : presque tout l'écran, sans dépasser 1400×860
const bigSize = () => ({
  w: Math.max(OPEN.w, Math.min(1400, screen.width - 160)),
  h: Math.max(OPEN.h, Math.min(860, screen.height - 120)),
});
const WIN_PAD = { w: 60, h: 60 }; // marge de la fenêtre autour du panneau (oreilles)
function setBig(on, save = true) {
  big = on;
  const s = sizeFor('open');
  // la fenêtre grandit avant le panneau, et rétrécit après l'animation
  if (on) invoke('win_resize', { w: s.w + WIN_PAD.w, h: s.h + WIN_PAD.h });
  else setTimeout(() => { if (!big) invoke('win_resize', { w: OPEN.w + WIN_PAD.w, h: OPEN.h + WIN_PAD.h }); }, 550);
  island.style.setProperty('--open-w', s.w + 'px');
  island.style.setProperty('--open-h', s.h + 'px');
  island.classList.toggle('big', on);
  const b = $('[data-tool="big"]');
  b.classList.toggle('on', on);
  b.title = on ? 'Réduire' : 'Agrandir';
  b.querySelector('.ms').textContent = on ? 'close_fullscreen' : 'open_in_full';
  applySize();
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
// Touche Windows remappée (F24) : quand l'îlot a le clavier, elle arrive ici
// au lieu de passer par le hook ; seule, elle referme l'îlot
let winTap = false;
addEventListener('keydown', e => {
  if (e.key === 'F24') { if (!e.repeat) winTap = true; e.preventDefault(); }
  else winTap = false;
}, true);
addEventListener('keyup', e => {
  if (e.key !== 'F24' || !winTap) return;
  winTap = false;
  if (state === 'open') close();
}, true);
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
  if (o.kind === 'volume') showBarVolume(o.value, o.muted);
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
// largeur des onglets changée (police d'icônes chargée, libellé actif) : on recale
new ResizeObserver(moveIndicator).observe($('#tabs'));

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
  // onglets PC et Tâches : rafraîchis tant qu'ils sont affichés
  clearInterval(pcTimer);
  if (tab === 'pc') { refreshPc(); pcTimer = setInterval(() => state === 'open' && currentTab === 'pc' ? refreshPc() : clearInterval(pcTimer), 3000); }
  clearInterval(taskTimer);
  if (tab === 'tasks') { refreshTasks(); taskTimer = setInterval(() => state === 'open' && currentTab === 'tasks' ? refreshTasks() : clearInterval(taskTimer), 2000); }
}

// ================================================================ horloge
const fmtDate = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
const fmtShort = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
const fmtHM = new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit' });
const fmtBar = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
function tickClock() {
  const d = new Date();
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  $('.mini-clock').textContent = $('.peek-clock').textContent = `${hh}:${mm}`;
  $('.big-clock .hh').textContent = hh;
  $('.big-clock .mm').textContent = mm;
  $('.big-date').textContent = fmtDate.format(d);
  $('.peek-date').textContent = fmtShort.format(d);
  const day = fmtBar.format(d);
  $('.bar-date').textContent = day[0].toUpperCase() + day.slice(1);
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
    const note = calNotes[noteKey(day)];
    el.className = `d${out ? ' out' : ''}${today ? ' today' : ''}${we ? ' we' : ''}${busy.has(dayKey(day)) ? ' ev' : ''}${note ? ' noted' : ''}`;
    el.textContent = day.getDate();
    if (note) el.title = note;
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
  noteDay = noteKey(from);
  calNote.value = calNotes[noteDay] || '';
  $('.cal-card').classList.add('day');
}
$('#cal-back').addEventListener('click', () => $('.cal-card').classList.remove('day'));

// --- notes par date, dans %LOCALAPPDATA%\Ilot\calnotes.json : { "AAAA-MM-JJ": "texte" }
let calNotes = {};
let noteDay = null;
const noteKey = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const calNote = $('.cal-note');
calNote.addEventListener('focus', () => { pinned = true; });
calNote.addEventListener('input', () => {
  if (calNote.value.trim()) calNotes[noteDay] = calNote.value; else delete calNotes[noteDay];
  invoke('store_set', { key: 'calnotes', value: calNotes });
  renderCal();
});
invoke('store_get', { key: 'calnotes' }).then(n => { if (n && typeof n === 'object') { calNotes = n; renderCal(); } });
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
  barResources(r);
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
listen('net', ({ payload }) => { net = payload; renderTiles(); renderBarNet(); });
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
  const badge = $('[data-tab="ctrl"] .badge');
  badge.hidden = !n;
  badge.textContent = n > 9 ? '9+' : n;
  const bell = $('.bar-notif');
  bell.classList.toggle('has', !!n && !cfg.dnd);
  bell.querySelector('.ms').textContent = cfg.dnd ? 'do_not_disturb_on' : n ? 'notifications' : 'notifications_none';
  bell.querySelector('b').textContent = n && !cfg.dnd ? (n > 9 ? '9+' : n) : '';
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
  renderFolders();
  const q = norm(t.trim());
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
  // un calcul tapé directement s'affiche en tête
  const mathRow = looksLikeMath(t.trim()) ? calc(t.trim()) : null;
  appSel = Math.min(appSel, Math.max(0, appView.length - 1));
  grid.classList.toggle('games', inGames);
  if (inGames) return renderGames(grid, q);
  if (!apps.length) { grid.innerHTML = '<div class="empty">Chargement des applications…</div>'; return; }
  grid.innerHTML = '';
  if (mathRow !== null) {
    const m = document.createElement('button');
    m.className = 'calc-row';
    m.innerHTML = `<span class="ms">calculate</span><b>= ${fmtNumber(mathRow)}</b><small>Ctrl+Entrée pour copier</small>`;
    m.addEventListener('click', () => { invoke('clip_text', { text: String(mathRow) }); m.classList.add('done'); });
    grid.append(m);
  }
  if (!appView.length) {
    grid.insertAdjacentHTML('beforeend', folder && !q
      ? '<div class="empty">Dossier vide : glisse une appli sur le dossier, dépose un fichier ici, ou clic droit sur une application.</div>'
      : '<div class="empty">Aucune application</div>');
    return;
  }
  appView.forEach((a, i) => {
    const el = document.createElement('button');
    el.className = 'app' + (q && i === appSel ? ' sel' : '') + (a.missing ? ' missing' : '');
    el.title = (a.file ? a.file : a.name) + (a.added ? `\nAjoutée le ${fmtAdded.format(a.added)}` : '');
    el.innerHTML = a.icon ? `<img src="${a.icon}" alt="">` : `<div class="ph">${esc(a.name[0] || '?')}</div>`;
    const label = document.createElement('span');
    label.textContent = a.name;
    el.append(label);
    el.addEventListener('click', () => { if (!dragJustEnded) launch(a); });
    el.addEventListener('contextmenu', e => { e.preventDefault(); appMenu(a, e); });
    el.addEventListener('pointerdown', e => dragStart(a, el, e));
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
  if (a.file) invoke('file_open', { path: a.file });
  else if (a.source) invoke('game_launch', { id: a.id });
  else invoke('app_launch', { id: a.id });
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
  // nombre de colonnes réel (varie avec le panneau agrandi et le Launcher)
  const cols = getComputedStyle($('.app-grid')).gridTemplateColumns.split(' ').length;
  const moves = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: cols, ArrowUp: -cols };
  if (e.key in moves) {
    e.preventDefault();
    appSel = Math.max(0, Math.min(appView.length - 1, appSel + moves[e.key]));
    const tiles = $$('.app-grid > .app, .app-grid > .game');
    tiles.forEach((el, i) => el.classList.toggle('sel', i === appSel));
    tiles[appSel]?.scrollIntoView({ block: 'nearest' });
  } else if (e.key === 'Enter' && e.ctrlKey && $('.calc-row')) {
    $('.calc-row').click();
  } else if (e.key === 'Enter' && appView[appSel]) {
    launch(appView[appSel]);
  }
});
listen('apps', ({ payload }) => { apps = payload; seedGames(); if (currentTab === 'apps') renderApps(); renderNotifs(); });
invoke('apps_get').then(l => { if (l.length) { apps = l; seedGames(); renderNotifs(); } });

// ================================================== dossiers d'apps et Launcher
// Launcher de jeux (src/games.rs), dossiers, glisser-déposer, tri, menu contextuel
let games = [];
const GAMES = '@games'; // pseudo-dossier « Launcher de jeux »
const SOURCE = { steam: 'Steam', epic: 'Epic', ubisoft: 'Ubisoft', gog: 'GOG' };

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
listen('tauri://drag-enter', () => {
  // déposer sur l'îlot l'ouvre sur les applis
  if (state !== 'open' || currentTab !== 'apps') { fileDragOpened = true; pinned = true; open('apps'); }
  island.classList.add('filedrag');
});
const dropPoint = pos => ({ clientX: pos.x / devicePixelRatio, clientY: pos.y / devicePixelRatio });
listen('tauri://drag-over', ({ payload }) => {
  const p = dropPoint(payload.position);
  markDrop(chipAt(p.clientX, p.clientY));
});
listen('tauri://drag-leave', () => {
  island.classList.remove('filedrag');
  markDrop(null);
  if (fileDragOpened) { fileDragOpened = false; close(); }
});
listen('tauri://drag-drop', ({ payload }) => {
  island.classList.remove('filedrag');
  markDrop(null);
  fileDragOpened = false;
  const paths = payload.paths || [];
  if (!paths.length) return;
  const p = dropPoint(payload.position);
  const chip = chipAt(p.clientX, p.clientY);
  const target = findFolder(chip ? chip.dataset.id : folders.sel);
  if (target) return addFiles(target, paths);
  // déposé hors d'un dossier : demander lequel
  const what = paths.length > 1 ? `${paths.length} éléments` : paths[0].split('\\').pop();
  showCtx(p, box => {
    ctxTitle(box, `Ranger ${what} dans…`);
    ctxItem(box, 'stadia_controller', 'Launcher de jeux', () => { hideCtx(); addFiles(launcherFolder(), paths); });
    folders.list.forEach(f => ctxItem(box, folderIcon(f.name), f.name, () => { hideCtx(); addFiles(f, paths); }));
    ctxItem(box, 'create_new_folder', 'Nouveau dossier…', () => askName(p, 'Nouveau dossier', '', name => addFiles(newFolder(name), paths)));
  });
});

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

// =================================================================== mail
// comptes IMAP gérés côté Rust (src/mail.rs) ; vérification toutes les 2 min
let inbox = { accounts: [], mails: [] };
let mailAcc = ''; // filtre : '' = tous les comptes
let mailOpen = null; // message affiché dans le lecteur
let mailBusy = false;
const fmtHour = new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit' });
const fmtMailDay = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'short' });
function mailDate(ts) {
  const d = new Date(ts * 1000);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) return fmtHour.format(d);
  const y = new Date(now); y.setDate(now.getDate() - 1);
  if (d.toDateString() === y.toDateString()) return 'Hier';
  return fmtMailDay.format(d);
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
  const badge = $('[data-tab="mail"] .badge');
  badge.hidden = !unread;
  badge.textContent = unread > 99 ? '99+' : unread;
  $('.ind-mail').hidden = !unread;
  if (state === 'collapsed') applySize();
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

// ===================================================== média : playlists
// --- panneaux latéraux (playlists, apparence)
function togglePanel(id) {
  const p = $(id);
  const show = p.hidden;
  $$('.side-panel').forEach(x => (x.hidden = true));
  p.hidden = !show;
}
$$('.side-panel [data-close]').forEach(b => b.addEventListener('click', () => (b.closest('.side-panel').hidden = true)));
$('#mp-lists').addEventListener('click', () => togglePanel('#pl-panel'));
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
  if (document.activeElement?.closest?.('.dc-people')) return;
  renderDiscord();
});
invoke('discord_get').then(s => { dc = s; renderDiscord(); });

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


let pcTimer = null;
function refreshPc() {
  renderHardware();
  refreshPower();
  invoke('app_volume_get', { app: 'discord' }).then(v => { showDcVolume(v); renderDiscord(); });
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
const HUES = { cpu: 210, mem: 275, disk: 135, net: 30 };
function heat(el, frac, kind) {
  const f = Math.max(0, Math.min(1, frac || 0));
  const hue = f >= 0.75 ? 0 : HUES[kind] ?? 50;
  el.style.setProperty('--heat', `hsl(${hue} 85% 55% / ${0.1 + 0.6 * Math.sqrt(f)})`);
  el.style.setProperty('--bar', `hsl(${hue} 90% 60%)`);
  el.style.setProperty('--fill', Math.max(f * 100, f > 0.002 ? 3 : 0) + '%');
  el.classList.toggle('hot', f >= 0.5);
}
async function refreshTasks() {
  if (taskBusy) return;
  taskBusy = true;
  try {
    const r = await invoke('tasks_get');
    tasks = r.list;
    netRate = { down: r.net_down, up: r.net_up };
  } finally { taskBusy = false; }
  renderTasks();
}
function renderTasks() {
  const q = norm($('#task-q').value.trim());
  const by = {
    cpu: (x, y) => y.cpu - x.cpu || y.mem - x.mem,
    mem: (x, y) => y.mem - x.mem,
    disk: (x, y) => y.disk - x.disk || y.cpu - x.cpu,
    net: (x, y) => y.net - x.net || y.cpu - x.cpu,
    name: (x, y) => x.name.localeCompare(y.name, 'fr'),
  }[taskSort];
  const list = tasks.filter(t => !q || norm(t.name).includes(q)).sort(by);
  const procs = tasks.reduce((n, t) => n + t.count, 0);
  const cpu = Math.min(100, tasks.reduce((n, t) => n + t.cpu, 0));
  const mem = tasks.reduce((n, t) => n + t.mem, 0);
  const disk = tasks.reduce((n, t) => n + t.disk, 0);
  const memTotal = lastSys?.mem_total || 16 * 1024 ** 3;
  $('.task-sum').textContent = `${procs} processus`;
  // en-têtes : totaux colorés, comme le Gestionnaire des tâches
  const head = (k, frac, text) => {
    const h = $(`.task-headrow [data-h="${k}"]`);
    heat(h, frac, k);
    h.querySelector('b').textContent = text;
  };
  head('cpu', cpu / 100, Math.round(cpu) + ' %');
  head('mem', (lastSys ? lastSys.mem_used : mem) / memTotal, Math.round((lastSys ? lastSys.mem_used : mem) / memTotal * 100) + ' %');
  head('disk', disk / DISK_FULL, fmtRate(disk));
  head('net', (netRate.down + netRate.up) / NET_FULL, `↓${fmtNet(netRate.down)} ↑${fmtNet(netRate.up)}`);
  const box = $('.task-list');
  if (!list.length) { box.innerHTML = '<div class="empty">Aucun processus</div>'; return; }
  box.innerHTML = '';
  list.forEach(t => {
    const row = document.createElement('div');
    row.className = 'task-row task';
    row.innerHTML = t.icon ? `<img src="${t.icon}" alt="">` : '<span class="ms">memory</span>';
    const name = document.createElement('span');
    name.className = 'task-name';
    name.textContent = t.name;
    if (t.count > 1) name.insertAdjacentHTML('beforeend', ` <i>(${t.count})</i>`);
    row.append(name);
    [
      ['cpu', t.cpu / 100, t.cpu.toFixed(1) + ' %'],
      ['mem', t.mem / memTotal, fmtMem(t.mem)],
      ['disk', t.disk / DISK_FULL, fmtRate(t.disk)],
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
    kill.innerHTML = `<span class="ms">${t.protected ? 'shield' : 'close'}</span><span>${taskArmed === t.name ? 'Confirmer' : ''}</span>`;
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
    box.append(row);
  });
}
$$('.task-seg button').forEach(b => b.addEventListener('click', () => {
  taskSort = b.dataset.s;
  $$('.task-seg button').forEach(x => x.classList.toggle('on', x === b));
  renderTasks();
}));
$('#task-q').addEventListener('input', renderTasks);
$('#taskmgr').addEventListener('click', () => { invoke('taskmgr_open'); setState('collapsed'); });


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
  invoke('clip_text', { text: notes.value });
  noteStatus('Copié');
  setTimeout(() => noteStatus(), 1200);
});
invoke('store_get', { key: 'notes' }).then(n => { if (n && typeof n.text === 'string') notes.value = n.text; noteStatus(); });

// mémoire totale, pour colorer la colonne Mémoire
let lastSys = null;
listen('sys', ({ payload }) => { lastSys = payload; });

// ========================================================= presse-papiers
function renderClips(list) {
  clipCount = list.length ? `${list.length} élément${list.length > 1 ? 's' : ''}` : 'Historique vide';
  if (clipView === 'hist') $('.clip-count').textContent = clipCount;
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
    if (c.text !== null && c.text !== undefined) {
      el.insertAdjacentHTML('beforeend', '<span class="ms to-note" title="Ajouter au bloc-notes">note_add</span>');
      el.querySelector('.to-note').addEventListener('click', e => {
        e.stopPropagation();
        addToNotes(c.text);
        el.classList.add('done');
        setTimeout(() => el.classList.remove('done'), 1200);
      });
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
  $('#set-win-key').checked = cfg.win_key;
  renderWinKey();
  $('#set-bar').checked = cfg.bar;
  $('#set-hide-taskbar').checked = cfg.hide_taskbar;
  $('#set-hide-taskbar').disabled = !cfg.bar;
  for (const k of ['islands', 'tasks', 'autohide']) {
    $(`#set-bar-${k}`).checked = cfg[`bar_${k}`];
    $(`#set-bar-${k}`).disabled = !cfg.bar;
  }
  $$('#set-rotate button').forEach(b => b.classList.toggle('on', Number(b.dataset.v) === cfg.rotate_min));
  $$('#set-island-bg button').forEach(b => b.classList.toggle('on', b.dataset.v === (cfg.island_bg || 'solid')));
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
// Touche Windows : remappée au niveau du pilote (invite administrateur), sinon
// Windows ouvre quand même le menu Démarrer
async function winKeyRemap(on) {
  const sw = $('#set-win-key');
  sw.disabled = true;
  const ok = await invoke('winkey_remap', { on });
  sw.disabled = false;
  // couper reste possible si le remappage n'a pas pu être retiré
  if (ok || !on) await setCfg({ win_key: on });
  sw.checked = cfg.win_key;
  renderWinKey();
}
async function renderWinKey() {
  const st = await invoke('winkey_status');
  const note = $('#win-key-note');
  if (!st) return (note.hidden = true);
  const btn = note.querySelector('button');
  let text = '', action = null;
  if (st.pending) text = 'Redémarrez Windows pour terminer (Redémarrer, pas Arrêter).';
  else if (cfg.win_key && !st.remap) {
    text = 'Windows peut encore ouvrir le menu Démarrer : la touche n\'est pas remappée.';
    action = ['Remapper', true];
  } else if (!cfg.win_key && st.remap) {
    text = 'La touche Windows est encore remappée.';
    action = ['Rétablir', false];
  }
  note.hidden = !text;
  note.querySelector('small').textContent = text;
  btn.hidden = !action;
  if (action) {
    btn.textContent = action[0];
    btn.onclick = () => winKeyRemap(action[1]);
  }
}
$('#set-win-key').addEventListener('change', e => winKeyRemap(e.target.checked));
$('#set-bar').addEventListener('change', e => setCfg({ bar: e.target.checked }));
$('#set-hide-taskbar').addEventListener('change', e => setCfg({ hide_taskbar: e.target.checked }));
for (const k of ['islands', 'tasks', 'autohide']) {
  $(`#set-bar-${k}`).addEventListener('change', e => setCfg({ [`bar_${k}`]: e.target.checked }));
}
$$('#set-rotate button').forEach(b => b.addEventListener('click', () => setCfg({ rotate_min: Number(b.dataset.v) })));
$$('#set-island-bg button').forEach(b => b.addEventListener('click', () => setCfg({ island_bg: b.dataset.v })));

// --- fond de l'îlot : opacité de la couleur de surface (en %), ou fond d'écran flouté
const ISLAND_ALPHA = { solid: 100, glass: 80, clear: 55, wall: 50 };
const WALL_BLEED = 30; // débord du calque flouté (évite les bords clairs du flou)
async function applyIslandBg(src = currentThumb) {
  const mode = cfg.island_bg || 'solid';
  const a = ISLAND_ALPHA[mode] ?? 100;
  document.documentElement.style.setProperty('--island-bg', a === 100 ? 'var(--surface)' : `color-mix(in srgb, var(--surface) ${a}%, transparent)`);
  const wall = mode === 'wall' && src;
  island.classList.toggle('wall-bg', !!wall);
  if (!wall) return;
  // le fond d'écran, calé comme à l'écran (« remplir ») : l'îlot est centré en haut
  try {
    const img = new Image();
    img.src = src;
    await img.decode();
    const s = Math.max(screen.width / img.naturalWidth, screen.height / img.naturalHeight);
    const w = img.naturalWidth * s, h = img.naturalHeight * s;
    const el = $('.island-wall');
    el.style.backgroundImage = `url("${src}")`;
    el.style.backgroundSize = `${w}px ${h}px`;
    el.style.backgroundPosition = `center ${WALL_BLEED - (h - screen.height) / 2}px`;
  } catch {}
}

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
  applyBar();
  applyIslandBg();
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

// ================================================================= barre
// Façon Waybar : à gauche le lanceur, les bureaux virtuels et les fenêtres
// ouvertes ; à droite l'état du système. Chaque module ouvre l'onglet de
// l'îlot qui va avec, et un second clic le referme.
let barOn = null;
let barWins = { windows: [], active: 0, desktops: 1, desktop: 0 };
const taskIcons = {};
let barVol = { level: 0, muted: false };
function refreshBar() {
  if (!barVisible()) hidePreview();
  $('#bar').classList.toggle('hidden', !barVisible());
  document.body.classList.toggle('with-bar', barDocked());
  document.body.classList.toggle('bar-islands', !!cfg.bar_islands);
  applySize();
}
function showBar(on) {
  clearTimeout(barTimer);
  if (on === barPeek) return;
  barPeek = on;
  refreshBar();
}
// la barre reste tant que le panneau de l'îlot est ouvert
function hideBarLater() {
  clearTimeout(barTimer);
  if (barPeek) barTimer = setTimeout(() => { if (state !== 'open' && !atTop && !pvKey) showBar(false); }, 500);
}
listen('top-hover', ({ payload }) => {
  atTop = payload;
  if (payload) showBar(true);
  else hideBarLater();
});
// îlots séparés : les zones cliquables suivent la taille des groupes
const barResize = new ResizeObserver(() => { if (cfg.bar_islands) reportHit(); });
['#bar', '.bar-l', '.bar-r'].forEach(q => barResize.observe($(q)));

function applyBar() {
  const on = !!cfg.bar;
  $('.bar-taskbar').hidden = !(on && cfg.hide_taskbar);
  if ($('.tasks').hidden === !!cfg.bar_tasks) {
    $('.tasks').hidden = !cfg.bar_tasks;
    renderBarWins(barWins);
  }
  if (!barAuto()) barPeek = false;
  refreshBar();
  if (on === barOn) return;
  barOn = on;
  $('#bar').hidden = !on;
  if (!on) return;
  invoke('bar_windows').then(renderBarWins);
  invoke('net_get').then(n => { net = n; renderTiles(); renderBarNet(); });
  invoke('volume_get').then(v => showBarVolume(v.level, v.muted));
}

function renderBarWins(t) {
  barWins = t;
  const ws = $('.ws');
  if (ws.children.length !== t.desktops) {
    ws.innerHTML = '';
    for (let i = 0; i < t.desktops; i++) {
      const b = document.createElement('button');
      b.title = `Bureau ${i + 1}`;
      b.addEventListener('click', () => invoke('desktop_go', { index: i }));
      ws.append(b);
    }
  }
  [...ws.children].forEach((b, i) => b.classList.toggle('on', i === t.desktop));

  const box = $('.tasks');
  box.innerHTML = '';
  if (!cfg.bar_tasks) return hidePreview();
  for (const g of taskGroups(t)) {
    const active = g.wins.find(w => w.id === t.active);
    const first = g.wins[0];
    const el = document.createElement('button');
    el.className = 'bar-task' + (active ? ' on' : '');
    el.dataset.key = g.key;
    el.innerHTML = taskIconHtml(g.key, first.title);
    const label = document.createElement('span');
    label.textContent = (active || first).title;
    el.append(label);
    if (g.wins.length > 1) {
      const n = document.createElement('em');
      n.textContent = g.wins.length;
      el.append(n);
    }
    // plusieurs fenêtres : chaque clic passe à la suivante
    el.addEventListener('click', () => {
      const i = g.wins.findIndex(w => w.id === barWins.active);
      const w = i >= 0 && g.wins.length > 1 ? g.wins[(i + 1) % g.wins.length] : first;
      hidePreview();
      invoke('task_activate', { id: w.id });
    });
    // clic molette : fermer, comme dans Waybar (fenêtre seule)
    el.addEventListener('mousedown', e => { if (e.button === 1) e.preventDefault(); });
    el.addEventListener('auxclick', e => { if (e.button === 1 && g.wins.length === 1) invoke('task_close', { id: first.id }); });
    box.append(el);
    if (taskIcons[g.key] === undefined) loadTaskIcon(g.key, first.id);
  }
  // la fenêtre qui vient d'être activée est capturée : une fois réduite, son
  // aperçu montrera encore son contenu
  const ids = new Set(t.windows.map(w => w.id));
  for (const id of Object.keys(thumbs)) if (!ids.has(Number(id))) delete thumbs[id];
  if (t.active !== lastActive) {
    lastActive = t.active;
    const id = t.active;
    if (id) setTimeout(() => { if (barWins.active === id) loadThumb(id); }, 800);
  }
  if (pvKey) renderPreview();
}

// fenêtres d'une même appli regroupées sous une seule icône
function taskGroups(t) {
  const groups = new Map();
  for (const w of t.windows) {
    if (!groups.has(w.icon)) groups.set(w.icon, []);
    groups.get(w.icon).push(w);
  }
  return [...groups].map(([key, wins]) => ({ key, wins }));
}
function taskIconHtml(key, title) {
  const icon = taskIcons[key];
  return icon ? `<img src="${icon}" alt="">` : `<i class="ph">${esc(title.trim()[0] || '?')}</i>`;
}

// --- aperçu des fenêtres au survol d'une appli
const PV_W = 220;
const PV_H = 124;
const thumbs = {}; // id de fenêtre -> dernière capture (gardée une fois réduite)
const minimized = new Set();
let lastActive = 0;
let pvKey = null;  // appli dont l'aperçu est affiché
let pvSig = '';
let pvShowTimer = null;
let pvHideTimer = null;
let pvRefresh = null;

function previewSoon(key) {
  clearTimeout(pvHideTimer);
  clearTimeout(pvShowTimer);
  if (key === pvKey) return;
  // déjà ouvert : on passe tout de suite à l'autre appli
  pvShowTimer = setTimeout(() => showPreview(key), pvKey ? 0 : 350);
}
function previewLeave() {
  clearTimeout(pvShowTimer);
  clearTimeout(pvHideTimer);
  pvHideTimer = setTimeout(hidePreview, 250);
}
function showPreview(key) {
  pvKey = key;
  pvSig = '';
  renderPreview();
  clearInterval(pvRefresh);
  pvRefresh = setInterval(loadThumbs, 1500);
}
function hidePreview() {
  clearTimeout(pvShowTimer);
  clearTimeout(pvHideTimer);
  clearInterval(pvRefresh);
  if (!pvKey) return;
  pvKey = null;
  $('#task-preview').classList.add('out');
  reportHit();
  if (!atTop) hideBarLater();
}
function renderPreview() {
  const g = taskGroups(barWins).find(g => g.key === pvKey);
  const anchor = $(`.bar-task[data-key="${CSS.escape(pvKey)}"]`);
  if (!g || !anchor || !barVisible()) return hidePreview();
  const pv = $('#task-preview');
  const sig = JSON.stringify([g.wins, barWins.active, !!taskIcons[g.key]]);
  if (sig !== pvSig) {
    pvSig = sig;
    const box = pv.querySelector('.tp-cards');
    box.innerHTML = '';
    for (const w of g.wins) {
      const card = document.createElement('div');
      card.className = 'tp-card' + (w.id === barWins.active ? ' on' : '');
      card.dataset.id = w.id;
      card.innerHTML = `<div class="tp-head">${taskIconHtml(g.key, w.title)}<span></span>`
        + `<button class="tp-x" title="Fermer"><span class="ms">close</span></button></div><div class="tp-shot"></div>`;
      card.querySelector('.tp-head span').textContent = w.title;
      setThumb(card, w.id);
      card.addEventListener('click', e => {
        hidePreview();
        if (e.target.closest('.tp-x')) return invoke('task_close', { id: w.id });
        if (w.id !== barWins.active) invoke('task_activate', { id: w.id });
      });
      card.addEventListener('mousedown', e => { if (e.button === 1) e.preventDefault(); });
      card.addEventListener('auxclick', e => { if (e.button === 1) invoke('task_close', { id: w.id }); });
      box.append(card);
    }
    loadThumbs();
  }
  // sous l'appli survolée, sans sortir de l'écran
  const a = anchor.getBoundingClientRect();
  const left = Math.max(8, Math.min(innerWidth - pv.offsetWidth - 8, a.left + a.width / 2 - pv.offsetWidth / 2));
  pv.style.left = left + 'px';
  pv.classList.remove('out');
  reportHit();
}
// réduite : dernière capture assombrie, ou à défaut l'icône de l'appli
function setThumb(card, id) {
  const shot = card.querySelector('.tp-shot');
  const src = thumbs[id];
  const min = minimized.has(id);
  shot.classList.toggle('min', min);
  if (src) {
    const img = shot.querySelector('img.tp-img');
    if (img) img.src = src;
    else shot.innerHTML = `<img class="tp-img" src="${src}" alt=""><small>Réduite</small>`;
  } else if (src === '' || min) {
    const key = taskGroups(barWins).find(g => g.wins.some(w => w.id === id))?.key;
    const title = barWins.windows.find(w => w.id === id)?.title || '';
    shot.innerHTML = `<div class="tp-ph">${taskIconHtml(key, title)}</div><small>${min ? 'Réduite' : 'Aperçu indisponible'}</small>`;
  }
}
function loadThumb(id) {
  const dpr = devicePixelRatio || 1;
  return invoke('task_thumb', { id, w: Math.round(PV_W * dpr), h: Math.round(PV_H * dpr) }).then(src => {
    if (src === 'min') minimized.add(id);
    else { minimized.delete(id); thumbs[id] = src; }
    if (src === 'min' && thumbs[id] === undefined) thumbs[id] = '';
  });
}
function loadThumbs() {
  if (!pvKey) return;
  for (const card of $$('#task-preview .tp-card')) {
    const id = Number(card.dataset.id);
    loadThumb(id).then(() => { if (card.isConnected) setThumb(card, id); });
  }
}
$('.tasks').addEventListener('mouseover', e => {
  const t = e.target.closest('.bar-task');
  if (t) previewSoon(t.dataset.key);
});
$('.tasks').addEventListener('mouseleave', previewLeave);
$('#task-preview').addEventListener('mouseenter', () => clearTimeout(pvHideTimer));
$('#task-preview').addEventListener('mouseleave', previewLeave);
const iconTries = {};
function loadTaskIcon(key, id) {
  taskIcons[key] = null; // en cours
  invoke('task_icon', { key, id }).then(src => {
    taskIcons[key] = src || '';
    if (src) return renderBarWins(barWins);
    // échec passager (démarrage de Windows, appli qui se lance) : on réessaie
    const n = (iconTries[key] = (iconTries[key] || 0) + 1);
    if (n <= 5) setTimeout(() => { delete taskIcons[key]; renderBarWins(barWins); }, 2000 * n);
  });
}
listen('tasks', ({ payload }) => renderBarWins(payload));

let wsWheel = 0;
$('.ws').addEventListener('wheel', e => {
  if (Date.now() - wsWheel < 350) return;
  const i = Math.max(0, Math.min(barWins.desktops - 1, barWins.desktop + Math.sign(e.deltaY)));
  if (i === barWins.desktop) return;
  wsWheel = Date.now();
  invoke('desktop_go', { index: i });
}, { passive: true });

function openFromBar(tab) {
  if (state === 'open' && currentTab === tab) return setState('collapsed');
  pinned = true;
  open(tab);
}
$$('#bar [data-open]').forEach(b => b.addEventListener('click', () => openFromBar(b.dataset.open)));
$('.bar-launch').addEventListener('click', () => {
  openFromBar('apps');
  if (state === 'open') { invoke('grab_focus'); setTimeout(() => $('#q').focus(), 60); }
});

function barResources(r) {
  $('.bar-cpu').textContent = Math.round(r.cpu) + '%';
  $('.bar-mem').textContent = Math.round((r.mem_used / r.mem_total) * 100) + '%';
  $('.bar-res').classList.toggle('hot', r.cpu > 90);
  const bat = $('.bar-bat');
  bat.hidden = r.battery < 0;
  if (r.battery >= 0) {
    bat.querySelector('.ms').textContent = r.charging ? 'battery_charging_full' : r.battery <= 20 ? 'battery_std' : 'battery_full';
    bat.querySelector('b').textContent = r.battery + '%';
    bat.title = r.charging ? 'En charge' : 'Sur batterie';
  }
}

function renderBarNet() {
  const r = net.radios;
  const wifi = $('.bar-wifi');
  wifi.hidden = r.wifi === null;
  wifi.classList.toggle('off', !r.wifi || !net.ssid);
  wifi.title = r.wifi ? net.ssid || 'Wi-Fi : non connecté' : 'Wi-Fi désactivé';
  const bt = $('.bar-bt');
  bt.hidden = !r.bluetooth;
  bt.querySelector('.ms').textContent = net.bt_devices.length ? 'bluetooth_connected' : 'bluetooth';
  bt.title = net.bt_devices.length ? net.bt_devices.join(', ') : 'Bluetooth';
}

function showBarVolume(level, muted) {
  barVol = { level, muted };
  const v = Math.round(level * 100);
  const b = $('.bar-vol');
  b.classList.toggle('off', muted);
  b.querySelector('.ms').textContent = muted || v === 0 ? 'volume_off' : v < 50 ? 'volume_down' : 'volume_up';
  b.querySelector('b').textContent = muted ? '–' : v + '%';
}
$('.bar-vol').addEventListener('click', () => {
  showBarVolume(barVol.level, !barVol.muted);
  invoke('volume_set', { muted: barVol.muted });
});
$('.bar-vol').addEventListener('wheel', e => {
  const level = Math.max(0, Math.min(1, Math.round((barVol.level - Math.sign(e.deltaY) * 0.05) * 100) / 100));
  showBarVolume(level, false);
  invoke('volume_set', { level, muted: false });
}, { passive: true });

// barre des tâches Windows affichée temporairement
$('.bar-taskbar').addEventListener('click', e => {
  invoke('taskbar_peek', { show: !e.currentTarget.classList.contains('on') });
});
listen('taskbar-peek', ({ payload }) => {
  const b = $('.bar-taskbar');
  b.classList.toggle('on', payload);
  b.title = payload ? 'Masquer la barre des tâches Windows' : 'Afficher la barre des tâches Windows';
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
    applyIslandBg(src);
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
