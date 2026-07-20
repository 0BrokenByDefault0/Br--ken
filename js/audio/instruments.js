// ============================================================
// BR--KEN · instruments
// Pure synthesis — every voice is built from (ctx, dest, time, ...)
// so identical code drives the live AudioContext and the
// OfflineAudioContext used for WAV export.
// ============================================================

export const midiToFreq = (m) => 440 * Math.pow(2, (m - 69) / 12);

// ---------------- shared noise buffer (cached per context) ----------------

const noiseCache = new WeakMap();

export function noiseBuffer(ctx) {
  let buf = noiseCache.get(ctx);
  if (!buf) {
    const len = ctx.sampleRate * 2;
    buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    noiseCache.set(ctx, buf);
  }
  return buf;
}

function noiseSource(ctx, time, dur) {
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(ctx);
  src.loop = true;
  src.start(time, Math.random() * 1.5); // random offset → no machine-gun effect
  src.stop(time + dur);
  return src;
}

// tiny helper: gain node with an exponential-ish decay envelope
function envGain(ctx, time, peak, decay, curve = 0.0001) {
  const g = ctx.createGain();
  g.gain.setValueAtTime(Math.max(peak, curve), time);
  g.gain.exponentialRampToValueAtTime(curve, time + decay);
  return g;
}

// ============================================================
// DRUMS — analog-style voices, lane ids match state.DRUM_LANES
// ============================================================

const drumVoices = {

  kick(ctx, dest, time, vel) {
    // body: sine with fast pitch drop
    const osc = ctx.createOscillator();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(150, time);
    osc.frequency.exponentialRampToValueAtTime(48, time + 0.08);
    osc.frequency.exponentialRampToValueAtTime(38, time + 0.4);
    const g = envGain(ctx, time, vel * 1.1, 0.42);
    // click transient
    const click = ctx.createOscillator();
    click.type = 'square';
    click.frequency.setValueAtTime(1200, time);
    const cg = envGain(ctx, time, vel * 0.25, 0.012);
    osc.connect(g).connect(dest);
    click.connect(cg).connect(dest);
    osc.start(time); osc.stop(time + 0.5);
    click.start(time); click.stop(time + 0.03);
  },

  snare(ctx, dest, time, vel) {
    // tone
    const osc = ctx.createOscillator();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(238, time);
    osc.frequency.exponentialRampToValueAtTime(170, time + 0.06);
    const og = envGain(ctx, time, vel * 0.5, 0.1);
    osc.connect(og).connect(dest);
    osc.start(time); osc.stop(time + 0.15);
    // noise crack
    const n = noiseSource(ctx, time, 0.25);
    const bp = ctx.createBiquadFilter();
    bp.type = 'highpass'; bp.frequency.value = 1800; bp.Q.value = 0.8;
    const ng = envGain(ctx, time, vel * 0.7, 0.18);
    n.connect(bp).connect(ng).connect(dest);
  },

  clap(ctx, dest, time, vel) {
    const bp = ctx.createBiquadFilter();
    bp.type = 'bandpass'; bp.frequency.value = 1400; bp.Q.value = 1.4;
    const out = ctx.createGain();
    bp.connect(out).connect(dest);
    // 3 quick bursts + tail
    for (let i = 0; i < 3; i++) {
      const t = time + i * 0.011;
      const n = noiseSource(ctx, t, 0.06);
      n.connect(envGain(ctx, t, vel * 0.55, 0.03)).connect(bp);
    }
    const tail = noiseSource(ctx, time + 0.028, 0.3);
    tail.connect(envGain(ctx, time + 0.028, vel * 0.6, 0.22)).connect(bp);
  },

  chat(ctx, dest, time, vel) {
    hatVoice(ctx, dest, time, vel * 0.6, 0.045);
  },

  ohat(ctx, dest, time, vel) {
    hatVoice(ctx, dest, time, vel * 0.6, 0.4);
  },

  rim(ctx, dest, time, vel) {
    const osc = ctx.createOscillator();
    osc.type = 'square';
    osc.frequency.setValueAtTime(1720, time);
    const bp = ctx.createBiquadFilter();
    bp.type = 'bandpass'; bp.frequency.value = 3600; bp.Q.value = 3;
    const g = envGain(ctx, time, vel * 0.7, 0.045);
    osc.connect(bp).connect(g).connect(dest);
    osc.start(time); osc.stop(time + 0.06);
  },

  tom(ctx, dest, time, vel) {
    const osc = ctx.createOscillator();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(210, time);
    osc.frequency.exponentialRampToValueAtTime(92, time + 0.25);
    const g = envGain(ctx, time, vel * 0.9, 0.3);
    osc.connect(g).connect(dest);
    osc.start(time); osc.stop(time + 0.35);
    const n = noiseSource(ctx, time, 0.05);
    n.connect(envGain(ctx, time, vel * 0.15, 0.03)).connect(dest);
  },

  cow(ctx, dest, time, vel) {
    // two detuned squares — the classic 808 cowbell trick
    const bp = ctx.createBiquadFilter();
    bp.type = 'bandpass'; bp.frequency.value = 2640; bp.Q.value = 1;
    const g = envGain(ctx, time, vel * 0.45, 0.3);
    bp.connect(g).connect(dest);
    for (const f of [540, 800]) {
      const o = ctx.createOscillator();
      o.type = 'square';
      o.frequency.value = f;
      o.connect(bp);
      o.start(time); o.stop(time + 0.35);
    }
  },
};

