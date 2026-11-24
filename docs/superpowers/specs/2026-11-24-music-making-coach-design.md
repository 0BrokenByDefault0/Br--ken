# Music-Making Coach — Design

*Working title: Br--ken (the repo name). Personal iPhone app, sideloaded as an unsigned IPA.*
*Date: 2026-11-24 · Status: approved by owner*

---

## 1. Intent and why

The owner makes beats in **Koala Sampler** on iPhone. They know what a drum loop is made of,
how to build one, and what sounds good. They can find their way around most DAWs. On a piano
roll or instrument they can fumble around until they land on a loop that sounds good, but they
can't explain *why* it works and can't steer there on purpose. They also have no reliable path
from "a loop" to "a finished song."

They want a personal app that walks them through music-making **from the very beginning to a
complete song**, deeply and comprehensively, while staying intuitive and engaging. Questions the
app must answer, in their words:

- What's the first thing you do when you sit down to make your first song?
- What does it look like to create a melody?
- In what order are things typically added to make a song complete?
- How do you build from a loop, or from a single melody?
- How do you know which chords to use, based on the notes in your melody?
- How do you lay down a drum pattern over a melody, or a melody over drums?
- How do you practice composition?
- Style tricks for different subgenres.

**What keeps them hooked** (their words): *seeing immediate results in some form*, and *being able
to work out how to get from point A to point B and see the bigger picture clearly*.

**The goal:** become proficient at making every kind of hip hop instrumental, with an emphasis on
**trap, cloud rap, and underground ("UG")**, plus a general idea of how to make everything else.
The instrumentals are **built to carry vocals**: songs will have someone rapping or singing over them.

## 2. Goals, non-goals, anti-goals

### Goals
1. **Full depth on every element.** Drums, 808/bass, melody, chords/harmony, counter-melodies and
   layers, sound choice and texture, arrangement, and leaving room for vocals. Each one gets both
   *how to construct it* and *why it works*. The owner explicitly asked that this emphasis not be
   lost. The owner's existing drum skill changes where they *start*, not how deep drums go.
2. **Start to finish.** A clear path from a blank screen to a finished, arranged song. Every element
   is taught at the point where it naturally comes in.
3. **Hear it, play it.** The app makes its own sound. Concepts are demonstrated audibly, and the owner
   practices on playable in-app instruments (keyboard, drum grid, chord pads, 808).
4. **Immediate results.** Every lesson ends with something the owner made and can play back.
5. **The big picture is always visible.** A map shows the whole journey, where they are, and what
   each stage adds to the song.
6. **Genre depth.** Deep style guides for trap, cloud rap, and the underground styles. Working
   knowledge of the rest of hip hop.
7. **Bridge to Koala.** Anything built in the app can be exported as audio into Koala to sample.

### Non-goals
- **Not a DAW and not a Koala replacement.** Koala stays the studio. The app teaches, demonstrates,
  and gives a practice space, and its tools are scoped to what lessons need.
- **No vocal writing, recording, or vocal mixing.** Out of scope for now. Leave room to add it later
  as a separate module; don't design it out.
