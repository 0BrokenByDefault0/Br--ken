// ============================================================
// BR--KEN · ui components
// Tiny DOM builder + touch-first controls shared across views.
// ============================================================

export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') el.className = v;
    else if (k === 'style') el.style.cssText = v;
    else if (k === 'dataset') Object.assign(el.dataset, v);
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (v !== false && v != null) el.setAttribute(k, v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    el.append(c.nodeType ? c : document.createTextNode(c));
  }
  return el;
}

// ---------------- toast ----------------

let toastTimer = 0;
export function toast(msg, ms = 1800) {
  const el = document.getElementById('toast');
  if (!el) return;
  el.textContent = msg;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, ms);
}

// ---------------- long-press ----------------

/**
 * Attach tap + long-press handlers to an element.
 * Cancels on pointer movement (so scrolling never triggers either).
 */
export function pressable(el, { onTap, onLongPress, holdMs = 450 } = {}) {
  let timer = 0, sx = 0, sy = 0, long = false, active = false;

  el.addEventListener('pointerdown', (e) => {
    if (!e.isPrimary) return;
    active = true; long = false;
    sx = e.clientX; sy = e.clientY;
    if (onLongPress) {
      timer = setTimeout(() => {
        if (!active) return;
        long = true;
        navigator.vibrate?.(12);
        onLongPress(e);
      }, holdMs);
    }
  });

  el.addEventListener('pointermove', (e) => {
    if (!active) return;
    if (Math.hypot(e.clientX - sx, e.clientY - sy) > 12) {
      active = false;
      clearTimeout(timer);
    }
  });

  const end = (e) => {
    clearTimeout(timer);
    if (active && !long && e.type === 'pointerup' && onTap) onTap(e);
    active = false;
  };
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', end);
}

// ---------------- knob ----------------

/**
 * Rotary knob driven by vertical drag.
 * opts: { label, value (0..1), format(v)=>string, color, onInput(v), onStart() }
 * Returns { el, set(v) }.
 */
export function makeKnob(opts) {
  const dial = h('div', { class: 'knob-dial' });
  const val = h('div', { class: 'knob-val' });
  const root = h('div', { class: 'knob' },
    dial, h('div', { class: 'knob-label' }, opts.label), val);
  if (opts.color) dial.style.setProperty('--knob-c', opts.color);

  let v = opts.value ?? 0;
  const fmt = opts.format || ((x) => Math.round(x * 100).toString());

  function paint() {
    dial.style.setProperty('--rot', `${-135 + v * 270}deg`);
    val.textContent = fmt(v);
  }
  paint();

  let dragging = false, startY = 0, startV = 0;
  dial.addEventListener('pointerdown', (e) => {
    dragging = true;
    startY = e.clientY;
    startV = v;
    dial.setPointerCapture(e.pointerId);
    opts.onStart?.();
    e.preventDefault();
  });
  dial.addEventListener('pointermove', (e) => {
    if (!dragging) return;
    const dy = startY - e.clientY;
    v = Math.max(0, Math.min(1, startV + dy / 150));
    paint();
    opts.onInput?.(v);
  });
  const up = () => { dragging = false; };
  dial.addEventListener('pointerup', up);
  dial.addEventListener('pointercancel', up);
  dial.addEventListener('dblclick', () => {
    v = opts.defaultValue ?? 0.5;
    paint();
    opts.onInput?.(v);
  });

  return { el: root, set(x) { if (!dragging) { v = x; paint(); } } };
}

// ---------------- vertical fader ----------------

/**
 * opts: { value 0..1, color, onInput(v), onStart() }
 * Returns { el, set(v), setMeter(rms) }.
 */
export function makeFader(opts) {
  const fill = h('div', { class: 'fader-fill' });
  const thumb = h('div', { class: 'fader-thumb' });
  const meterFill = h('div', { class: 'meter-fill' });
  const meter = h('div', { class: 'meter' }, meterFill);
  const rail = h('div', { class: 'fader-rail' }, fill, thumb, meter);
  if (opts.color) rail.style.setProperty('--strip-c', opts.color);

  let v = opts.value ?? 0.8;
  function paint() {
    const pct = v * 100;
    fill.style.height = `${pct}%`;
    thumb.style.bottom = `calc(${pct}% - 7px)`;
  }
  paint();

  let dragging = false;
  const fromEvent = (e) => {
    const r = rail.getBoundingClientRect();
    return Math.max(0, Math.min(1, 1 - (e.clientY - r.top) / r.height));
  };
  rail.addEventListener('pointerdown', (e) => {
    dragging = true;
    rail.setPointerCapture(e.pointerId);
    opts.onStart?.();
    v = fromEvent(e);
    paint();
    opts.onInput?.(v);
    e.preventDefault();
  });
  rail.addEventListener('pointermove', (e) => {
    if (!dragging) return;
    v = fromEvent(e);
    paint();
    opts.onInput?.(v);
  });
  const up = () => { dragging = false; };
  rail.addEventListener('pointerup', up);
  rail.addEventListener('pointercancel', up);

  return {
    el: rail,
    set(x) { if (!dragging) { v = x; paint(); } },
    setMeter(rms) {
      const pct = Math.min(1, rms * 3.2) * 100;
      meterFill.style.height = `${pct}%`;
    },
  };
}

export const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
export const midiName = (m) => `${NOTE_NAMES[m % 12]}${Math.floor(m / 12) - 1}`;
