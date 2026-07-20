// ============================================================
// BR--KEN · main
// Boot, view routing, transport bar, menu sheet, rAF loop.
// ============================================================

import { store, emptyProject, demoProject } from './state.js';
import { engine } from './audio/engine.js';
import { exportSceneToWav } from './audio/export.js';
import { toast } from './ui/components.js';
import * as session from './ui/session.js';
import * as editor from './ui/editor.js';
import * as keys from './ui/keys.js';
import * as mixer from './ui/mixer.js';
import * as fx from './ui/fx.js';

const VIEWS = { session, editor, keys, mixer, fx };

// console access for tinkering + automated tests
window.__brkn = { store, engine };

const $ = (id) => document.getElementById(id);
const viewEl = $('view');
let currentView = 'session';

// ---------------- boot ----------------

if (!store.load()) store.reset(demoProject());

$('boot-start').addEventListener('click', () => {
  engine.init();
  engine.resume();
  $('boot').remove();
  $('app').hidden = false;
  setView('session');
  syncTopbar();
  requestAnimationFrame(frame);
});

// ---------------- view routing ----------------

function setView(name) {
  currentView = name;
  document.querySelectorAll('.tab').forEach(t =>
    t.classList.toggle('active', t.dataset.view === name));
  if (name === 'editor' && !store.ui.editingClip) {
    // default to the selected track's clip in the selected scene, if any
    const t = store.selectedTrack;
    if (t && t.clips[store.ui.selectedScene]) {
      store.ui.editingClip = { trackId: t.id, sceneIdx: store.ui.selectedScene };
    }
  }
  VIEWS[name].render(viewEl);
}

$('tabs').addEventListener('click', (e) => {
  const tab = e.target.closest('.tab');
  if (tab) setView(tab.dataset.view);
});

store.on('navigate', (name) => setView(name));

// re-render the active view when the underlying data changes
store.on('project', () => { VIEWS[currentView].render(viewEl); syncTopbar(); });
store.on('clip', () => VIEWS[currentView].render(viewEl));
// live-recorded notes: only refresh the editor, never yank the pads
// out from under held fingers in the PLAY view
store.on('recorded', () => { if (currentView === 'editor') editor.render(viewEl); });

// ---------------- transport controls ----------------

$('t-play').addEventListener('click', () => {
  if (engine.playing) return;
  // nothing queued or playing → fire the selected scene so play always plays
  const anyActive = [...engine.trackState.values()].some(s => s.playing != null || s.queued != null);
  if (!anyActive) engine.launchScene(store.ui.selectedScene);
  else engine.play();
});

$('t-stop').addEventListener('click', () => engine.stop());
$('t-rec').addEventListener('click', () => engine.toggleRecord());
$('t-metro').addEventListener('click', () => engine.toggleMetronome());

store.on('transport', syncTransportButtons);
store.on('clips', () => { if (currentView === 'session') { /* tick handles visuals */ } });

function syncTransportButtons() {
  $('t-play').classList.toggle('on', engine.playing);
  $('t-rec').classList.toggle('on', engine.recording);
  $('t-metro').classList.toggle('on', engine.metronome);
}

// ---------------- BPM control (drag vertically / tap sides) ----------------

{
  const box = $('bpm-box');
  const val = $('bpm-val');
  let startY = 0, startBpm = 0, dragging = false, moved = false;

  const setBpm = (bpm, checkpoint = false) => {
    bpm = Math.max(50, Math.min(220, Math.round(bpm)));
    if (bpm === store.project.bpm) return;
    const apply = () => { store.project.bpm = bpm; };
    checkpoint ? store.mutate(apply, 'bpm') : store.tweak(apply, 'bpm');
    engine.setBpm(bpm);
    val.textContent = bpm;
  };

  box.addEventListener('pointerdown', (e) => {
    dragging = true; moved = false;
    startY = e.clientY;
    startBpm = store.project.bpm;
    box.setPointerCapture(e.pointerId);
    e.preventDefault();
  });
  box.addEventListener('pointermove', (e) => {
    if (!dragging) return;
    const dy = startY - e.clientY;
    if (Math.abs(dy) > 4) moved = true;
    if (moved) setBpm(startBpm + dy / 5);
  });
  box.addEventListener('pointerup', (e) => {
    dragging = false;
    if (!moved) {
      const r = box.getBoundingClientRect();
      const x = e.clientX - r.left;
      setBpm(store.project.bpm + (x < r.width / 2 ? -1 : 1), true);
    } else {
      store.save();
    }
  });
  box.addEventListener('pointercancel', () => { dragging = false; });
  store.on('bpm', () => { val.textContent = store.project.bpm; });
}

