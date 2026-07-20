// ============================================================
// BR--KEN · export
// Renders a scene offline through the exact same graph +
// instrument code as live playback, then encodes 16-bit WAV.
// ============================================================

import { STEPS_PER_BAR, DRUM_LANES } from '../state.js';
import { buildGraph } from './graph.js';
import { triggerDrum, synthVoice } from './instruments.js';

const gcd = (a, b) => (b ? gcd(b, a % b) : a);
const lcm = (a, b) => a / gcd(a, b) * b;

/**
 * Render `sceneIdx` of `project` to an AudioBuffer.
 * Loop length = LCM of the scene's clip lengths (capped), played twice.
 */
export async function renderScene(project, sceneIdx) {
  const clips = project.tracks
    .map(t => ({ track: t, clip: t.clips[sceneIdx] }))
    .filter(x => x.clip && x.clip.notes.length);

  if (!clips.length) throw new Error('scene is empty');

  let loopBars = clips.reduce((acc, { clip }) => lcm(acc, clip.bars), 1);
  loopBars = Math.min(loopBars, 8);
  const passBars = Math.min(loopBars * 2, 16);

  const bpm = project.bpm;
  const stepDur = 60 / bpm / 4;
  const totalSteps = passBars * STEPS_PER_BAR;
  const tail = 2.0;
  const sampleRate = 44100;
  const length = Math.ceil((totalSteps * stepDur + tail) * sampleRate);

  const ctx = new OfflineAudioContext(2, length, sampleRate);
  const graph = buildGraph(ctx);
  graph.setDelayTimes(bpm);

  const anySolo = project.tracks.some(t => t.mixer.solo);
  const swung = (s) => (s % 2 === 1 ? (project.swing / 100) * stepDur * 0.55 : 0);
  const t0 = 0.05;

  for (const { track, clip } of clips) {
    const m = track.mixer;
    const audible = !m.mute && (!anySolo || m.solo);
    if (!audible) continue;
    const ch = graph.makeChannel();
    ch.gain.gain.value = m.vol * m.vol;
    if (ch.pan.pan) ch.pan.pan.value = m.pan;
    ch.sendA.gain.value = m.sendA;
    ch.sendB.gain.value = m.sendB;

    const clipSteps = clip.bars * STEPS_PER_BAR;
    for (let s = 0; s < totalSteps; s++) {
      const local = s % clipSteps;
      const time = t0 + s * stepDur + swung(s);
      for (const n of clip.notes) {
        if (n.step !== local) continue;
        if (track.type === 'drum') {
          const lane = DRUM_LANES[n.pitch];
          if (lane) triggerDrum(ctx, ch.input, lane.id, time, n.vel);
        } else {
          synthVoice(ctx, ch.input, track.presetId, n.pitch, time, n.vel,
            Math.max(n.len, 0.5) * stepDur * 0.98);
        }
      }
    }
  }

  return ctx.startRendering();
}

// ---------------- WAV encoding (16-bit PCM, interleaved) ----------------

export function audioBufferToWav(buffer) {
  const numCh = Math.min(buffer.numberOfChannels, 2);
  const rate = buffer.sampleRate;
  const frames = buffer.length;
  const bytesPerSample = 2;
  const dataSize = frames * numCh * bytesPerSample;
  const out = new ArrayBuffer(44 + dataSize);
  const dv = new DataView(out);

  const wstr = (off, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(off + i, s.charCodeAt(i)); };
  wstr(0, 'RIFF');
  dv.setUint32(4, 36 + dataSize, true);
  wstr(8, 'WAVE');
  wstr(12, 'fmt ');
  dv.setUint32(16, 16, true);
  dv.setUint16(20, 1, true);                    // PCM
  dv.setUint16(22, numCh, true);
  dv.setUint32(24, rate, true);
  dv.setUint32(28, rate * numCh * bytesPerSample, true);
  dv.setUint16(32, numCh * bytesPerSample, true);
  dv.setUint16(34, 16, true);
  wstr(36, 'data');
  dv.setUint32(40, dataSize, true);

  const chans = [];
  for (let c = 0; c < numCh; c++) chans.push(buffer.getChannelData(c));
  let off = 44;
  for (let i = 0; i < frames; i++) {
    for (let c = 0; c < numCh; c++) {
      const x = Math.max(-1, Math.min(1, chans[c][i]));
      dv.setInt16(off, x < 0 ? x * 0x8000 : x * 0x7fff, true);
      off += 2;
    }
  }
  return new Blob([out], { type: 'audio/wav' });
}

export async function exportSceneToWav(project, sceneIdx) {
  const buffer = await renderScene(project, sceneIdx);
  const blob = audioBufferToWav(buffer);
  const name = `${(project.name || 'brkn').replace(/[^\w-]+/g, '_')}_scene${sceneIdx + 1}.wav`;
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
  return name;
}