function hatVoice(ctx, dest, time, peak, decay) {
  // six square oscillators at inharmonic ratios → metallic wash
  const ratios = [2, 3, 4.16, 5.43, 6.79, 8.21];
  const bp = ctx.createBiquadFilter();
  bp.type = 'bandpass'; bp.frequency.value = 10000; bp.Q.value = 0.6;
  const hp = ctx.createBiquadFilter();
  hp.type = 'highpass'; hp.frequency.value = 7000;
  const g = envGain(ctx, time, peak, decay);
  bp.connect(hp).connect(g).connect(dest);
  for (const r of ratios) {
    const o = ctx.createOscillator();
    o.type = 'square';
    o.frequency.value = 40 * r * 2;
    o.connect(bp);
    o.start(time); o.stop(time + decay + 0.05);
  }
}

export function triggerDrum(ctx, dest, laneId, time, vel = 1) {
  const voice = drumVoices[laneId];
  if (voice) voice(ctx, dest, time, Math.max(0.05, Math.min(1, vel)));
}

// ============================================================
// SYNTH — 2-osc subtractive poly voice with filter + amp envelopes
// ============================================================

export const SYNTH_PRESETS = {
  subbass: {
    name: 'SUB BASS',
    osc1: { type: 'sine', oct: 0, detune: 0 },
    osc2: { type: 'square', oct: 0, detune: 4, level: 0.25 },
    filter: { cutoff: 420, q: 6, env: 900, decay: 0.18 },
    amp: { a: 0.004, d: 0.2, s: 0.75, r: 0.08 },
    gain: 0.9,
  },
  acid: {
    name: 'ACID',
    osc1: { type: 'sawtooth', oct: 0, detune: 0 },
    osc2: { type: 'sawtooth', oct: 0, detune: 0, level: 0 },
    filter: { cutoff: 300, q: 14, env: 2600, decay: 0.16 },
    amp: { a: 0.002, d: 0.18, s: 0.4, r: 0.05 },
    gain: 0.55,
  },
  glasskeys: {
    name: 'GLASS KEYS',
    osc1: { type: 'triangle', oct: 0, detune: 0 },
    osc2: { type: 'sine', oct: 1, detune: 6, level: 0.5 },
    filter: { cutoff: 2400, q: 1, env: 1600, decay: 0.4 },
    amp: { a: 0.005, d: 0.5, s: 0.35, r: 0.35 },
    gain: 0.6,
  },
  lead: {
    name: 'NEON LEAD',
    osc1: { type: 'sawtooth', oct: 0, detune: -7 },
    osc2: { type: 'sawtooth', oct: 0, detune: 7, level: 0.9 },
    filter: { cutoff: 1400, q: 2.5, env: 3200, decay: 0.3 },
    amp: { a: 0.01, d: 0.25, s: 0.6, r: 0.18 },
    gain: 0.5,
  },
  pad: {
    name: 'FOG PAD',
    osc1: { type: 'sawtooth', oct: 0, detune: -9 },
    osc2: { type: 'sawtooth', oct: 0, detune: 9, level: 0.9 },
    filter: { cutoff: 900, q: 0.8, env: 700, decay: 1.4 },
    amp: { a: 0.4, d: 0.8, s: 0.7, r: 0.9 },
    gain: 0.45,
  },
  pluck: {
    name: 'WIRE PLUCK',
    osc1: { type: 'square', oct: 0, detune: 0 },
    osc2: { type: 'triangle', oct: 1, detune: 3, level: 0.6 },
    filter: { cutoff: 500, q: 4, env: 4200, decay: 0.09 },
    amp: { a: 0.002, d: 0.16, s: 0.12, r: 0.1 },
    gain: 0.6,
  },
  bell: {
    name: 'DUSK BELL',
    osc1: { type: 'sine', oct: 0, detune: 0 },
    osc2: { type: 'sine', oct: 2, detune: 14, level: 0.35 },
    filter: { cutoff: 5200, q: 0.7, env: 0, decay: 0.3 },
    amp: { a: 0.003, d: 0.9, s: 0.15, r: 0.6 },
    gain: 0.55,
  },
};

