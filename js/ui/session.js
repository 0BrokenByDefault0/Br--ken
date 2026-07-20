// ============================================================
// BR--KEN · session view
// Ableton-style clip launch grid: tracks × scenes.
// tap clip = launch (quantized) · long-press = edit
// tap empty slot = select · long-press empty = create clip
// ============================================================

import { store, SCENES, makeClip, makeTrack, TRACK_COLORS } from '../state.js';
import { engine } from '../audio/engine.js';
import { h, pressable, toast } from './components.js';

let root = null;
let clipEls = new Map();   // `${trackId}:${scene}` -> {cell, progress}

export function render(container) {
  root = container;
  clipEls = new Map();
  const proj = store.project;
  const nT = proj.tracks.length;

  const grid = h('div', {
    class: 'session-grid',
    style: `grid-template-columns: repeat(${nT}, minmax(86px, 1fr)) 46px;`,
  });

  // header row: track heads + scene col label
  proj.tracks.forEach((t, ti) => {
    const head = h('div', {
      class: `trk-head${ti === store.ui.selectedTrack ? ' selected' : ''}`,
      style: `border-top: 2px solid ${t.color};`,
    },
      h('div', { class: 'trk-name' }, t.name),
      h('div', { class: 'trk-type' }, t.type === 'drum' ? 'DRUM·KIT' : t.presetId.toUpperCase()),
    );
    pressable(head, {
      onTap: () => { store.ui.selectedTrack = ti; render(root); },
      onLongPress: () => renameTrack(t),
    });
    grid.append(head);
  });
  grid.append(h('div', { class: 'trk-head sticky-r', style: 'align-items:center;' },
    h('div', { class: 'trk-type' }, 'SCN')));

  // clip rows
  for (let s = 0; s < SCENES; s++) {
    proj.tracks.forEach((t, ti) => {
      const clip = t.clips[s];
      const cell = h('div', {
        class: `clip${clip ? ' has' : ''}`,
        style: `--clip-c: ${t.color};`,
      });
      if (clip) {
        cell.append(
          h('div', { class: 'clip-progress' }),
          h('div', { class: 'clip-glyph' }, '▶'),
          h('div', { class: 'clip-name' }, clip.name),
        );
        clipEls.set(`${t.id}:${s}`, {
          cell,
          progress: cell.querySelector('.clip-progress'),
          glyph: cell.querySelector('.clip-glyph'),
        });
      }
      pressable(cell, {
        onTap: () => {
          store.ui.selectedTrack = ti;
          store.ui.selectedScene = s;
          if (clip) {
            store.ui.editingClip = { trackId: t.id, sceneIdx: s };
            engine.launchClip(t.id, s);
          }
          render(root);
        },
        onLongPress: () => {
          store.ui.selectedTrack = ti;
          store.ui.selectedScene = s;
          if (!clip) {
            store.mutate(p => {
              p.tracks[ti].clips[s] = makeClip(newClipName(t), t.type === 'drum' ? 1 : 2);
            });
          }
          store.ui.editingClip = { trackId: t.id, sceneIdx: s };
          store.ui.selectedNote = null;
          store.emit('navigate', 'editor');
        },
      });
      grid.append(cell);
    });
    // scene launch cell
    const scn = h('button', { class: 'scene-cell sticky-r' }, `▶${s + 1}`);
    scn.addEventListener('click', () => { store.ui.selectedScene = s; engine.launchScene(s); });
    grid.append(scn);
  }

  // stop row
  proj.tracks.forEach((t) => {
    const stop = h('button', { class: 'stop-cell' }, '■');
    stop.addEventListener('click', () => engine.stopTrack(t.id));
    grid.append(stop);
  });
  const stopAll = h('button', { class: 'stop-cell sticky-r', style: 'color: var(--coral);' }, '■');
  stopAll.addEventListener('click', () => engine.stopAllClips());
  grid.append(stopAll);

  // action bar
  const actions = h('div', { class: 'session-actions' },
    actionBtn('+ SYNTH', () => addTrack('synth')),
    actionBtn('+ DRUM', () => addTrack('drum')),
    actionBtn('✕ TRACK', deleteSelectedTrack),
    actionBtn('■ STOP ALL', () => engine.stopAllClips()),
  );

  container.replaceChildren(
    h('div', { class: 'session' },
      h('div', { class: 'session-scroll' }, grid),
      actions,
    ),
  );
}

function actionBtn(label, fn) {
  const b = h('button', { class: 'sess-btn' }, label);
  b.addEventListener('click', fn);
  return b;
}

function newClipName(track) {
  const n = track.clips.filter(Boolean).length + 1;
  return `${track.name.toLowerCase().slice(0, 5)}--${n}`;
}

function addTrack(type) {
  if (store.project.tracks.length >= 8) { toast('max 8 tracks'); return; }
  store.mutate(p => {
    const idx = p.tracks.length;
    const name = type === 'drum' ? `DRUMS ${idx + 1}` : `SYNTH ${idx + 1}`;
    p.tracks.push(makeTrack(type, name, idx % TRACK_COLORS.length,
      type === 'drum' ? 'kit808' : ['lead', 'pluck', 'pad', 'acid', 'bell'][idx % 5]));
  });
  store.ui.selectedTrack = store.project.tracks.length - 1;
  render(root);
  toast(`${type} track added`);
}

function deleteSelectedTrack() {
  const t = store.selectedTrack;
  if (!t) return;
  if (store.project.tracks.length <= 1) { toast('keep at least one track'); return; }
  if (!confirm(`delete track "${t.name}"?`)) return;
  engine.stopTrack(t.id);
  store.mutate(p => {
    p.tracks = p.tracks.filter(x => x.id !== t.id);
  });
  store.ui.selectedTrack = Math.max(0, store.ui.selectedTrack - 1);
  if (store.ui.editingClip?.trackId === t.id) store.ui.editingClip = null;
  render(root);
}

function renameTrack(t) {
  const name = prompt('track name', t.name);
  if (name == null) return;
  store.mutate(() => { t.name = name.trim().slice(0, 16).toUpperCase() || t.name; });
  render(root);
}

// per-frame updates: play state, queue blink, progress bars
export function tick() {
  if (!root) return;
  for (const t of store.project.tracks) {
    const st = engine.trackState.get(t.id);
    for (let s = 0; s < SCENES; s++) {
      const ref = clipEls.get(`${t.id}:${s}`);
      if (!ref) continue;
      const isPlaying = st?.playing === s && engine.playing;
      const isQueued = st?.queued === s;
      ref.cell.classList.toggle('playing', isPlaying);
      ref.cell.classList.toggle('queued', isQueued);
      ref.glyph.textContent = isPlaying ? '❚❚' : '▶';
      if (isPlaying) {
        const prog = engine.clipProgress(t.id);
        ref.progress.style.width = prog ? `${prog.frac * 100}%` : '0%';
      } else {
        ref.progress.style.width = '0%';
      }
    }
  }
}
