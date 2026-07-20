// ============================================================
// BR--KEN · play view
// Multi-touch performance pads: scale-locked notes for synth
// tracks, drum pads for drum tracks. Arm REC + launch a clip
// and everything you play is quantized into it live.
// ============================================================

import { store, DRUM_LANES } from '../state.js';
import { SYNTH_PRESETS, SYNTH_PRESET_IDS } from '../audio/instruments.js';
import { engine } from '../audio/engine.js';
import { h, NOTE_NAMES } from './components.js';

const SCALES = {
  minor:   { name: 'MINOR',    iv: [0, 2, 3, 5, 7, 8, 10] },
  major:   { name: 'MAJOR',    iv: [0, 2, 4, 5, 7, 9, 11] },
  dorian:  { name: 'DORIAN',   iv: [0, 2, 3, 5, 7, 9, 10] },
  minpent: { name: 'MIN·PENT', iv: [0, 3, 5, 7, 10] },
  majpent: { name: 'MAJ·PENT', iv: [0, 2, 4, 7, 9] },
  chrom:   { name: 'CHROMA',   iv: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] },
};

export function render(container) {
  const track = store.selectedTrack;
  const view = h('div', { class: 'keys' });
  view.append(head(track));
  view.append(track?.type === 'drum' ? drumPads(track) : notePads(track));
  container.replaceChildren(view);
}

function head(track) {
  const ui = store.ui;

  const trackSel = h('select', { class: 'keys-select', 'aria-label': 'track' });
  store.project.tracks.forEach((t, i) => {
    const o = h('option', { value: i }, t.name);
    if (i === ui.selectedTrack) o.selected = true;
    trackSel.append(o);
  });
  trackSel.addEventListener('change', () => {
    ui.selectedTrack = +trackSel.value;
    store.emit('clip');
  });

  const kids = [trackSel];

  if (track?.type === 'synth') {
    const presetSel = h('select', { class: 'keys-select', 'aria-label': 'preset' });
    SYNTH_PRESET_IDS.forEach(id => {
      const o = h('option', { value: id }, SYNTH_PRESETS[id].name);
      if (id === track.presetId) o.selected = true;
      presetSel.append(o);
    });
    presetSel.addEventListener('change', () => {
      store.mutate(() => { track.presetId = presetSel.value; }, 'clip');
    });

    const rootSel = h('select', { class: 'keys-select', 'aria-label': 'root' });
    NOTE_NAMES.forEach((n, i) => {
      const o = h('option', { value: i }, n);
      if (i === ui.scaleRoot) o.selected = true;
      rootSel.append(o);
    });
    rootSel.addEventListener('change', () => { ui.scaleRoot = +rootSel.value; store.emit('clip'); });

    const scaleSel = h('select', { class: 'keys-select', 'aria-label': 'scale' });
    for (const [id, s] of Object.entries(SCALES)) {
      const o = h('option', { value: id }, s.name);
      if (id === ui.scaleId) o.selected = true;
      scaleSel.append(o);
    }
    scaleSel.addEventListener('change', () => { ui.scaleId = scaleSel.value; store.emit('clip'); });

    const octDn = octBtn('OCT−', () => { ui.octave = Math.max(1, ui.octave - 1); store.emit('clip'); });
    const octUp = octBtn('OCT+', () => { ui.octave = Math.min(6, ui.octave + 1); store.emit('clip'); });
    kids.push(presetSel, rootSel, scaleSel, octDn, octUp);
  }

  return h('div', { class: 'keys-head' }, ...kids);
}

function octBtn(label, fn) {
  const b = h('button', { class: 'ed-tool' }, label);
  b.addEventListener('click', fn);
  return b;
}

// ---------------- synth pads: 16 scale-locked notes, low→high ----------------

function notePads(track) {
  const ui = store.ui;
  const scale = SCALES[ui.scaleId] || SCALES.minor;
  const base = 12 * (ui.octave + 1) + ui.scaleRoot; // octave 3 + C → C3=48

  const midis = [];
  for (let i = 0; midis.length < 16; i++) {
    const oct = Math.floor(i / scale.iv.length);
    const deg = i % scale.iv.length;
    const m = base + oct * 12 + scale.iv[deg];
    if (m > 108) break;
    midis.push(m);
  }

  const grid = h('div', { class: 'pads' });
  // bottom-left = lowest note: top visual row holds the highest four
  for (let row = 3; row >= 0; row--) {
    for (let col = 0; col < 4; col++) {
      const m = midis[row * 4 + col];
      if (m == null) { grid.append(h('div')); continue; }
      grid.append(pad(track, m));
    }
  }
  return grid;
}

function pad(track, midi) {
  const isRoot = midi % 12 === store.ui.scaleRoot;
  const el = h('div', { class: `pad${isRoot ? ' root' : ''}` },
    h('div', { class: 'pad-name' }, NOTE_NAMES[midi % 12]),
    h('div', { class: 'pad-oct' }, `${Math.floor(midi / 12) - 1}`),
  );
  bindPad(el,
    () => engine.noteOn(track.id, midi, 1),
    () => engine.noteOff(track.id, midi));
  return el;
}

// ---------------- drum pads ----------------

function drumPads(track) {
  const grid = h('div', { class: 'pads drumpads' });
  // classic MPC order: kick bottom-left
  const order = [4, 5, 6, 7, 0, 1, 2, 3];
  for (const li of order) {
    const lane = DRUM_LANES[li];
    const el = h('div', { class: 'pad drumpad' }, lane.name);
    bindPad(el,
      () => engine.hitDrum(track.id, li, 1),
      () => {});
    grid.append(el);
  }
  return grid;
}

// multi-touch pad binding with visual feedback
function bindPad(el, down, up) {
  const active = new Set();
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    active.add(e.pointerId);
    el.classList.add('lit');
    navigator.vibrate?.(8);
    down();
  });
  const end = (e) => {
    if (!active.has(e.pointerId)) return;
    active.delete(e.pointerId);
    if (!active.size) el.classList.remove('lit');
    up();
  };
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', end);
  el.addEventListener('pointerleave', end);
}
