// ============================================================
// BR--KEN · state store
// Single source of truth for the project + UI state.
// Pub/sub events, bounded undo/redo, debounced localStorage persistence.
// ============================================================

const STORAGE_KEY = 'brkn.project.v1';
const MAX_UNDO = 60;

export const SCENES = 6;
export const STEPS_PER_BAR = 16;

export const TRACK_COLORS = ['#c8ff2e', '#43e8d8', '#ff5c7a', '#ffb02e', '#b18cff', '#5cc8ff'];

// Drum lanes are fixed: index in a pattern's `lane` field maps here.
export const DRUM_LANES = [
  { id: 'kick',  name: 'KICK'  },
  { id: 'snare', name: 'SNARE' },
  { id: 'clap',  name: 'CLAP'  },
  { id: 'chat',  name: 'HAT·C' },
  { id: 'ohat',  name: 'HAT·O' },
  { id: 'rim',   name: 'RIM'   },
  { id: 'tom',   name: 'TOM'   },
  { id: 'cow',   name: 'COW'   },
];

let _id = 0;
export const uid = () => `id${Date.now().toString(36)}${(_id++).toString(36)}`;

// ---------------- factories ----------------

export function makeClip(name = 'clip', bars = 1) {
  return { id: uid(), name, bars, notes: [] };
}

// note: { id, step, pitch (midi | lane index), vel 0..1, len (in 16th steps) }
export function makeNote(step, pitch, vel = 1, len = 1) {
  return { id: uid(), step, pitch, vel, len };
}

export function makeTrack(type, name, colorIdx = 0, presetId = 'lead') {
  return {
    id: uid(),
    type,                    // 'drum' | 'synth'
    name,
    color: TRACK_COLORS[colorIdx % TRACK_COLORS.length],
    presetId: type === 'drum' ? 'kit808' : presetId,
    mixer: { vol: 0.8, pan: 0, mute: false, solo: false, sendA: 0, sendB: 0 },
    clips: Array(SCENES).fill(null),
  };
}

export function emptyProject() {
  const p = {
    name: 'untitled',
    bpm: 120,
    swing: 0,
    tracks: [
      makeTrack('drum', 'DRUMS', 0),
      makeTrack('synth', 'BASS', 1, 'subbass'),
      makeTrack('synth', 'KEYS', 2, 'glasskeys'),
      makeTrack('synth', 'LEAD', 3, 'lead'),
    ],
  };
  return p;
}

// ---------------- store ----------------

class Store {
  constructor() {
    this.project = emptyProject();
    this.ui = {
      view: 'session',
      selectedTrack: 0,
      selectedScene: 0,
      editingClip: null,      // { trackId, sceneIdx } | null
      noteLen: 1,             // default note length for piano roll (16ths)
      octave: 3,              // pads base octave
      scaleRoot: 0,           // 0 = C
      scaleId: 'minor',
      selectedNote: null,     // note id in editing clip
    };
    this._subs = new Map();
    this._undo = [];
    this._redo = [];
    this._saveTimer = 0;
  }

  on(event, fn) {
    if (!this._subs.has(event)) this._subs.set(event, new Set());
    this._subs.get(event).add(fn);
    return () => this._subs.get(event).delete(fn);
  }

  emit(event, data) {
    const set = this._subs.get(event);
    if (set) for (const fn of set) fn(data);
    const all = this._subs.get('*');
    if (all) for (const fn of all) fn(event, data);
  }

  // --- undo/redo: snapshot the whole project (small enough to be cheap) ---

  checkpoint() {
    this._undo.push(JSON.stringify(this.project));
    if (this._undo.length > MAX_UNDO) this._undo.shift();
    this._redo.length = 0;
    this.emit('history');
  }

  undo() {
    if (!this._undo.length) return false;
    this._redo.push(JSON.stringify(this.project));
    this.project = JSON.parse(this._undo.pop());
    this._afterRestore();
    return true;
  }

