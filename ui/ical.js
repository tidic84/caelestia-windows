// Lecture des agendas iCal (.ics) : événements simples et récurrents
// (RRULE DAILY / WEEKLY / MONTHLY / YEARLY avec INTERVAL, COUNT, UNTIL,
// BYDAY, ainsi que EXDATE). Les heures avec TZID sont lues en heure locale.

function unfold(text) {
  return text.replace(/\r\n/g, '\n').replace(/\n[ \t]/g, '');
}

function unescapeText(s) {
  return s.replace(/\\n/gi, '\n').replace(/\\([,;\\])/g, '$1');
}

/// « 20261015 », « 20261015T143000 » ou « 20261015T143000Z » -> { date, allDay }
function parseDate(value, params) {
  const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/.exec(value.trim());
  if (!m) return null;
  const [, y, mo, d, h, mi, s, z] = m;
  if (h === undefined || /VALUE=DATE(?!-)/.test(params)) {
    return { date: new Date(+y, +mo - 1, +d), allDay: true };
  }
  const date = z
    ? new Date(Date.UTC(+y, +mo - 1, +d, +h, +mi, +(s || 0)))
    : new Date(+y, +mo - 1, +d, +h, +mi, +(s || 0));
  return { date, allDay: false, utc: !!z };
}

function parseEvents(text) {
  const lines = unfold(text).split('\n');
  const events = [];
  let ev = null;
  for (const line of lines) {
    if (line === 'BEGIN:VEVENT') { ev = { exdates: [] }; continue; }
    if (line === 'END:VEVENT') { if (ev && ev.start) events.push(ev); ev = null; continue; }
    if (!ev) continue;
    const i = line.indexOf(':');
    if (i < 0) continue;
    const head = line.slice(0, i);
    const value = line.slice(i + 1);
    const [name, ...rest] = head.split(';');
    const params = rest.join(';');
    switch (name.toUpperCase()) {
      case 'SUMMARY': ev.title = unescapeText(value); break;
      case 'LOCATION': ev.location = unescapeText(value); break;
      case 'DTSTART': { const d = parseDate(value, params); if (d) { ev.start = d.date; ev.allDay = d.allDay; ev.utc = d.utc; } break; }
      case 'DTEND': { const d = parseDate(value, params); if (d) ev.end = d.date; break; }
      case 'RRULE': ev.rrule = Object.fromEntries(value.split(';').map(p => p.split('='))); break;
      case 'EXDATE': value.split(',').forEach(v => { const d = parseDate(v, params); if (d) ev.exdates.push(d.date.getTime()); }); break;
      case 'RECURRENCE-ID': { const d = parseDate(value, params); if (d) ev.recurrenceId = d.date.getTime(); break; }
      case 'UID': ev.uid = value; break;
      case 'STATUS': ev.cancelled = value.toUpperCase() === 'CANCELLED'; break;
    }
  }
  return events;
}

const DAYS = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

