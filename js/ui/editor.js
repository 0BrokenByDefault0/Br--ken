// ============================================================
// BR--KEN · editor view
// Drum tracks get a step grid; synth tracks get a piano roll.
// tap = add/select · tap selected = delete · toolbar for tweaks
// ============================================================

import { store, DRUM_LANES, STEPS_PER_BAR, makeNote } from '../state.js';
import { engine } from '../audio/engine.js';
import { h, toast, midiName } from './components.js';

const CELL_W = 34;
const CELL_H = 26;
const KEY_W = 44;
const PITCH_MAX = 96; // C7
const PITCH_MIN = 33; // A1

let root = null;
let scrollMemo = { x: 0, y: 0 };
let colCells = [];      // drum grid: step -> [cells]
let playheadEl = null;
let scroller = null;
let firstOpen = true;

export function render(container) {
  root = container;
  const clip = store.editingClip;
  const track = store.editingTrack;

  if (!clip || !track) {
    container.replaceChildren(
      h('div', { class: 'editor' },
        h('div', { class: 'editor-empty' },
          'NO CLIP SELECTED', h('br'), 'long-press a slot in SESSION', h('br'), 'to create or edit a clip')),
    );
    return;
  }

  const ed = h('div', { class: 'editor', style: `--clip-c: ${track.color};` });
  ed.append(header(track, clip));

  if (track.type === 'drum') {
    ed.append(drumGrid(track, clip));
  } else {
    ed.append(pianoRoll(track, clip));
    ed.append(noteTools(track, clip));
  }

  container.replaceChildren(ed);

  if (scroller) {
    if (firstOpen && track.type !== 'drum') {
      // center the view on the clip's notes (or middle C)
      const pitches = clip.notes.map(n => n.pitch);
      const mid = pitches.length ? (Math.max(...pitches) + Math.min(...pitches)) / 2 : 60;
      scroller.scrollTop = (PITCH_MAX - mid) * CELL_H - scroller.clientHeight / 2;
      firstOpen = false;
    } else {
      scroller.scrollLeft = scrollMemo.x;
      scroller.scrollTop = scrollMemo.y;
    }
    scroller.addEventListener('scroll', () => {
      scrollMemo = { x: scroller.scrollLeft, y: scroller.scrollTop };
    }, { passive: true });
  }
}

export function onClipChanged() { firstOpen = true; scrollMemo = { x: 0, y: 0 }; }

// ---------------- header ----------------

function header(track, clip) {
  const name = h('button', { class: 'ed-clipname' }, clip.name);
  name.addEventListener('click', () => {
    const v = prompt('clip name', clip.name);
    if (v == null) return;
    store.mutate(() => { clip.name = v.trim().slice(0, 20) || clip.name; }, 'clip');
  });

  const bars = toolBtn(`${clip.bars} BAR${clip.bars > 1 ? 'S' : ''}`, () => {
    const next = { 1: 2, 2: 4, 4: 8, 8: 1 }[clip.bars] || 1;
    store.mutate(() => {
      clip.bars = next;
      const max = next * STEPS_PER_BAR;
      clip.notes = clip.notes.filter(n => n.step < max);
    }, 'clip');
  });

  const dbl = toolBtn('×2', () => {
    if (clip.bars >= 8) { toast('max 8 bars'); return; }
    store.mutate(() => {
      const len = clip.bars * STEPS_PER_BAR;
      const copies = clip.notes.map(n => ({ ...n, id: `${n.id}c`, step: n.step + len }));
      clip.bars *= 2;
      clip.notes.push(...copies);
    }, 'clip');
  });

  const clr = toolBtn('CLR', () => {
    if (!clip.notes.length) return;
    store.mutate(() => { clip.notes = []; }, 'clip');
    toast('clip cleared');
  });

  const kids = [name, h('span', { class: 'ed-meta' }, track.name), bars];

  if (track.type !== 'drum') {
    const lenBtn = toolBtn(`✎ ${lenLabel(store.ui.noteLen)}`, () => {
      store.ui.noteLen = { 1: 2, 2: 4, 4: 8, 8: 1 }[store.ui.noteLen] || 1;
      store.emit('clip');
    });
    kids.push(lenBtn);
  }
  kids.push(dbl, clr);
  return h('div', { class: 'editor-head' }, ...kids);
}