export const SYNTH_PRESET_IDS = Object.keys(SYNTH_PRESETS);

/**
 * Start a synth voice. Returns a handle:
 *   .release(when) — begin the amp release at audio time `when`
 * If `dur` is given the release is pre-scheduled (sequencer use);
 * otherwise call release() yourself (live pads).
 */
export function synthVoice(ctx, dest, presetId, midi, time, vel = 1, dur = null) {
  const p = SYNTH_PRESETS[presetId] || SYNTH_PRESETS.lead;
  const freq = midiToFreq(midi);

  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.Q.value = p.filter.q;

  const amp = ctx.createGain();
  amp.gain.value = 0;

  filter.connect(amp).connect(dest);

  const oscs = [];
  const addOsc = (cfg, level) => {
    if (level <= 0) return;
    const o = ctx.createOscillator();
    o.type = cfg.type;
    o.frequency.value = freq * Math.pow(2, cfg.oct || 0);
    o.detune.value = cfg.detune || 0;
    const og = ctx.createGain();
    og.gain.value = level;
    o.connect(og).connect(filter);
    o.start(time);
    oscs.push(o);
  };
  addOsc(p.osc1, 1);
  addOsc(p.osc2, p.osc2.level ?? 0);

  // filter envelope: cutoff + env·vel, decaying back to cutoff
  const f0 = Math.min(p.filter.cutoff, 18000);
  const fPeak = Math.min(f0 + p.filter.env * (0.4 + 0.6 * vel), 18000);
  filter.frequency.setValueAtTime(Math.max(fPeak, 30), time);
  filter.frequency.exponentialRampToValueAtTime(Math.max(f0, 30), time + p.filter.decay);

  // amp ADSR
  const peak = p.gain * (0.35 + 0.65 * vel);
  const sus = peak * p.amp.s;
  amp.gain.setValueAtTime(0, time);
  amp.gain.linearRampToValueAtTime(peak, time + p.amp.a);
  amp.gain.setTargetAtTime(sus, time + p.amp.a, Math.max(p.amp.d / 3, 0.01));

  let released = false;
  const release = (when = ctx.currentTime) => {
    if (released) return;
    released = true;
    const w = Math.max(when, time + p.amp.a);
    amp.gain.cancelScheduledValues(w);
    amp.gain.setTargetAtTime(0, w, Math.max(p.amp.r / 3, 0.01));
    const stopAt = w + p.amp.r + 0.25;
    for (const o of oscs) { try { o.stop(stopAt); } catch (e) { /* already stopped */ } }
  };

  if (dur != null) release(time + dur);
  return { release, midi };
}
