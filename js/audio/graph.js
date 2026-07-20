// ============================================================
// BR--KEN · audio graph
// Builds the full mixing topology in ANY BaseAudioContext:
//
//  track voice ─▶ channel.input ─▶ gain ─▶ pan ─┬─▶ master.input
//                                               ├─▶ sendA ─▶ delay bus
//                                               └─▶ sendB ─▶ reverb bus
//  delay/reverb buses ─▶ master.input
//  master.input ─▶ xy lowpass ─▶ drive ─▶ compressor ─▶ limiter ─▶ out
// ============================================================

// generated stereo impulse response — dark exponential-decay plate
function makeReverbIR(ctx, seconds = 2.4, decay = 3.2) {
  const rate = ctx.sampleRate;
  const len = Math.floor(rate * seconds);
  const buf = ctx.createBuffer(2, len, rate);
  for (let ch = 0; ch < 2; ch++) {
    const d = buf.getChannelData(ch);
    for (let i = 0; i < len; i++) {
      const t = i / len;
      // noise, exp decay, slightly lowpassed by averaging
      d[i] = (Math.random() * 2 - 1) * Math.pow(1 - t, decay);
    }
    // cheap one-pole smoothing to darken the tail
    for (let i = 1; i < len; i++) d[i] = d[i - 1] * 0.35 + d[i] * 0.65;
  }
  return buf;
}

export function buildGraph(ctx) {
  // ---- master chain ----
  const masterIn = ctx.createGain();

  const xyFilter = ctx.createBiquadFilter();
  xyFilter.type = 'lowpass';
  xyFilter.frequency.value = 18000;
  xyFilter.Q.value = 1;

  const drive = ctx.createWaveShaper();
  setDrive(drive, 0); // transparent by default
  drive.oversample = '2x';

  const comp = ctx.createDynamicsCompressor();
  comp.threshold.value = -14;
  comp.knee.value = 8;
  comp.ratio.value = 3.5;
  comp.attack.value = 0.004;
  comp.release.value = 0.18;

  const limiter = ctx.createDynamicsCompressor();
  limiter.threshold.value = -2;
  limiter.knee.value = 0;
  limiter.ratio.value = 20;
  limiter.attack.value = 0.001;
  limiter.release.value = 0.08;

  const masterGain = ctx.createGain();
  masterGain.gain.value = 0.9;

  masterIn.connect(xyFilter).connect(drive).connect(comp).connect(limiter).connect(masterGain);
  masterGain.connect(ctx.destination);

  // ---- delay bus (ping-pong) ----
  const delayIn = ctx.createGain();
  const dL = ctx.createDelay(2);
  const dR = ctx.createDelay(2);
  dL.delayTime.value = 0.375; // dotted 8th at 120 — retuned by engine per BPM
  dR.delayTime.value = 0.5;
  const fbL = ctx.createGain();
  const fbR = ctx.createGain();
  fbL.gain.value = 0.35;
  fbR.gain.value = 0.35;
  const dFilter = ctx.createBiquadFilter();
  dFilter.type = 'lowpass';
  dFilter.frequency.value = 3200;
  const dMerge = ctx.createChannelMerger(2);
  const delayOut = ctx.createGain();
  delayOut.gain.value = 0.9;

  delayIn.connect(dFilter);
  dFilter.connect(dL);
  dL.connect(fbL).connect(dR);   // ping →
  dR.connect(fbR).connect(dL);   // ← pong
  dL.connect(dMerge, 0, 0);
  dR.connect(dMerge, 0, 1);
  dMerge.connect(delayOut).connect(masterIn);

  // ---- reverb bus ----
  const verbIn = ctx.createGain();
  const conv = ctx.createConvolver();
  conv.buffer = makeReverbIR(ctx);
  const verbOut = ctx.createGain();
  verbOut.gain.value = 1;
  verbIn.connect(conv).connect(verbOut).connect(masterIn);

  // ---- per-track channel strip factory ----
  function makeChannel() {
    const input = ctx.createGain();
    const gain = ctx.createGain();
    const pan = ctx.createStereoPanner ? ctx.createStereoPanner() : ctx.createGain();
    const sendA = ctx.createGain();
    const sendB = ctx.createGain();
    sendA.gain.value = 0;
    sendB.gain.value = 0;
    input.connect(gain).connect(pan);
    pan.connect(masterIn);
    pan.connect(sendA).connect(delayIn);
    pan.connect(sendB).connect(verbIn);
    return { input, gain, pan, sendA, sendB };
  }

  return {
    ctx,
    masterIn, xyFilter, drive, comp, limiter, masterGain,
    delay: { input: delayIn, dL, dR, fbL, fbR, filter: dFilter, out: delayOut },
    reverb: { input: verbIn, out: verbOut },
    makeChannel,
    setDelayTimes(bpm) {
      const beat = 60 / bpm;
      dL.delayTime.value = beat * 0.75;  // dotted 8th
      dR.delayTime.value = beat;         // quarter
    },
  };
}

// waveshaper curve: 0 = identity, 1 = heavy tanh saturation
export function setDrive(shaper, amount) {
  const n = 1024;
  const curve = new Float32Array(n);
  const k = amount * 24;
  for (let i = 0; i < n; i++) {
    const x = (i / (n - 1)) * 2 - 1;
    curve[i] = k > 0 ? Math.tanh(x * (1 + k)) / Math.tanh(1 + k) : x;
  }
  shaper.curve = curve;
}