const lenLabel = (l) => ({ 1: '1/16', 2: '1/8', 4: '1/4', 8: '1/2' }[l] || `${l}`);

function toolBtn(label, fn, on = false) {
  const b = h('button', { class: `ed-tool${on ? ' on' : ''}` }, label);
  b.addEventListener('click', fn);
  return b;
}

// ============================================================
// drum step grid
// ============================================================

function drumGrid(track, clip) {
  const steps = clip.bars * STEPS_PER_BAR;
  colCells = Array.from({ length: steps }, () => []);

  const grid = h('div', {
    class: 'dgrid',
    style: `grid-template-columns: 64px repeat(${steps}, 34px); grid-template-rows: repeat(${DRUM_LANES.length}, 38px);`,
  });

  DRUM_LANES.forEach((lane, li) => {
    const label = h('button', { class: 'dlane-label' }, lane.name);
    label.addEventListener('click', () => engine.previewDrum(track.id, li));
    grid.append(label);

    for (let s = 0; s < steps; s++) {
      const note = clip.notes.find(n => n.pitch === li && n.step === s);
      const cell = h('button', {
        class: `dcell${s % 4 === 0 ? ' beat' : ''}${note ? (note.vel < 0.8 ? ' on soft' : ' on') : ''}`,
      });
      cell.addEventListener('click', () => {
        store.mutate(() => {
          const i = clip.notes.findIndex(n => n.pitch === li && n.step === s);
          if (i < 0) {
            clip.notes.push(makeNote(s, li, 1, 1));
            engine.previewDrum(track.id, li);
          } else if (clip.notes[i].vel >= 0.8) {
            clip.notes[i].vel = 0.55;   // second tap = ghost note
          } else {
            clip.notes.splice(i, 1);    // third tap = off
          }
        }, 'clip');
      });
      colCells[s].push(cell);
      grid.append(cell);
    }
  });

  scroller = h('div', { class: 'dgrid-wrap' }, grid);
  return scroller;
}

// ============================================================
// piano roll
// ============================================================

function pianoRoll(track, clip) {
  const steps = clip.bars * STEPS_PER_BAR;
  const rows = [];
  const width = KEY_W + steps * CELL_W;

  const roll = h('div', {
    class: 'proll',
    style: `width:${width}px; --cell-w:${CELL_W}px; --cell-h:${CELL_H}px;`,
  });

  for (let p = PITCH_MAX; p >= PITCH_MIN; p--) {
    const isBlack = [1, 3, 6, 8, 10].includes(p % 12);
    const row = h('div', { class: `proll-row${isBlack ? ' black' : ''}` });
    row.append(h('div', {
      class: `proll-key${p % 12 === 0 ? ' c-note' : ''}${isBlack ? ' black' : ''}`,
    }, p % 12 === 0 || !isBlack ? midiName(p) : ''));
    for (let s = 0; s < steps; s++) {
      row.append(h('div', {
        class: `proll-cell${(s + 1) % STEPS_PER_BAR === 0 ? ' bar' : (s + 1) % 4 === 0 ? ' beat' : ''}`,
      }));
    }
    roll.append(row);
    rows.push(row);
  }

  // notes overlay
  for (const n of clip.notes) {
    if (n.pitch > PITCH_MAX || n.pitch < PITCH_MIN) continue;
    const el = h('div', {
      class: `pnote${store.ui.selectedNote === n.id ? ' selected' : ''}`,
      dataset: { note: n.id },
      style: `left:${KEY_W + n.step * CELL_W + 1}px; top:${(PITCH_MAX - n.pitch) * CELL_H}px;` +
        `width:${n.len * CELL_W - 3}px; --vel-op:${0.45 + n.vel * 0.55};`,
    }, h('div', { class: 'pnote-tail' }));
    roll.append(el);
  }

  playheadEl = h('div', { class: 'playhead-v', style: 'display:none;' });
  roll.append(playheadEl);

  roll.addEventListener('click', (e) => {
    const noteEl = e.target.closest('.pnote');
    if (noteEl) {
      const id = noteEl.dataset.note;
      if (store.ui.selectedNote === id) {
        store.mutate(() => { clip.notes = clip.notes.filter(n => n.id !== id); }, 'clip');
        store.ui.selectedNote = null;
      } else {
        store.ui.selectedNote = id;
        store.emit('clip');
      }
      return;
    }
    const r = roll.getBoundingClientRect();
    const x = e.clientX - r.left - KEY_W;
    const y = e.clientY - r.top;
    if (x < 0) return;
    const step = Math.floor(x / CELL_W);
    const pitch = PITCH_MAX - Math.floor(y / CELL_H);
    if (step < 0 || step >= steps || pitch < PITCH_MIN || pitch > PITCH_MAX) return;
    const note = makeNote(step, pitch, 0.9, Math.min(store.ui.noteLen, steps - step));
    store.ui.selectedNote = note.id;
    store.mutate(() => { clip.notes.push(note); }, 'clip');
    engine.previewSynth(track.id, pitch);
  });

  scroller = h('div', { class: 'proll-wrap' }, roll);
  return scroller;
}