// ---------------- undo / redo ----------------

$('undo-btn').addEventListener('click', () => {
  if (store.undo()) toast('undo'); syncHistory();
});
$('redo-btn').addEventListener('click', () => {
  if (store.redo()) toast('redo'); syncHistory();
});
store.on('history', syncHistory);

function syncHistory() {
  $('undo-btn').disabled = !store.canUndo;
  $('redo-btn').disabled = !store.canRedo;
}

// ---------------- menu sheet ----------------

const sheet = $('sheet');

$('menu-btn').addEventListener('click', () => {
  $('proj-name').value = store.project.name;
  $('m-swing').value = store.project.swing;
  $('m-swing-val').textContent = `${store.project.swing}%`;
  sheet.hidden = false;
});
sheet.querySelector('[data-close]').addEventListener('click', () => { sheet.hidden = true; });

$('proj-name').addEventListener('change', () => {
  store.tweak(p => { p.name = $('proj-name').value.trim().slice(0, 32) || 'untitled'; });
});

$('m-save').addEventListener('click', () => {
  store.save();
  toast('saved to this device');
  sheet.hidden = true;
});

$('m-new').addEventListener('click', () => {
  if (!confirm('start a new empty project? current project will be replaced.')) return;
  engine.stop();
  engine.stopAllClips();
  store.reset(emptyProject());
  sheet.hidden = true;
  setView('session');
  toast('new project');
});

$('m-demo').addEventListener('click', () => {
  if (!confirm('load the demo project? current project will be replaced.')) return;
  engine.stop();
  engine.stopAllClips();
  store.reset(demoProject());
  sheet.hidden = true;
  setView('session');
  toast('demo loaded — hit a scene ▶');
});

$('m-export').addEventListener('click', async () => {
  const scene = store.ui.selectedScene;
  sheet.hidden = true;
  toast(`rendering scene ${scene + 1}…`, 60000);
  try {
    // give the toast a frame to paint before the render blocks
    await new Promise(r => setTimeout(r, 50));
    const name = await exportSceneToWav(store.project, scene);
    toast(`exported ${name}`);
  } catch (err) {
    toast(err.message === 'scene is empty'
      ? `scene ${scene + 1} is empty — tap a clip first`
      : `export failed: ${err.message}`);
  }
});

$('m-swing').addEventListener('input', () => {
  const v = +$('m-swing').value;
  store.tweak(p => { p.swing = v; }, 'bpm');
  $('m-swing-val').textContent = `${v}%`;
});

// ---------------- topbar sync ----------------

function syncTopbar() {
  $('bpm-val').textContent = store.project.bpm;
  syncTransportButtons();
  syncHistory();
}

// ---------------- keyboard (desktop) ----------------

window.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return;
  if (e.code === 'Space') {
    e.preventDefault();
    engine.playing ? engine.stop() : $('t-play').click();
  } else if (e.key === 'z' && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    e.shiftKey ? store.redo() : store.undo();
  } else if (e.key >= '1' && e.key <= '5') {
    setView(['session', 'editor', 'keys', 'mixer', 'fx'][+e.key - 1]);
  }
});

// prevent iOS double-tap zoom on fast taps
document.addEventListener('dblclick', (e) => {
  if (!e.target.closest('.knob-dial')) e.preventDefault();
}, { passive: false });

// ---------------- animation frame loop ----------------

const posEl = $('pos-display');

function frame() {
  const step = engine.currentAudibleStep();
  if (step != null) {
    posEl.textContent = `${Math.floor(step / 16) + 1}.${Math.floor((step % 16) / 4) + 1}`;
  } else if (!engine.playing) {
    posEl.textContent = '1.1';
  }
  VIEWS[currentView].tick?.();
  requestAnimationFrame(frame);
}
