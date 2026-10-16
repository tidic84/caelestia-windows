// Barre d'un écran sans îlot (fenêtre `bar-*`, voir src/screens.rs) : les
// mêmes modules que la barre de l'îlot (app.js), dont les boutons ouvrent
// l'îlot sur son écran. Le thème vient de l'îlot, par le localStorage.

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;
const LABEL = window.__TAURI__.webviewWindow.getCurrentWebviewWindow().label;

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const store = {
  get(k, d = null) { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch { return d; } },
};

const BAR_H = 30;
let cfg = { bar: true, hide_taskbar: true, bar_islands: true, bar_tasks: false, bar_autohide: true, dnd: false };
let fullscreen = false;
let barPeek = false; // barre affichée (masquage automatique)
let atTop = false;   // souris dans la bande du haut de l'écran
let barTimer = null;
const barAuto = () => !!cfg.bar_autohide;
const barVisible = () => !fullscreen && (!cfg.bar_autohide || barPeek);

// ================================================================= thème
let themeSig = '';
function applyTheme() {
  const p = store.get('palette');
  const light = store.get('light', false);
  const bg = store.get('islandBg', 'var(--surface)');
  const sig = JSON.stringify([p, light, bg]);
  if (sig === themeSig) return;
  themeSig = sig;
  if (p) for (const [k, v] of Object.entries(p)) document.documentElement.style.setProperty('--' + k, v);
  document.documentElement.classList.toggle('light', light);
  document.documentElement.style.setProperty('--island-bg', bg);
}
addEventListener('storage', applyTheme);
setInterval(applyTheme, 3000);

// ======================================================= zones cliquables
function reportHit() {
  const rects = [];
  if (barVisible()) {
    if (!cfg.bar_islands) rects.push({ x: 0, y: 0, w: innerWidth, h: BAR_H });
    // îlots séparés : les clics passent entre eux
    else for (const el of $$('.bar-side > *, .bar-clock')) {
      const r = el.getBoundingClientRect();
      if (r.width) rects.push({ x: r.left - 2, y: 0, w: r.width + 4, h: BAR_H });
    }
    if (pvKey) {
      const r = $('#task-preview').getBoundingClientRect();
      rects.push({ x: r.left, y: r.top, w: r.width, h: r.height });
    }
  }
  // masquage auto : une bande au bord de l'écran affiche la barre
  const top = barAuto() && !fullscreen ? (barPeek ? BAR_H + 8 : 2) : 0;
  invoke('set_hit', { rects, top });
}

function refreshBar() {
  if (!barVisible()) hidePreview();
  $('#bar').classList.toggle('hidden', !barVisible());
  document.body.classList.toggle('bar-islands', !!cfg.bar_islands);
  reportHit();
}
function showBar(on) {
  clearTimeout(barTimer);
  if (on === barPeek) return;
  barPeek = on;
  refreshBar();
}
function hideBarLater() {
  clearTimeout(barTimer);
  if (barPeek) barTimer = setTimeout(() => { if (!atTop && !pvKey) showBar(false); }, 500);
}
listen('bar-top', ({ payload: [label, on] }) => {
  if (label !== LABEL) return;
  atTop = on;
  if (on) showBar(true);
  else hideBarLater();
});
listen('bar-fullscreen', ({ payload: [label, on] }) => {
  if (label !== LABEL) return;
  fullscreen = on;
  refreshBar();
});
const barResize = new ResizeObserver(() => { if (cfg.bar_islands) reportHit(); });
['#bar', '.bar-l', '.bar-r'].forEach(q => barResize.observe($(q)));

function applySettings() {
  $('.bar-taskbar').hidden = !cfg.hide_taskbar;
  if ($('.tasks').hidden === !!cfg.bar_tasks) {
    $('.tasks').hidden = !cfg.bar_tasks;
    renderBarWins(barWins);
  }
  if (!barAuto()) barPeek = false;
  refreshBar();
  renderNotifs();
}
listen('settings', ({ payload }) => { Object.assign(cfg, payload); applySettings(); });

// ============================================================== horloge
const fmtBar = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
let clockKey = '';
function tickClock() {
  const d = new Date();
  const key = `${d.getHours()}:${d.getMinutes()}:${d.getDate()}`;
  if (key === clockKey) return;
  clockKey = key;
  $('.bar-clock').textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  const day = fmtBar.format(d);
  $('.bar-date').textContent = day[0].toUpperCase() + day.slice(1);
}
setInterval(tickClock, 1000);

