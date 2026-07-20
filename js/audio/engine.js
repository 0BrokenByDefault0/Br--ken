// ============================================================
// BR--KEN · engine
// Live transport + lookahead scheduler ("a tale of two clocks"),
// clip launcher state machine, channel management, live input.
// ============================================================

import { store, STEPS_PER_BAR, DRUM_LANES, makeNote } from '../state.js';
import { buildGraph, setDrive } from './graph.js';
import { triggerDrum, synthVoice } from './instruments.js';

const LOOKAHEAD_SEC = 0.12;
const TICK_MS = 25;

class Engine {
  constructor() {
    this.ctx = null;
    this.graph = null;
    this.channels = new Map();   // trackId -> {strip, analyser, meterBuf}
    this.masterAnalyser = null;

    this.playing = false;
    this.recording = false;
    this.metronome = false;

    this.step = 0;               // global 16th counter while playing
    this.nextStepTime = 0;
    this._timer = 0;

    // per-track clip launcher state: trackId -> {playing, queued, startStep}
    // queued: sceneIdx to start, 'stop' to stop, or null
    this.trackState = new Map();

    // (step, time) pairs the UI drains to draw the playhead in sync w/ audio
    this.stepQueue = [];

    // live note handles for pads: key -> voice
    this._held = new Map();
    this._recPending = new Map(); // key -> {trackId, sceneIdx, step, pitch, vel, startTime}
  }

  // ---------------- boot ----------------

  init() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    this.ctx = new AC({ latencyHint: 'interactive' });
    this.graph = buildGraph(this.ctx);

    this.masterAnalyser = this.ctx.createAnalyser();
    this.masterAnalyser.fftSize = 1024;
    this.graph.masterGain.connect(this.masterAnalyser);

    this.syncTracks();
    this.applyAllMixers();
    this.graph.setDelayTimes(store.project.bpm);