  redo() {
    if (!this._redo.length) return false;
    this._undo.push(JSON.stringify(this.project));
    this.project = JSON.parse(this._redo.pop());
    this._afterRestore();
    return true;
  }

  get canUndo() { return this._undo.length > 0; }
  get canRedo() { return this._redo.length > 0; }

  _afterRestore() {
    // clamp UI refs that may have vanished
    if (this.ui.selectedTrack >= this.project.tracks.length) {
      this.ui.selectedTrack = Math.max(0, this.project.tracks.length - 1);
    }
    const ec = this.ui.editingClip;
    if (ec && !this.clipAt(ec.trackId, ec.sceneIdx)) this.ui.editingClip = null;
    this.ui.selectedNote = null;
    this.emit('project');
    this.emit('history');
    this.save();
  }

  // --- mutation helper: checkpoint → mutate → notify → persist ---

  mutate(fn, event = 'project') {
    this.checkpoint();
    fn(this.project);
    this.emit(event);
    this.save();
  }

  // silent tweak (no undo entry) — for continuous gestures like faders;
  // call checkpoint() once on gesture start instead.
  tweak(fn, event = 'project') {
    fn(this.project);
    this.emit(event);
    this.save();
  }

  // ---------------- lookups ----------------

  track(id) { return this.project.tracks.find(t => t.id === id); }
  trackAt(i) { return this.project.tracks[i]; }
  get selectedTrack() { return this.project.tracks[this.ui.selectedTrack]; }

  clipAt(trackId, sceneIdx) {
    const t = this.track(trackId);
    return t ? t.clips[sceneIdx] : null;
  }

  get editingClip() {
    const ec = this.ui.editingClip;
    return ec ? this.clipAt(ec.trackId, ec.sceneIdx) : null;
  }

  get editingTrack() {
    const ec = this.ui.editingClip;
    return ec ? this.track(ec.trackId) : null;
  }

  // ---------------- persistence ----------------

  save() {
    clearTimeout(this._saveTimer);
    this._saveTimer = setTimeout(() => {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(this.project));
      } catch (e) { /* storage full / private mode — non-fatal */ }
    }, 400);
  }

  load() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return false;
      const p = JSON.parse(raw);
      if (!p || !Array.isArray(p.tracks)) return false;
      this.project = p;
      return true;
    } catch (e) {
      return false;
    }
  }

  reset(project) {
    this.project = project;
    this._undo.length = 0;
    this._redo.length = 0;
    this.ui.selectedTrack = 0;
    this.ui.editingClip = null;
    this.ui.selectedNote = null;
    this.emit('project');
    this.emit('history');
    this.save();
  }
}

export const store = new Store();

// ============================================================
// Demo project — so the first tap already sounds like a track.
// A moody 122 BPM acid-adjacent groove in C minor.
// ============================================================

