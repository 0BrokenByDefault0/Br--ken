# BR--KEN

**A pocket studio.** BR--KEN is a mobile-first groovebox / DAW that runs entirely in the
browser — no build step, no dependencies, no server. It borrows its workflow from
Ableton Live's session view and its immediacy from hardware grooveboxes, and it fits
in one thumb's reach.

Open it, tap a scene, and a track is already playing.

## Run it

Any static file server works:

```sh
python3 -m http.server 8000
# → http://localhost:8000
```

Or enable GitHub Pages on this repo and open it on your phone. Audio starts after the
first tap (browser autoplay policy). Add it to your home screen for the full-screen
app experience.

## What it does

- **SESSION** — an Ableton-style clip-launch grid: tracks × 6 scenes.
  Tap a clip to launch it (quantized to the next bar), tap a scene number to fire a
  whole row, long-press any slot to create or edit a clip. The scene column stays
  pinned while tracks scroll.
- **EDIT** — drum tracks get a step sequencer (tap = hit, tap again = ghost note,
  again = off); synth tracks get a full piano roll (tap to draw, tap a note to select,
  toolbar to nudge/transpose/stretch, tap again to delete). 1–8 bar clips, `×2`
  duplication, live playhead.
- **PLAY** — multi-touch performance pads. Synth tracks are scale-locked (minor,
  major, dorian, pentatonics, chromatic — any root), drum tracks get MPC-style pads.
  Arm **●** while a clip plays and everything you play is quantized into the clip live.
- **MIX** — faders with real-time meters, pan, mute/solo, and per-track sends into
  the ping-pong delay and plate reverb buses.
- **FX** — a momentary XY performance pad (master filter sweep × delay feedback — it
  springs back when you let go), master drive, send-return levels, and a live
  oscilloscope of the output bus.
- **Transport** — drag the BPM number, swing control, metronome, undo/redo everywhere.
- **Export** — renders the selected scene *offline* through the exact same DSP graph
  and downloads a 16-bit WAV.
- **Autosave** — the project persists to `localStorage` on every change.

## Sound engine

Everything is synthesized live with the Web Audio API — there is not a single sample
file in this repo:

- 8 analog-style drum voices (pitch-dropped sine kick, noise-burst clap, six-oscillator
  metallic hats, 808 cowbell…)
- a 2-oscillator subtractive polysynth with filter + amp envelopes and 7 presets
  (sub bass, acid, glass keys, neon lead, fog pad, wire pluck, dusk bell)
- per-track channel strips → ping-pong delay + generated-IR plate reverb sends →
  master chain (XY filter → drive waveshaper → bus compressor → limiter)
- a lookahead scheduler (25 ms tick, 120 ms horizon) keeps timing sample-accurate
  while the UI thread does UI things; swing shifts every off-16th

Because every instrument takes its `AudioContext` as a parameter, the identical code
renders the WAV export in an `OfflineAudioContext`.

## Architecture

```
index.html            app shell
css/app.css           design system (dark / brutalist / acid)
js/state.js           store: project model, pub/sub, undo/redo, autosave, demo song
js/audio/
  instruments.js      drum voices + polysynth presets (context-agnostic)
  graph.js            mixing topology: channels, sends, delay/reverb/master buses
  engine.js           transport, lookahead scheduler, clip launcher, live input & rec
  export.js           offline scene render + WAV encoder
js/ui/
  components.js       DOM builder, knobs, faders, long-press, toast
  session.js          clip grid
  editor.js           step sequencer + piano roll
  keys.js             performance pads
  mixer.js            channel strips
  fx.js               XY pad, master bus, scope
js/main.js            boot, routing, transport bar, menu, rAF loop
```

Vanilla ES modules. No framework, no bundler, no dependencies.
