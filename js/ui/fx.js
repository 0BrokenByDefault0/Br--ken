// ============================================================
// BR--KEN · fx view
// Master-bus performance page: XY filter/feedback pad (momentary,
// springs back on release), drive + send-return levels, scope.
// ============================================================

import { engine } from '../audio/engine.js';
import { h, makeKnob } from './components.js';

let scopeCanvas = null;
let scopeCtx = null;
let scopeData = null;

export function render(container) {
  // ---- XY pad ----
  const dot = h('div', { class: 'xy-dot idle', style: 'left:100%; top:50%;' });
  const pad = h('div', { class: 'xy-pad' },
    dot,
    h('div', { class: 'xy-labels' },
      h('span', { class: 'y-lab' }, 'FEEDBACK ▲'),
      h('span', { class: 'x-lab' }, 'FILTER ▶'),
    ),
  );

  let active = false;
  const apply = (e) => {
    const r = pad.getBoundingClientRect();
    const x = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
    const y = Math.max(0, Math.min(1, 1 - (e.clientY - r.top) / r.height));
    dot.style.left = `${x * 100}%`;
    dot.style.top = `${(1 - y) * 100}%`;
    engine.setXY(x, y);
  };
  pad.addEventListener('pointerdown', (e) => {
    active = true;
    pad.setPointerCapture(e.pointerId);
    dot.classList.remove('idle');
    apply(e);
    e.preventDefault();
  });
  pad.addEventListener('pointermove', (e) => { if (active) apply(e); });
  const end = () => {
    if (!active) return;
    active = false;
    dot.classList.add('idle');
    dot.style.left = '100%';
    dot.style.top = '50%';
    engine.resetXY();
  };
  pad.addEventListener('pointerup', end);
  pad.addEventListener('pointercancel', end);

  // ---- master knobs ----
  const drive = makeKnob({
    label: 'DRIVE', value: 0, defaultValue: 0, color: '#ff5c7a',
    onInput: (v) => engine.setDriveAmount(v),
  });
  const dly = makeKnob({
    label: 'DELAY RET', value: 0.64, defaultValue: 0.64, color: '#43e8d8',
    onInput: (v) => engine.setDelayLevel(v),
  });
  const vrb = makeKnob({
    label: 'VERB RET', value: 0.62, defaultValue: 0.62, color: '#b18cff',
    onInput: (v) => engine.setReverbLevel(v),
  });

  // ---- scope ----
  scopeCanvas = h('canvas', { class: 'scope', width: 600, height: 140 });
  scopeCtx = scopeCanvas.getContext('2d');

  container.replaceChildren(
    h('div', { class: 'fx' },
      h('div', { class: 'fx-section' },
        h('div', { class: 'fx-title' }, 'PERFORM — HOLD & SWEEP'),
        pad,
      ),
      h('div', { class: 'fx-section' },
        h('div', { class: 'fx-title' }, 'MASTER BUS'),
        h('div', { class: 'fx-knobs' }, drive.el, dly.el, vrb.el),
      ),
      h('div', { class: 'fx-section' },
        h('div', { class: 'fx-title' }, 'OUTPUT'),
        scopeCanvas,
      ),
    ),
  );
}

export function tick() {
  if (!scopeCtx || !engine.masterAnalyser) return;
  const an = engine.masterAnalyser;
  if (!scopeData || scopeData.length !== an.fftSize) {
    scopeData = new Float32Array(an.fftSize);
  }
  an.getFloatTimeDomainData(scopeData);

  const { width: w, height: hgt } = scopeCanvas;
  scopeCtx.clearRect(0, 0, w, hgt);
  scopeCtx.strokeStyle = '#c8ff2e';
  scopeCtx.lineWidth = 1.6;
  scopeCtx.beginPath();
  for (let i = 0; i < scopeData.length; i++) {
    const x = (i / scopeData.length) * w;
    const y = hgt / 2 - scopeData[i] * hgt * 0.46;
    i ? scopeCtx.lineTo(x, y) : scopeCtx.moveTo(x, y);
  }
  scopeCtx.stroke();
}