export function demoProject() {
  const p = emptyProject();
  p.name = 'first--light';
  p.bpm = 122;
  p.swing = 12;

  const [drums, bass, keys, lead] = p.tracks;
  const L = Object.fromEntries(DRUM_LANES.map((l, i) => [l.id, i]));

  // --- drum clips ---
  const beatA = makeClip('four--floor', 1);
  for (let s = 0; s < 16; s += 4) beatA.notes.push(makeNote(s, L.kick, 1));
  for (let s = 2; s < 16; s += 4) beatA.notes.push(makeNote(s, L.chat, s % 8 === 2 ? 0.9 : 0.55));
  beatA.notes.push(makeNote(4, L.clap, 0.9), makeNote(12, L.clap, 0.9));
  beatA.notes.push(makeNote(10, L.ohat, 0.5));

  const beatB = makeClip('broke--beat', 2);
  [0, 7, 10, 16, 23, 26].forEach(s => beatB.notes.push(makeNote(s, L.kick, 1)));
  [4, 12, 20, 28].forEach(s => beatB.notes.push(makeNote(s, L.snare, 0.95)));
  for (let s = 0; s < 32; s += 2) beatB.notes.push(makeNote(s, L.chat, s % 4 === 0 ? 0.7 : 0.4));
  beatB.notes.push(makeNote(14, L.ohat, 0.6), makeNote(30, L.ohat, 0.6));
  beatB.notes.push(makeNote(11, L.rim, 0.5), makeNote(27, L.rim, 0.5));

  const beatC = makeClip('half--time', 2);
  [0, 12, 16, 22].forEach(s => beatC.notes.push(makeNote(s, L.kick, 1)));
  [8, 24].forEach(s => beatC.notes.push(makeNote(s, L.snare, 1)));
  for (let s = 0; s < 32; s += 4) beatC.notes.push(makeNote(s + 2, L.chat, 0.45));
  beatC.notes.push(makeNote(26, L.tom, 0.7), makeNote(29, L.tom, 0.5));
  beatC.notes.push(makeNote(20, L.cow, 0.35));

  drums.clips[0] = beatA;
  drums.clips[1] = beatB;
  drums.clips[2] = beatC;
  drums.mixer.vol = 0.85;

  // --- bass: C minor riff (C2=36) ---
  const bass1 = makeClip('low--end', 2);
  const bl = [
    [0, 36, 3], [4, 36, 1], [6, 43, 1], [8, 36, 3], [12, 34, 1], [14, 39, 1],
    [16, 36, 3], [20, 36, 1], [22, 43, 1], [24, 41, 3], [28, 39, 1], [30, 34, 1],
  ];
  bl.forEach(([s, m, len]) => bass1.notes.push(makeNote(s, m, 0.95, len)));

  const bass2 = makeClip('drop--out', 2);
  [[0, 36, 6], [8, 36, 2], [16, 32, 6], [24, 34, 4]].forEach(([s, m, len]) =>
    bass2.notes.push(makeNote(s, m, 0.9, len)));

  bass.clips[0] = bass1;
  const bass1b = JSON.parse(JSON.stringify(bass1));
  bass1b.id = uid();
  bass.clips[1] = bass1b;
  bass.clips[2] = bass2;
  bass.mixer.vol = 0.75;
  bass.mixer.sendA = 0.0;

  // --- keys: Cm / Ab / Eb / Bb pad stabs (C4=60) ---
  const stabs = makeClip('night--stabs', 4);
  const chords = [
    [0,  [60, 63, 67]],   // Cm
    [16, [56, 60, 63]],   // Ab
    [32, [58, 63, 67]],   // Eb/G-ish
    [48, [58, 62, 65]],   // Bb
  ];
  chords.forEach(([s, ch]) => ch.forEach(m => {
    stabs.notes.push(makeNote(s, m, 0.7, 3));
    stabs.notes.push(makeNote(s + 10, m, 0.5, 2));
  }));
  keys.clips[0] = stabs;
  keys.mixer.vol = 0.6;
  keys.mixer.sendA = 0.35;
  keys.mixer.sendB = 0.4;

  // --- lead: sparse call in C minor pentatonic ---
  const hook = makeClip('cold--call', 4);
  const lm = [
    [0, 72, 2, 0.8], [3, 75, 1, 0.6], [6, 79, 3, 0.9], [12, 75, 2, 0.6],
    [16, 74, 2, 0.7], [22, 72, 4, 0.8],
    [32, 79, 2, 0.85], [35, 82, 1, 0.6], [38, 84, 5, 0.95],
    [48, 82, 2, 0.7], [52, 79, 3, 0.75], [58, 75, 4, 0.7],
  ];
  lm.forEach(([s, m, len, v]) => hook.notes.push(makeNote(s, m, v, len)));
  lead.clips[1] = hook;
  lead.mixer.vol = 0.55;
  lead.mixer.sendA = 0.45;
  lead.mixer.sendB = 0.3;

  return p;
}