// =============================================== fenêtres et bureaux
let barWins = { windows: [], active: 0, desktops: 1, desktop: 0 };
const taskIcons = {};

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
    // clic molette : fermer (fenêtre seule)
    el.addEventListener('mousedown', e => { if (e.button === 1) e.preventDefault(); });
    el.addEventListener('auxclick', e => { if (e.button === 1 && g.wins.length === 1) invoke('task_close', { id: first.id }); });
    box.append(el);
    if (taskIcons[g.key] === undefined) loadTaskIcon(g.key, first.id);
  }
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

const iconTries = {};
function loadTaskIcon(key, id) {
  taskIcons[key] = null; // en cours
  invoke('task_icon', { key, id }).then(src => {
    taskIcons[key] = src || '';
    if (src) return renderBarWins(barWins);
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

// --- aperçu des fenêtres au survol d'une appli
const PV_W = 220;
const PV_H = 124;
const thumbs = {};
const minimized = new Set();
let lastActive = 0;
let pvKey = null;
let pvSig = '';
let pvShowTimer = null;
let pvHideTimer = null;
let pvRefresh = null;

function previewSoon(key) {
  clearTimeout(pvHideTimer);
  clearTimeout(pvShowTimer);
  if (key === pvKey) return;
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
  const a = anchor.getBoundingClientRect();
  const left = Math.max(8, Math.min(innerWidth - pv.offsetWidth - 8, a.left + a.width / 2 - pv.offsetWidth / 2));
  pv.style.left = left + 'px';
  pv.classList.remove('out');
  reportHit();
}
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

// ========================================================= boutons
// l'îlot s'ouvre sur son écran, sur l'onglet du module
$$('#bar [data-open]').forEach(b => b.addEventListener('click', () => invoke('bar_open', { tab: b.dataset.open })));
$('.bar-launch').addEventListener('click', () => invoke('bar_open', { tab: 'launcher' }));

// ===================================================== état du système
listen('sys', ({ payload: r }) => {
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
});

function renderNet(net) {
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
listen('net', ({ payload }) => renderNet(payload));

let barVol = { level: 0, muted: false };
function showBarVolume(level, muted) {
  barVol = { level, muted };
  const v = Math.round(level * 100);
  const b = $('.bar-vol');
  b.classList.toggle('off', muted);
  b.querySelector('.ms').textContent = muted || v === 0 ? 'volume_off' : v < 50 ? 'volume_down' : 'volume_up';
  b.querySelector('b').textContent = muted ? '–' : v + '%';
}
listen('osd', ({ payload: o }) => { if (o.kind === 'volume') showBarVolume(o.value, o.muted); });
$('.bar-vol').addEventListener('click', () => {
  showBarVolume(barVol.level, !barVol.muted);
  invoke('volume_set', { muted: barVol.muted });
});
$('.bar-vol').addEventListener('wheel', e => {
  const level = Math.max(0, Math.min(1, Math.round((barVol.level - Math.sign(e.deltaY) * 0.05) * 100) / 100));
  showBarVolume(level, false);
  invoke('volume_set', { level, muted: false });
}, { passive: true });

let notifCount = 0;
function renderNotifs() {
  const n = notifCount;
  const bell = $('.bar-notif');
  bell.classList.toggle('has', !!n && !cfg.dnd);
  bell.querySelector('.ms').textContent = cfg.dnd ? 'do_not_disturb_on' : n ? 'notifications' : 'notifications_none';
  bell.querySelector('b').textContent = n && !cfg.dnd ? (n > 9 ? '9+' : n) : '';
}
listen('notifs', ({ payload }) => { notifCount = payload.length; renderNotifs(); });

// barre des tâches Windows affichée temporairement
$('.bar-taskbar').addEventListener('click', e => {
  invoke('taskbar_peek', { show: !e.currentTarget.classList.contains('on') });
});
listen('taskbar-peek', ({ payload }) => {
  const b = $('.bar-taskbar');
  b.classList.toggle('on', payload);
  b.title = payload ? 'Masquer la barre des tâches Windows' : 'Afficher la barre des tâches Windows';
});

// ============================================================== démarrage
applyTheme();
tickClock();
(async () => {
  Object.assign(cfg, await invoke('settings_get'));
  applySettings();
  invoke('bar_windows').then(renderBarWins);
  invoke('net_get').then(renderNet);
  invoke('volume_get').then(v => showBarVolume(v.level, v.muted));
  invoke('notifs_get').then(l => { notifCount = l.length; renderNotifs(); });
})();