- **No mixing/mastering course.** Sound choice and basic balance only, where they serve composition
  (e.g. "the 808 and kick fight; here's why"). *(Builder's call how far to go; keep it shallow.)*
- **No importing your own audio** (from Koala, Files, etc.) for now. That would mean tempo/key
  detection, chopping, and time-stretching, which is a large audio job. Koala stays the place for
  real sampling. The owner may ask for it later, so don't design it out.
- No App Store release, accounts, backend, social features, or Android.

### Anti-goals (it fails even if it technically works when…)
- It turns into a **wall of reading** with nothing to hear or make.
- It is **shallow**: surface tips without the construction detail and "why."
- The owner **loses the thread**: they can't tell where they are or how a lesson leads to a finished song.
- Instruments **feel laggy or toy-like**, so playing them is a chore next to Koala.
- It teaches **generic music theory** detached from hip hop production. Every concept should be
  shown in a beat context.

## 3. Constraints

- **Platform:** iPhone only, native Swift/SwiftUI. *(Owner picked; see Approaches.)*
- **Distribution:** an **unsigned IPA**, sideloaded by the owner (AltStore, Sideloadly, or TrollStore).
  Sideloading tools re-sign the app with the owner's Apple ID. With a free Apple ID the app expires
  every 7 days unless refreshed (AltStore can auto-refresh). TrollStore avoids this but only works
  on some iOS versions.
  - Consequence: avoid entitlements that need a paid developer account (App Groups, iCloud, push,
    etc.). Sharing to Koala must go through the standard share sheet / Files, which needs no entitlement.
- **No Mac assumed.** Development happens in a Linux environment that can't compile iOS code.
  **Builds run on a GitHub Actions macOS runner**, which produces the unsigned IPA as a downloadable
  artifact. The build is unsigned (`CODE_SIGNING_ALLOWED=NO`); the IPA is the `.app` zipped into `Payload/`.
  - Consequence: slow feedback (each test is a CI build plus a sideload). Mitigations: put the music
    theory/logic in a pure-Swift package with unit tests that run on CI (ideally also on Linux), and
    prototype lesson interactions as web previews for the owner to react to before building them natively.
- **Fully offline.** All content and sounds are bundled. No network needed.
- **Minimum iOS:** iOS 18.0 (owner runs the latest iOS).
- **Sound licensing:** every bundled sample must be royalty-free / CC0 or generated by us. This is
  a personal app, but keep it clean anyway.
- **Content accuracy:** the lesson content will be written with AI help. Music theory statements must
  be correct, and genre characteristics must match how those genres are actually made.

## 4. Approaches considered

| | Approach | Trade-off |
|---|---|---|
| **A** ✅ | **Native Swift/SwiftUI with its own audio engine (AVAudioEngine + sampler)** | Instant, tight touch-to-sound response; proper sampled instruments; reliable audio export/share to Koala; offline. Cost: no iOS builds in the dev environment, so every test is a ~10–15 minute cloud build plus sideload. |
| B | Web app (e.g. React + Tone.js) wrapped as an iPhone app | Very fast iteration (preview in mobile Safari within seconds). But iOS web audio adds tap latency, can be muted by the silent switch, and glitches on app switches. That hurts exactly the "tap and hear it" moments the app depends on, and it feels less like Koala. |
| C | Cross-platform (Flutter / React Native) | Android support the owner doesn't need; weaker audio tooling than A or B. Dropped. |

**Picked: A.** Hearing it is the core teaching tool, so instruments must feel immediate. The slow
build loop is offset by web-preview mockups of lesson interactions and by unit-tested core logic.

## 5. The experience (decided)

### 5.1 Home: the Journey Map
The home screen is a map of the full song-making journey, top to bottom, with the owner's current
position marked. Each stage shows a one-line "what this adds to your song." Above the map,
**Your Track** plays everything the owner has built so far.

```
 YOUR TRACK ▶ [ ▮▮▮▮▯▯▯▯ ]  play what you've built so far

 ● 1 First sounds    — tempo, key, picking a vibe        ✓
 ● 2 The idea        — melody or loop as your seed       ✓
 ◐ 3 Harmony         — chords that fit your melody   ← you're here
 ○ 4 Drums & groove  — patterns that lock with it
 ○ 5 808 & bass      — following the chords, sliding
 ○ 6 Layers          — counter-melodies, texture
 ○ 7 Arrangement     — loop → intro/verse/hook/bridge
 ○ 8 Leave room for vocals
 ─────────────────────────────
 Style guides: Trap · Cloud · Plugg · Rage · Boom bap…
```

The exact stages and their order are a placeholder, finalized during content work (see 5.6).
The owner can **jump to any stage or style guide at any time**. The map guides; it never locks content.

### 5.2 Starting routes
Real producers start in different places, and the owner explicitly asked about "building from a
loop or a single melody" and "drums over melody or vice versa." So the journey has one main
path plus **alternate starting routes**, each converging on the same later stages:

- **Melody first:** a melody, then chords under it, then drums, then 808, and so on.
- **Chords/loop first:** a chord loop or melodic loop as the seed.
- **Drums first:** a groove, then a melody that sits in it. (Closest to how the owner works today.)
- **Sample first:** start from a sample or loop and build around it, mirroring Koala workflows.
  Uses **loops bundled with the app** (see Non-goals: no audio import).

The route changes the order of the early stages and the framing of their lessons, not the depth.
*(How routes are presented, e.g. a fork on the map vs. a choice at the start of a new track, is
the builder's call; prototype it.)*

### 5.3 Lesson anatomy
Every lesson follows the same rhythm so it never becomes a wall of text:

1. **The idea**: a short, visual explanation of the concept and *why* it works, in a beat context.
2. **Hear it**: playable examples, including A/B comparisons (e.g. "this chord fits your melody,
   this one clashes; tap both").
3. **Do it**: an interactive task on an in-app instrument (build the pattern, pick the chords,
   write the melody), with feedback.
4. **Keep it**: the result is saved to *Your Track* (or to a scratch project) and can be exported.
5. **Take it to Koala** *(optional)*: a short mission to recreate or extend it in Koala.

Theory depth is layered: each lesson gives the practical rule first, with an optional
**"go deeper"** expansion for the full explanation. Depth is always available, never forced.

### 5.4 Interactive tools
Scoped to what lessons need. Not a full DAW.

- **Keyboard** with key/scale highlighting and an optional "scale lock" so wrong notes are
  impossible while learning. Shows note names and scale degrees.
- **Drum grid** (step sequencer): velocity, swing, and the trap-specific moves it must handle:
  hi-hat rolls/ratchets (1/16, 1/32, triplet subdivisions), pitched hats, open/closed hats,
  ghost notes, half-time feel.
- **808 / bass** with pitch, glide/slide between notes, and sustain length. It shows how the 808
  follows the chord roots and locks with the kick.
- **Chord pads**: diatonic chords for the current key, labeled (name + Roman numeral), with
  common hip hop extensions (7ths, 9ths, sus) available.
- **Chord Finder**: given a melody (the owner's or an example), shows which chords contain or
  support its notes, ranks good fits, and lets the owner audition each under the melody. This
  directly answers "how do I know what chords to use based on the notes in my melody."
- **Mini piano roll** for viewing and editing melodies and chords.
- **Arrangement timeline**: sections (intro, verse, hook, bridge, outro) built from the owner's
  parts, with element mute/unmute per section to teach drops, switch-ups, and building energy.
- **Transport**: tempo, loop, metronome, count-in.

### 5.5 Your Track and export
- *Your Track* is one song in progress that accumulates parts as the owner moves through the
  journey. The owner can start a new track at any time and keep several.
- **Export**: render any part, section, or the full arrangement to an audio file (WAV, tempo-locked,
  loop-length exact), then share it via the iOS share sheet / Files so it can go into Koala.
  Stems (per-element exports) are wanted so the owner can sample individual parts.
  *(MIDI export is a nice-to-have; Koala is sample-based, so audio is the priority.)*

### 5.6 Content scope

**Core journey.** Each stage covers construction plus "why," with hip hop examples throughout:

- **Getting started:** what to do first when you sit down; picking tempo, key, and a vibe or
  reference; how producers actually begin.
- **Rhythm and drums:** kick/snare/hat roles, groove, swing, pocket, half-time, hat rolls,
  percussion, variation and fills, and why patterns feel the way they do. Drums over a melody and
  a melody over drums.
- **Melody:** what makes a melody catchy, scales and keys, motifs, repetition and variation,
  call and response, rhythm of melody, writing over a loop, and turning a fumbled loop into an
  intentional one.
- **Harmony:** chords from notes, diatonic chords, finding chords from a melody, common hip hop
  progressions and moods (dark, sad, dreamy, triumphant), minor-key emphasis, extensions, voicing.
- **808 and bass:** following roots, glides, rhythm against the kick, tuning the 808 to the key,
  distortion/saturation as a style choice.
- **Layers and texture:** counter-melodies, pads, atmosphere, ear candy, sound selection and
  frequency space (just enough mixing awareness to keep parts from fighting).
- **Arrangement:** the typical order elements get added; loop to song; song structures (intro,
  verse, hook, bridge, outro, bar counts); energy curves; drops and switch-ups; transitions.
- **Building for vocals:** leaving space in the frequency range and the arrangement, pockets and
  gaps, hook vs. verse density, beat switches, what rappers and singers need from a beat.
- **Practicing composition:** a dedicated practice area. Timed drills (e.g. "four melodies in
  A minor in 10 minutes"), ear training (identify chord quality, hear the scale degree), flipping
  a given loop, recreating a style from its guide, and daily or short "reps."

**Style guides.** Each guide covers tempo range, drum patterns, 808 behavior, chord/mood
palette, melody habits, signature sounds, arrangement habits, signature tricks, and playable,
deconstructable example beats (mute/solo each element to hear what it contributes).

- **Deep:** trap (and its sub-flavors), cloud rap, and underground styles: plugg, pluggnb, rage,
  jerk, and nearby dark/distorted SoundCloud styles.
- **Working knowledge:** boom bap, lo-fi, drill (UK/NY/Chicago), West Coast/G-funk, Memphis/phonk,
  Jersey club, and others as relevant.

*("UG" confirmed by owner: underground SoundCloud-style subgenres.)*

### 5.7 Learn mode and Build mode *(decided by owner)*
The journey is a **course you go through once** (Learn mode). After that, the same map stages
become a **guided Build mode** for every new song: start a new track and the stages walk you through
it in order, without the lessons. Each step gives quick reminders, the right tool, and a
"go deeper" link back to the full lesson. Stages finished in Learn mode unlock their Build-mode
version, but nothing is locked: the owner can use Build mode at any time.

Consequences for the data model: **lesson progress belongs to the user**, while **each track has its
own build progress** (which stages it has gone through). The first track the owner builds in Learn
mode is just a track like any other.

### 5.8 Progress
Stored locally on the device: lessons completed, current map position, saved tracks with their
per-track stage progress, and drill history. No account, no sync. Progress shows as position on the map and a playable track, not
as points or badges. *(Light streaks for practice drills are the builder's call; never let
gamification replace actual results.)*

## 6. Proposed phasing

The owner should get a usable app early. Each phase ends with an IPA they can sideload.

1. **Foundation + first playable path.** CI build to unsigned IPA; audio engine and core instruments
   (keyboard, drum grid, chord pads, 808); theory core (keys, scales, chords, Chord Finder);
   Journey Map shell; *Your Track*; audio export to Koala; and the first stages of content end to end
   (getting started → melody → harmony → drums) on the main route.
2. **Complete journey.** Remaining stages (808, layers, arrangement timeline, building for vocals);
   alternate starting routes; Build mode; the practice area.
3. **Style guides.** Trap, cloud rap, and underground in depth with example beats; then the
   working-knowledge guides.

Each phase gets its own implementation plan.

## 7. Calls made after design review *(builder/assistant calls; owner to check)*

- **Sound shaping:** preset sounds plus a small set of genre-critical controls built into the
  engine: 808 distortion/saturation, filter cutoff, reverb, delay, and pitch/glide. No synth
  programming. This is enough to teach cloud rap washes, rage distortion, and dark 808s without
  turning into a sound-design course.
- **Task feedback is rule-based and offline:** in key, chord contains or supports the melody
  note, 808 follows the root, kick and 808 alignment, density checks for vocal space, etc. Where
  quality is subjective, the app uses *compare-to-reference* (A/B your result against an example)
  instead of pretending to judge taste.
- **Content accuracy is owned by the builder:** every theory claim and genre characteristic is
  cross-checked against references and real tracks. The owner flags anything that "doesn't sound
  right" in use.

### Settled with owner after review
1. Later songs are made in the guided Build mode (5.7).
2. No audio import initially; bundled loops only (Non-goals).
3. "UG" = underground SoundCloud styles (plugg, pluggnb, rage, jerk, etc.).

## 8. Left to the builder

- App architecture, data model, and how lesson content is authored and stored (a structured,
  data-driven format is strongly preferred so content can grow without code changes).
- Audio engine internals (sampler setup, sequencing clock, offline rendering for export).
- Sourcing or generating the sound library within the licensing constraint.
- Visual design and UI details, within the intent: intuitive, engaging, results-first, big
  picture always visible. Prototype key screens as web previews for the owner to react to.
- Exact stage list, order, and lesson breakdown, drafted from 5.6 and reviewed with the owner.
- Testing approach, given that iOS builds only run on CI.