// ---------------- selected-note toolbar ----------------

function noteTools(track, clip) {
  const sel = clip.notes.find(n => n.id === store.ui.selectedNote);
  if (!sel) {
    return h('div', { class: 'note-tools' },
      h('span', { class: 'nt-label' }, 'tap grid to draw · tap note to select · tap again to delete'));
  }
  const steps = clip.bars * STEPS_PER_BAR;
  const mut = (fn) => store.mutate(fn, 'clip');

  return h('div', { class: 'note-tools' },
    h('span', { class: 'nt-label' }, `${midiName(sel.pitch)}·${sel.step + 1}`),
    ntBtn('◀', () => mut(() => { sel.step = Math.max(0, sel.step - 1); })),
    ntBtn('▶', () => mut(() => { sel.step = Math.min(steps - sel.len, sel.step + 1); })),
    ntBtn('▲', () => mut(() => {
      sel.pitch = Math.min(PITCH_MAX, sel.pitch + 1);
      engine.previewSynth(track.id, sel.pitch);
    })),
    ntBtn('▼', () => mut(() => {
      sel.pitch = Math.max(PITCH_MIN, sel.pitch - 1);
      engine.previewSynth(track.id, sel.pitch);
    })),
    ntBtn('LEN−', () => mut(() => { sel.len = Math.max(1, sel.len - 1); })),
    ntBtn('LEN+', () => mut(() => { sel.len = Math.min(steps - sel.step, sel.len + 1); })),
    ntBtn(`VEL ${Math.round(sel.vel * 100)}`, () => mut(() => {
      sel.vel = sel.vel > 0.85 ? 0.55 : sel.vel > 0.5 ? 0.3 : 1;
    })),
    ntBtn('✕ DEL', () => {
      mut(() => { clip.notes = clip.notes.filter(n => n.id !== sel.id); });
      store.ui.selectedNote = null;
    }, true),
  );
}

function ntBtn(label, fn, danger = false) {
  const b = h('button', { class: `nt-btn${danger ? ' danger' : ''}` }, label);
  b.addEventListener('click', fn);
  return b;
}

// ---------------- playhead ----------------

export function tick() {
  const clip = store.editingClip;
  const track = store.editingTrack;
  if (!clip || !track) return;

  const prog = engine.clipProgress(track.id);
  const ec = store.ui.editingClip;
  const active = prog && ec && prog.sceneIdx === ec.sceneIdx && engine.playing;

  if (track.type === 'drum') {
    const steps = clip.bars * STEPS_PER_BAR;
    const col = active ? prog.local % steps : -1;
    colCells.forEach((cells, s) => {
      const on = s === col;
      for (const c of cells) c.classList.toggle('playcol', on);
    });
  } else if (playheadEl) {
    if (active) {
      playheadEl.style.display = '';
      playheadEl.style.left = `${KEY_W + prog.frac * clip.bars * STEPS_PER_BAR * CELL_W}px`;
    } else {
      playheadEl.style.display = 'none';
    }
  }
}
