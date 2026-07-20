// ============================================================
// BR--KEN · mixer view
// One strip per track: fader + live meter, pan, delay/verb
// sends, mute/solo. Plus a master strip.
// ============================================================

import { store } from '../state.js';
import { engine } from '../audio/engine.js';
import { h, makeFader, makeKnob } from './components.js';

let faders = new Map();   // trackId -> fader handle
let masterFader = null;

export function render(container) {
  faders = new Map();
  const strips = h('div', { class: 'mixer-strips' });

  for (const t of store.project.tracks) {
    strips.append(strip(t));
  }
  strips.append(masterStrip());

  container.replaceChildren(h('div', { class: 'mixer' }, strips));
}

function strip(t) {
  const m = t.mixer;

  const fader = makeFader({
    value: m.vol,
    color: t.color,
    onStart: () => store.checkpoint(),
    onInput: (v) => store.tweak(() => { m.vol = v; }, 'mixer'),
  });
  faders.set(t.id, fader);

  const mute = h('button', { class: `strip-btn mute${m.mute ? ' on' : ''}` }, 'M');
  mute.addEventListener('click', () => {
    store.mutate(() => { m.mute = !m.mute; }, 'mixer');
    mute.classList.toggle('on', m.mute);
  });
  const solo = h('button', { class: `strip-btn solo${m.solo ? ' on' : ''}` }, 'S');
  solo.addEventListener('click', () => {
    store.mutate(() => { m.solo = !m.solo; }, 'mixer');
    solo.classList.toggle('on', m.solo);
  });

  const pan = makeKnob({
    label: 'PAN', value: (m.pan + 1) / 2, color: t.color, defaultValue: 0.5,
    format: (v) => { const p = Math.round((v * 2 - 1) * 100); return p === 0 ? 'C' : p < 0 ? `L${-p}` : `R${p}`; },
    onStart: () => store.checkpoint(),
    onInput: (v) => store.tweak(() => { m.pan = v * 2 - 1; }, 'mixer'),
  });
  const sendA = makeKnob({
    label: 'DLY', value: m.sendA, color: '#43e8d8', defaultValue: 0,
    onStart: () => store.checkpoint(),
    onInput: (v) => store.tweak(() => { m.sendA = v; }, 'mixer'),
  });
  const sendB = makeKnob({
    label: 'VRB', value: m.sendB, color: '#b18cff', defaultValue: 0,
    onStart: () => store.checkpoint(),
    onInput: (v) => store.tweak(() => { m.sendB = v; }, 'mixer'),
  });

  return h('div', { class: 'strip', style: `--strip-c: ${t.color};` },
    h('div', { class: 'strip-name' }, t.name),
    fader.el,
    h('div', { class: 'strip-btns' }, mute, solo),
    h('div', { class: 'knob-row' }, pan.el),
    h('div', { class: 'knob-row' }, sendA.el, sendB.el),
  );
}

function masterStrip() {
  masterFader = makeFader({
    value: 0.9,
    color: '#ececf1',
    onInput: (v) => engine.setMasterVolume(v),
  });
  return h('div', { class: 'strip master', style: '--strip-c: #ececf1;' },
    h('div', { class: 'strip-name' }, 'MASTER'),
    masterFader.el,
    h('div', { class: 'strip-db' }, 'MAIN OUT'),
  );
}

export function tick() {
  for (const [id, fader] of faders) {
    fader.setMeter(engine.channelLevel(id));
  }
}