    store.on('project', () => { this.syncTracks(); this.applyAllMixers(); });
    store.on('mixer', () => this.applyAllMixers());
  }

  resume() { if (this.ctx && this.ctx.state !== 'running') this.ctx.resume(); }

  // create/destroy channel strips to match the project's tracks
  syncTracks() {
    const ids = new Set(store.project.tracks.map(t => t.id));
    for (const [id, ch] of this.channels) {
      if (!ids.has(id)) {
        ch.strip.input.disconnect();
        ch.strip.pan.disconnect();
        this.channels.delete(id);
        this.trackState.delete(id);
      }
    }
    for (const t of store.project.tracks) {
      if (!this.channels.has(t.id)) {
        const strip = this.graph.makeChannel();
        const analyser = this.ctx.createAnalyser();
        analyser.fftSize = 256;
        strip.pan.connect(analyser);
        this.channels.set(t.id, { strip, analyser, meterBuf: new Float32Array(analyser.fftSize) });
      }
      if (!this.trackState.has(t.id)) {
        this.trackState.set(t.id, { playing: null, queued: null, startStep: 0 });
      }
    }
  }

  applyAllMixers() {
    const tracks = store.project.tracks;
    const anySolo = tracks.some(t => t.mixer.solo);
    const now = this.ctx.currentTime;
    for (const t of tracks) {
      const ch = this.channels.get(t.id);
      if (!ch) continue;
      const m = t.mixer;
      const audible = !m.mute && (!anySolo || m.solo);
      ch.strip.gain.gain.setTargetAtTime(audible ? m.vol * m.vol : 0, now, 0.02);
      if (ch.strip.pan.pan) ch.strip.pan.pan.setTargetAtTime(m.pan, now, 0.02);
      ch.strip.sendA.gain.setTargetAtTime(m.sendA, now, 0.02);
      ch.strip.sendB.gain.setTargetAtTime(m.sendB, now, 0.02);
    }
  }

  // ---------------- transport ----------------

  get stepDur() { return 60 / store.project.bpm / 4; }

  play() {
    if (this.playing) return;
    this.init();
    this.resume();
    this.playing = true;
    this.step = 0;
    this.stepQueue.length = 0;
    this._lastAudible = null;
    for (const st of this.trackState.values()) st.startStep = 0;
    this.nextStepTime = this.ctx.currentTime + 0.08;
    // anything queued fires immediately at step 0
    this._timer = setInterval(() => this._tick(), TICK_MS);
    store.emit('transport');
  }

  stop() {
    if (!this.playing) {
      // second stop press = panic: also clear playing clips
      for (const st of this.trackState.values()) { st.playing = null; st.queued = null; }
      store.emit('transport');
      return;
    }
    this.playing = false;
    clearInterval(this._timer);
    this.stepQueue.length = 0;
    for (const st of this.trackState.values()) st.queued = null;
    this._releaseAllHeld();
    store.emit('transport');
  }

  toggleRecord() {
    this.recording = !this.recording;
    store.emit('transport');
  }

  toggleMetronome() {
    this.metronome = !this.metronome;
    store.emit('transport');
  }

  // ---------------- clip launcher ----------------

  launchClip(trackId, sceneIdx) {
    this.init();
    this.resume();
    const st = this.trackState.get(trackId);
    if (!st) return;
    st.queued = sceneIdx;
    if (!this.playing) this.play();
    store.emit('clips');
  }

  stopTrack(trackId) {
    const st = this.trackState.get(trackId);
    if (!st) return;
    if (this.playing && st.playing != null) st.queued = 'stop';
    else { st.playing = null; st.queued = null; }
    store.emit('clips');
  }

  launchScene(sceneIdx) {
    this.init();
    this.resume();
    for (const t of store.project.tracks) {
      const st = this.trackState.get(t.id);
      if (!st) continue;
      if (t.clips[sceneIdx]) st.queued = sceneIdx;
      else if (st.playing != null) st.queued = 'stop';
    }
    if (!this.playing) this.play();
    store.emit('clips');
  }

  stopAllClips() {
    for (const t of store.project.tracks) this.stopTrack(t.id);
  }

  // ---------------- scheduler ----------------

  _tick() {
    const horizon = this.ctx.currentTime + LOOKAHEAD_SEC;
    while (this.nextStepTime < horizon) {
      this._scheduleStep(this.step, this.nextStepTime);
      this.nextStepTime += this.stepDur;
      this.step++;
    }
  }

  _scheduleStep(step, time) {
    const proj = store.project;
    const stepDur = this.stepDur;

    // bar boundary: commit queued clip switches
    if (step % STEPS_PER_BAR === 0) {
      let changed = false;
      for (const [, st] of this.trackState) {
        if (st.queued != null) {
          st.playing = st.queued === 'stop' ? null : st.queued;
          st.startStep = step;
          st.queued = null;
          changed = true;
        }
      }
      if (changed) store.emit('clips');
    }

    // metronome click on quarter notes
    if (this.metronome && step % 4 === 0) {
      this._click(time, step % STEPS_PER_BAR === 0);
    }

    // swing: push every odd 16th later
    const swung = (s) => (s % 2 === 1 ? (proj.swing / 100) * stepDur * 0.55 : 0);

    for (const t of proj.tracks) {
      const st = this.trackState.get(t.id);
      if (!st || st.playing == null) continue;
      const clip = t.clips[st.playing];
      if (!clip) { st.playing = null; continue; }
      const clipSteps = clip.bars * STEPS_PER_BAR;
      const local = ((step - st.startStep) % clipSteps + clipSteps) % clipSteps;
      const ch = this.channels.get(t.id);
      if (!ch) continue;
      for (const n of clip.notes) {
        if (n.step !== local) continue;
        const at = time + swung(step);
        if (t.type === 'drum') {
          const lane = DRUM_LANES[n.pitch];
          if (lane) triggerDrum(this.ctx, ch.strip.input, lane.id, at, n.vel);
        } else {
          const dur = Math.max(n.len, 0.5) * stepDur * 0.98;
          synthVoice(this.ctx, ch.strip.input, t.presetId, n.pitch, at, n.vel, dur);
        }
      }
    }

    this.stepQueue.push({ step, time });
    if (this.stepQueue.length > 128) this.stepQueue.splice(0, 64);
  }

  _click(time, downbeat) {
    const o = this.ctx.createOscillator();
    o.type = 'sine';
    o.frequency.value = downbeat ? 1568 : 1046;
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0.12, time);
    g.gain.exponentialRampToValueAtTime(0.0001, time + 0.05);
    o.connect(g).connect(this.graph.masterGain);
    o.start(time); o.stop(time + 0.06);
  }

  // current audible step (UI playhead) — drains the schedule queue
  currentAudibleStep() {
    if (!this.playing || !this.ctx) return null;
    const now = this.ctx.currentTime;
    let last = null;
    while (this.stepQueue.length && this.stepQueue[0].time <= now) {
      last = this.stepQueue.shift();
    }
    if (last) this._lastAudible = last;
    return this._lastAudible?.step ?? null;
  }

  // playhead position within a track's playing clip, 0..1
  clipProgress(trackId) {
    const st = this.trackState.get(trackId);
    if (!st || st.playing == null || !this.playing) return null;
    const t = store.track(trackId);
    const clip = t?.clips[st.playing];
    if (!clip) return null;
    const cur = this._lastAudible?.step;
    if (cur == null) return 0;
    const clipSteps = clip.bars * STEPS_PER_BAR;
    const local = ((cur - st.startStep) % clipSteps + clipSteps) % clipSteps;
    return { sceneIdx: st.playing, frac: local / clipSteps, local };
  }

  // ---------------- live input (pads / audition) ----------------

  _keyFor(trackId, pitch) { return `${trackId}:${pitch}`; }

  noteOn(trackId, midi, vel = 1) {
    this.init();
    this.resume();
    const t = store.track(trackId);
    const ch = this.channels.get(trackId);
    if (!t || !ch) return;
    const key = this._keyFor(trackId, midi);
    this.noteOff(trackId, midi); // retrigger safety
    const voice = synthVoice(this.ctx, ch.strip.input, t.presetId, midi, this.ctx.currentTime, vel);
    this._held.set(key, voice);
    this._maybeRecordStart(key, trackId, midi, vel);
  }

  noteOff(trackId, midi) {
    const key = this._keyFor(trackId, midi);
    const v = this._held.get(key);
    if (v) { v.release(); this._held.delete(key); }
    this._maybeRecordEnd(key);
  }

  hitDrum(trackId, laneIdx, vel = 1) {
    this.init();
    this.resume();
    const ch = this.channels.get(trackId);
    const lane = DRUM_LANES[laneIdx];
    if (!ch || !lane) return;
    triggerDrum(this.ctx, ch.strip.input, lane.id, this.ctx.currentTime, vel);
    const key = this._keyFor(trackId, `d${laneIdx}`);
    this._maybeRecordStart(key, trackId, laneIdx, vel, true);
    this._maybeRecordEnd(key);
  }

  // short audition notes — never recorded
  previewDrum(trackId, laneIdx, vel = 0.9) {
    this.init();
    this.resume();
    const ch = this.channels.get(trackId);
    const lane = DRUM_LANES[laneIdx];
    if (ch && lane) triggerDrum(this.ctx, ch.strip.input, lane.id, this.ctx.currentTime, vel);
  }

  previewSynth(trackId, midi, vel = 0.85) {
    this.init();
    this.resume();
    const t = store.track(trackId);
    const ch = this.channels.get(trackId);
    if (!t || !ch) return;
    synthVoice(this.ctx, ch.strip.input, t.presetId, midi, this.ctx.currentTime, vel, 0.22);
  }

  _releaseAllHeld() {
    for (const v of this._held.values()) v.release();
    this._held.clear();
    this._recPending.clear();
  }

  // ---------------- live recording into the playing clip ----------------

  _recTarget(trackId) {
    if (!this.recording || !this.playing) return null;
    const st = this.trackState.get(trackId);
    if (!st || st.playing == null) return null;
    const t = store.track(trackId);
    const clip = t?.clips[st.playing];
    if (!clip) return null;
    return { st, clip, sceneIdx: st.playing };
  }

  _liveStep(st, clip) {
    // where are we *right now* (not the last scheduled step)
    const now = this.ctx.currentTime;
    const ahead = (now - (this._lastAudible?.time ?? now)) / this.stepDur;
    const cur = (this._lastAudible?.step ?? 0) + ahead;
    const clipSteps = clip.bars * STEPS_PER_BAR;
    const local = ((cur - st.startStep) % clipSteps + clipSteps) % clipSteps;
    return { local, clipSteps };
  }

  _maybeRecordStart(key, trackId, pitch, vel, isDrum = false) {
    const target = this._recTarget(trackId);
    if (!target) return;
    const { st, clip, sceneIdx } = target;
    const { local, clipSteps } = this._liveStep(st, clip);
    const qStep = Math.round(local) % clipSteps;
    this._recPending.set(key, {
      trackId, sceneIdx, clipId: clip.id,
      step: qStep, pitch, vel,
      startTime: this.ctx.currentTime, isDrum,
    });
  }

  _maybeRecordEnd(key) {
    const pend = this._recPending.get(key);
    if (!pend) return;
    this._recPending.delete(key);
    const clip = store.clipAt(pend.trackId, pend.sceneIdx);
    if (!clip || clip.id !== pend.clipId) return;
    const heldSec = this.ctx.currentTime - pend.startTime;
    const len = pend.isDrum ? 1 : Math.max(1, Math.round(heldSec / this.stepDur));
    store.mutate(() => {
      // replace an identical-pitch note on the same step rather than stacking
      clip.notes = clip.notes.filter(n => !(n.step === pend.step && n.pitch === pend.pitch));
      clip.notes.push(makeNote(pend.step, pend.pitch, pend.vel, len));
    }, 'recorded');
  }

  // ---------------- metering ----------------

  channelLevel(trackId) {
    const ch = this.channels.get(trackId);
    if (!ch) return 0;
    ch.analyser.getFloatTimeDomainData(ch.meterBuf);
    let sum = 0;
    for (let i = 0; i < ch.meterBuf.length; i++) sum += ch.meterBuf[i] ** 2;
    return Math.sqrt(sum / ch.meterBuf.length);
  }

  // ---------------- FX controls ----------------

  setXY(x, y) {
    // x: filter cutoff 80..18k (log) · y: delay feedback 0..0.85
    if (!this.graph) return;
    const now = this.ctx.currentTime;
    const cutoff = 80 * Math.pow(18000 / 80, x);
    this.graph.xyFilter.frequency.setTargetAtTime(cutoff, now, 0.02);
    const fb = y * 0.85;
    this.graph.delay.fbL.gain.setTargetAtTime(fb, now, 0.02);
    this.graph.delay.fbR.gain.setTargetAtTime(fb, now, 0.02);
  }

  resetXY() {
    if (!this.graph) return;
    const now = this.ctx.currentTime;
    this.graph.xyFilter.frequency.setTargetAtTime(18000, now, 0.08);
    this.graph.delay.fbL.gain.setTargetAtTime(0.35, now, 0.08);
    this.graph.delay.fbR.gain.setTargetAtTime(0.35, now, 0.08);
  }

  setDriveAmount(v) { if (this.graph) setDrive(this.graph.drive, v); }
  setReverbLevel(v) {
    if (this.graph) this.graph.reverb.out.gain.setTargetAtTime(v * 1.6, this.ctx.currentTime, 0.03);
  }
  setDelayLevel(v) {
    if (this.graph) this.graph.delay.out.gain.setTargetAtTime(v * 1.4, this.ctx.currentTime, 0.03);
  }
  setMasterVolume(v) {
    if (this.graph) this.graph.masterGain.gain.setTargetAtTime(v, this.ctx.currentTime, 0.03);
  }
  setBpm(bpm) {
    if (this.graph) this.graph.setDelayTimes(bpm);
  }
}

export const engine = new Engine();