/// Occurrences d'un événement récurrent entre `from` et `to`.
function expand(ev, from, to) {
  const r = ev.rrule;
  const dur = (ev.end ? ev.end - ev.start : ev.allDay ? 86400000 : 3600000);
  const out = [];
  const interval = Math.max(1, parseInt(r.INTERVAL || '1', 10));
  const count = r.COUNT ? parseInt(r.COUNT, 10) : Infinity;
  const until = r.UNTIL ? parseDate(r.UNTIL, '')?.date : null;
  const byday = r.BYDAY ? r.BYDAY.split(',').map(d => ({ n: parseInt(d, 10) || 0, wd: DAYS[d.slice(-2)] })) : null;
  let n = 0;
  const push = c => {
    const d = toReal(c);
    if (until && d > until) return false;
    if (n >= count) return false;
    n++;
    if (d.getTime() + dur >= from.getTime() && d <= to && !ev.exdates.includes(d.getTime())) {
      out.push({ ...ev, start: new Date(d), end: new Date(d.getTime() + dur) });
    }
    return true;
  };
  // une heure UTC reste fixe en UTC (elle bouge en heure locale au changement d'heure)
  const u = ev.utc;
  const st = ev.start;
  const s = u ? new Date(st.getUTCFullYear(), st.getUTCMonth(), st.getUTCDate(), st.getUTCHours(), st.getUTCMinutes(), st.getUTCSeconds()) : st;
  const toReal = d => (u ? new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes(), d.getSeconds())) : d);
  const at = (y, m, day) => new Date(y, m, day, s.getHours(), s.getMinutes(), s.getSeconds());
  const freq = r.FREQ;
  // sans COUNT, on saute directement près de la plage demandée
  const period = { DAILY: 1, WEEKLY: 7, MONTHLY: 30.44, YEARLY: 365.25 }[freq] * 86400000;
  let k0 = 0;
  if (count === Infinity && period && from > s) {
    k0 = Math.max(0, Math.floor((from - s) / period / interval) - 1) * interval;
  }
  // borne de sécurité
  for (let k = k0, guard = 0; guard < 4000; k += interval, guard++) {
    let cands = [];
    if (freq === 'DAILY') cands = [at(s.getFullYear(), s.getMonth(), s.getDate() + k)];
    else if (freq === 'WEEKLY') {
      const base = at(s.getFullYear(), s.getMonth(), s.getDate() + k * 7);
      const monday = new Date(base); monday.setDate(base.getDate() - ((base.getDay() + 6) % 7));
      const wds = byday ? byday.map(b => b.wd) : [s.getDay()];
      cands = wds.map(wd => at(monday.getFullYear(), monday.getMonth(), monday.getDate() + ((wd + 6) % 7))).sort((a, b) => a - b);
    } else if (freq === 'MONTHLY') {
      const y = s.getFullYear(), m = s.getMonth() + k;
      if (byday) {
        for (const b of byday) {
          const days = [];
          for (let d = 1; d <= 31; d++) { const x = at(y, m, d); if (x.getMonth() !== ((m % 12) + 12) % 12) break; if (x.getDay() === b.wd) days.push(x); }
          if (b.n > 0 && days[b.n - 1]) cands.push(days[b.n - 1]);
          else if (b.n < 0 && days[days.length + b.n]) cands.push(days[days.length + b.n]);
          else if (!b.n) cands.push(...days);
        }
        cands.sort((a, b) => a - b);
      } else {
        const x = at(y, m, s.getDate());
        if (x.getDate() === s.getDate()) cands = [x];
      }
    } else if (freq === 'YEARLY') {
      const x = at(s.getFullYear() + k, s.getMonth(), s.getDate());
      if (x.getMonth() === s.getMonth()) cands = [x];
    } else {
      break;
    }
    let stop = false;
    for (const c of cands) {
      if (c < s) continue;
      if (toReal(c) > to) { stop = true; break; }
      if (!push(c)) { stop = true; break; }
    }
    if (stop) break;
  }
  return out;
}

/// Événements des agendas entre `from` et `to`, triés.
export function eventsBetween(texts, from, to) {
  const all = [];
  for (const t of texts) {
    const evs = parseEvents(t);
    // occurrences modifiées individuellement (RECURRENCE-ID)
    const overrides = new Map();
    evs.filter(e => e.recurrenceId).forEach(e => overrides.set(e.uid + '|' + e.recurrenceId, e));
    for (const ev of evs) {
      if (ev.recurrenceId) continue;
      const occ = ev.rrule ? expand(ev, from, to) : [{ ...ev, end: ev.end || new Date(ev.start.getTime() + (ev.allDay ? 86400000 : 3600000)) }];
      for (const o of occ) {
        const ov = overrides.get(ev.uid + '|' + o.start.getTime());
        const e = ov ? { ...ov, end: ov.end || new Date(ov.start.getTime() + (o.end - o.start)) } : o;
        if (e.cancelled) continue;
        if (e.end > from && e.start <= to) all.push(e);
      }
    }
    // exceptions déplacées hors de la plage d'origine
    for (const ov of overrides.values()) {
      if (ov.cancelled || !ov.start) continue;
      const end = ov.end || new Date(ov.start.getTime() + 3600000);
      if (end > from && ov.start <= to && !all.includes(ov) && !all.some(a => a.uid === ov.uid && a.start.getTime() === ov.start.getTime())) {
        all.push({ ...ov, end });
      }
    }
  }
  return all.sort((a, b) => a.start - b.start);
}
