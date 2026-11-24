# Phase 1 — Foundation + First Playable Path · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sideloadable iPhone app in which the owner can follow the first four journey stages (First sounds → The idea → Harmony → Drums & groove). The owner hears and plays everything on in-app instruments, builds *Your Track* as they go, and exports audio to Koala.

**Architecture:** One local Swift package, `BrokenKit`, holds all logic, split into two library targets:
- `MusicCore`: theory, timeline models, tracks, persistence, content, Chord Finder, task checks.
- `SoundEngine`: a pure-Swift synth, sampler, and sequencer that renders into float buffers, plus WAV export.

Both use only Foundation and Synchronization, so their tests run on Linux in CI. A thin SwiftUI app target hosts the renderer inside `AVAudioEngine` through an `AVAudioSourceNode` and owns all UI. Lesson content is bundled JSON using a compact music notation. All sounds are synthesized in code, so there are no sample files and no licensing questions.

**Tech Stack:** Swift 6 (tools 6.0), SwiftUI, Observation, Swift Testing, AVFoundation (app target only), XcodeGen, GitHub Actions (Linux `swift:6.1` container plus a macOS runner).

**Spec:** `docs/superpowers/specs/2026-11-24-music-making-coach-design.md`. Read it before starting any task.

## Global Constraints

- iPhone only. **Deployment target iOS 18.0.** The owner runs the latest iOS.
- Unsigned IPA. **No entitlements that need a paid developer account** (no App Groups, iCloud, push). Sharing goes through the share sheet / Files only.
- Fully offline: no networking code anywhere.
- `MusicCore` and `SoundEngine` import only `Foundation` and `Synchronization`. No `AVFoundation`, `UIKit`, or `SwiftUI`. They must build and test on Linux.
- Swift language mode 6 for `BrokenKit`. App target uses `SWIFT_VERSION = 5.0` with `SWIFT_STRICT_CONCURRENCY = complete` (avoids AVFoundation sendability friction).
- Timing: 4/4 only. **PPQN 96** → 16th = 24 ticks, bar = 384 ticks.
- Engine sample rate = the hardware rate passed in at init. **Export: 48 000 Hz, 16-bit, stereo WAV.**
- **Max 32 simultaneous voices**, with voice stealing.
- Audio session: category `.playback`, options `[.mixWithOthers]` (plays with the silent switch on and alongside Koala), preferred IO buffer **0.005 s**.
- Real-time render path: no allocation, locks (only `withLockIfAvailable`), file I/O, or `print`.
- Bundle id `com.local.broken`, target/product `Broken`, display name `Br--ken`.
- No Swift toolchain exists in the dev container. **"Run tests" means push and read the CI job result** (GitHub MCP `actions_list` / `get_job_logs`). The Linux job runs on every push. The macOS job runs on `workflow_dispatch` or when the commit message contains `[ipa]`, to save macOS minutes.
- Commit messages end with the session's attribution lines (see the system reminder). No model names in repo files.

## Review Focus

1. **Jumping ahead with an empty track.** Nothing is locked. Opening a Harmony or Drums lesson with no track, or a track without a melody, must still work: the task uses the lesson's `starter` parts for missing roles. *(Task 13 test)*
2. **Switching to Koala or taking a call mid-playback.** When the owner returns, audio works without relaunching: interruption-ended and route-change restart the engine; media-services-reset rebuilds it. *(Task 13 test)*
3. **Silent switch on.** The app still makes sound (`.playback` category). *(Task 13 test)*
4. **No stuck notes.** Stopping, notes that cross the loop end, and swapping the pattern during playback never leave a note ringing. *(Task 11 tests)*
5. **Corrupt or newer-version save files.** The app opens. A corrupt track file is renamed `.corrupt` and skipped, a newer-version file is skipped and left untouched, other tracks load, and a corrupt progress file resets to empty. *(Task 5 tests)*

---

## File Structure

```
project.yml                         XcodeGen spec (app + test targets, Content as folder resource)
.github/workflows/ci.yml            linux core tests; macOS app tests + unsigned IPA (+ release on tag)
scripts/build-ipa.sh                xcodebuild unsigned → Payload/ → Broken.ipa
scripts/pick-simulator.sh           prints an available iPhone simulator UDID
docs/BUILD.md                       how to get the IPA and sideload it
Content/journey.json                8 stages (4 available in Phase 1)
Content/lessons/<lesson-id>.json    one file per lesson
Packages/BrokenKit/Package.swift
Packages/BrokenKit/Sources/MusicCore/
  Theory/      PitchClass.swift Key.swift Chord.swift Voicer.swift
  Timeline/    Ticks.swift NoteSequence.swift ChordProgression.swift DrumPattern.swift Notation.swift
  Track/       Track.swift TrackStore.swift Progress.swift
  Harmony/     ChordFinder.swift
  Checks/      TaskCheck.swift CheckRunner.swift
  Content/     ContentModel.swift ContentLibrary.swift ContentValidator.swift
Packages/BrokenKit/Sources/SoundEngine/
  DSP/         Envelope.swift Oscillators.swift Filter.swift Drive.swift Delay.swift Reverb.swift
  Instruments/ DrumSynth.swift InstrumentPreset.swift Voice.swift VoicePool.swift
  Render/      PlaybackSnapshot.swift CommandQueue.swift Renderer.swift
  Export/      OfflineRenderer.swift WAVWriter.swift ExportNaming.swift
Packages/BrokenKit/Tests/MusicCoreTests/ …   Packages/BrokenKit/Tests/SoundEngineTests/ …
App/Sources/
  BrokenApp.swift  AppModel.swift
  Audio/       AudioHost.swift AVAudioEngineController.swift AudioPlayer.swift
  Tools/       MelodyEditor/(KeyboardView PianoRollView PianoRollModel LiveRecorder)
               DrumGrid/(DrumGridView DrumGridModel)  Chords/(ChordPadsView ChordFinderView ChordFinderModel)
               TrackSetupView.swift TransportBar.swift SoundControlsView.swift
  Journey/     JourneyMapView.swift YourTrackBar.swift TrackListView.swift
  Lesson/      LessonPlayerView.swift StepViews.swift TaskStepModel.swift
  Export/      ExportSheet.swift ExportModel.swift
App/Tests/     AudioHostTests.swift AppModelTests.swift ToolModelTests.swift ExportModelTests.swift
```

---

### Task 1: Repo skeleton, CI, and a sideloadable "hello" IPA

De-risks the whole pipeline before any real code: the owner confirms an unsigned IPA from CI installs and launches.

**Files:**
- Create: `Packages/BrokenKit/Package.swift`, `Sources/MusicCore/MusicCore.swift`, `Sources/SoundEngine/SoundEngine.swift`, `Tests/MusicCoreTests/SmokeTests.swift`, `Tests/SoundEngineTests/SmokeTests.swift`
- Create: `project.yml`, `App/Sources/BrokenApp.swift`, `App/Tests/SmokeTests.swift`, `App/Resources/Assets.xcassets` (AppIcon placeholder, AccentColor)
- Create: `.github/workflows/ci.yml`, `scripts/build-ipa.sh`, `scripts/pick-simulator.sh`, `docs/BUILD.md`, `.gitignore` (`build/`, `*.xcodeproj`, `Payload/`, `*.ipa`, `.build/`, `DerivedData/`)

**Interfaces:**
- Produces: package products `MusicCore`, `SoundEngine` (platforms `.iOS(.v18)`, `.macOS(.v15)`); `SoundEngine` depends on `MusicCore`. The XcodeGen app target `Broken` depends on both via local package path `Packages/BrokenKit`; test target `BrokenTests`. `Content/` is added as a **folder reference** resource (bundle path `Content/`).

- [ ] **Step 1: Write smoke tests.** `MusicCoreTests`: `@Test func packageBuilds() { #expect(MusicCore.version == 1) }`. Same for `SoundEngine.version`. App: `@Test func appBundleHasContentFolder()` asserts `Bundle.main.url(forResource: "Content", withExtension: nil) != nil` (needs `Content/journey.json` placeholder `{"version":1,"stages":[]}`).
- [ ] **Step 2: Write `ci.yml`.**
  - Job `core-tests`: `ubuntu-latest`, `container: swift:6.1`, runs `swift test --package-path Packages/BrokenKit`. Runs on every push and PR.
  - Job `app`: `macos-15`, `maxim-lobanov/setup-xcode@v1` with `latest-stable`. Steps: `brew install xcodegen`, `xcodegen generate`, `xcodebuild test -project Broken.xcodeproj -scheme Broken -destination "id=$(scripts/pick-simulator.sh)"`, then `scripts/build-ipa.sh`, then `actions/upload-artifact` with `Broken.ipa`.
    - Condition: `github.event_name == 'workflow_dispatch' || contains(github.event.head_commit.message, '[ipa]') || startsWith(github.ref, 'refs/tags/v')`.
    - On a `v*` tag, attach the IPA to a GitHub Release (`softprops/action-gh-release@v2`) so the owner can download it on the phone.
- [ ] **Step 3: Write `build-ipa.sh`.** `xcodebuild -project Broken.xcodeproj -scheme Broken -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build`, then copy `build/Build/Products/Release-iphoneos/Broken.app` into `Payload/` and run `zip -qry Broken.ipa Payload`. Use `set -euo pipefail`. `pick-simulator.sh` reads `xcrun simctl list devices available -j` and prints the UDID of the first available `iPhone` device on the newest iOS runtime.
- [ ] **Step 4: Minimal app.** `BrokenApp` shows the text "Br--ken" centered. Set `project.yml`: deployment target 18.0, `PRODUCT_BUNDLE_IDENTIFIER com.local.broken`, `INFOPLIST_KEY_CFBundleDisplayName Br--ken`, `GENERATE_INFOPLIST_FILE YES`, `TARGETED_DEVICE_FAMILY 1`, `INFOPLIST_KEY_UIFileSharingEnabled YES`, `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace YES` (exports also visible in Files), and the Swift settings from Global Constraints.
- [ ] **Step 5: `docs/BUILD.md`.** Cover: how to trigger a build (Actions → CI → Run workflow) or download from Releases; installing with AltStore/SideStore or Sideloadly; the 7-day re-sign with a free Apple ID and AltStore/SideStore auto-refresh. Note that TrollStore does not support the latest iOS.
- [ ] **Step 6: Push and verify.** `core-tests` passes. Trigger `app` via `workflow_dispatch`: tests pass and the `Broken.ipa` artifact exists.
- [ ] **Step 7: Owner checkpoint.** Ask the owner to sideload the IPA and confirm it launches showing "Br--ken". **Do not start Task 9+ app-facing work until this is confirmed.** Tasks 2–8 may proceed meanwhile.
- [ ] **Step 8: Commit.** `chore: project skeleton, CI, unsigned IPA pipeline`

---

### Task 2: Clickable web mockups for owner reaction

The spec asks for key screens to be prototyped before they're built natively. This task is throwaway; only the decisions it records are kept.

**Files:**
- Create: `docs/superpowers/specs/2026-11-24-ui-notes.md` (owner feedback and the resulting UI decisions)

- [ ] **Step 1: Build one HTML artifact** (load the `artifact-design` skill first; publish with the Artifact tool). Make it tappable at phone width with four screens:
  - **Journey Map** with *Your Track* bar (spec §5.1 sketch)
  - **Lesson player** showing the idea → hear → do → keep steps
  - **Chord Finder**: a 2-bar melody, ranked chord fits per bar, tap to audition (use Web Audio; rough sound is fine)
  - **Drum grid** with a hi-hat roll tool
- [ ] **Step 2: Send the link to the owner** and ask what feels off, confusing, or missing.
- [ ] **Step 3: Record decisions** in `ui-notes.md`: layout, navigation, and anything the owner changed. Tasks 14–19 must follow it.
- [ ] **Step 4: Commit.** `docs: UI notes from mockup review`

---

### Task 3: Theory core

**Files:**
- Create: `Sources/MusicCore/Theory/{PitchClass,Key,Chord,Voicer}.swift`
- Test: `Tests/MusicCoreTests/TheoryTests.swift`

**Interfaces:**
- Produces:
  - `struct PitchClass: Hashable, Codable { let rawValue: Int /*0–11, C=0*/; init(_ v: Int) /*wraps mod 12*/ }`
  - `enum Mode: String, Codable { case major, minor }`
  - `struct Key: Hashable, Codable`:
    - `tonic: PitchClass`, `mode: Mode`
    - `init(parsing: String) throws` (`"A minor"`, `"Eb major"`, `"C# minor"`); `var name: String`
    - `var scalePitchClasses: [PitchClass]` (major / natural minor)
    - `func contains(_ pc: PitchClass) -> Bool`
    - `func degree(of pc: PitchClass) -> Int?` (1–7)
    - `func spell(_ pc: PitchClass) -> String`, `func spell(midi: Int) -> String` (e.g. `"A4"`)
    - `func diatonicTriads() -> [DiatonicChord]`, `func diatonicSevenths() -> [DiatonicChord]`
    - `func borrowedChords() -> [DiatonicChord]` (minor keys: harmonic-minor `V` and `V7`; major keys: `[]`)
  - `enum ScaleType: CaseIterable { case major, naturalMinor, harmonicMinor, dorian, phrygian, majorPentatonic, minorPentatonic; func pitchClasses(tonic: PitchClass) -> [PitchClass] }` (used for keyboard highlighting / scale lock)
  - `enum ChordQuality: String, Codable, CaseIterable { major, minor, diminished, augmented, major7, minor7, dominant7, halfDiminished7, sus2, sus4, add9, minor9, major9; var intervals: [Int]; var symbolSuffix: String; var isExtended: Bool }`
  - `struct Chord: Hashable, Codable`:
    - `root: PitchClass`, `quality: ChordQuality`
    - `init(parsing: String) throws`
    - `var pitchClasses: Set<PitchClass>`
    - `func symbol(in key: Key?) -> String`
  - `struct DiatonicChord: Hashable { let degree: Int; let roman: String; let chord: Chord }`
  - `enum Voicer { static func closeVoicing(_ c: Chord, inversion: Int = 0) -> [Int]; static func voiceLead(_ chords: [Chord]) -> [[Int]] }`
- Values pinned:
  - Interval tables: maj `[0,4,7]`, min `[0,3,7]`, dim `[0,3,6]`, aug `[0,4,8]`, maj7 `[0,4,7,11]`, m7 `[0,3,7,10]`, 7 `[0,4,7,10]`, m7b5 `[0,3,6,10]`, sus2 `[0,2,7]`, sus4 `[0,5,7]`, add9 `[0,4,7,14]`, m9 `[0,3,7,10,14]`, maj9 `[0,4,7,11,14]`.
  - Suffixes: `"" "m" "dim" "aug" "maj7" "m7" "7" "m7b5" "sus2" "sus4" "add9" "m9" "maj9"`. Parsing also accepts `°` = dim, `+` = aug, `ø7` = m7b5.
  - `isExtended` is true for maj7, m7, 7, m7b5, add9, m9, maj9.
  - Flat-spelled keys: majors F, Bb, Eb, Ab, Db, Gb; minors D, G, C, F, Bb, Eb. All others use sharps.
  - Close voicing puts the root in MIDI 48–59.
  - `voiceLead`: the first chord uses `closeVoicing`. Each later chord picks, among all inversions octave-shifted so the lowest note is in 48–62, the one minimizing the sum of |differences| between sorted voicings. Ties go to the lower inversion.

- [ ] **Step 1: Write failing tests**

```swift
@Test func keyParsingAndSpelling() throws {
    let am = try Key(parsing: "A minor")
    #expect(am.scalePitchClasses.map(\.rawValue) == [9, 11, 0, 2, 4, 5, 7])
    #expect(try Key(parsing: "Eb major").spell(PitchClass(10)) == "Bb")
    #expect(try Key(parsing: "E minor").spell(PitchClass(6)) == "F#")
    #expect(am.spell(midi: 69) == "A4")
    #expect(am.degree(of: PitchClass(4)) == 5)
    #expect(throws: (any Error).self) { try Key(parsing: "H minor") }
}
@Test func diatonicTriadsInAMinor() throws {
    let k = try Key(parsing: "A minor"), c = k.diatonicTriads()
    #expect(c.map(\.roman) == ["i", "ii°", "III", "iv", "v", "VI", "VII"])
    #expect(c.map { $0.chord.symbol(in: k) } == ["Am", "Bdim", "C", "Dm", "Em", "F", "G"])
}
@Test func diatonicSeventhsInCMajor() throws {
    let k = try Key(parsing: "C major"), c = k.diatonicSevenths()
    #expect(c.map(\.roman) == ["Imaj7", "ii7", "iii7", "IVmaj7", "V7", "vi7", "viiø7"])
    #expect(c.map { $0.chord.symbol(in: k) } == ["Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Bm7b5"])
}
@Test func harmonicMinorDominant() throws {
    let k = try Key(parsing: "A minor")
    #expect(k.borrowedChords().map { "\($0.roman)=\($0.chord.symbol(in: k))" } == ["V=E", "V7=E7"])
    #expect(try Key(parsing: "C major").borrowedChords().isEmpty)
}
@Test func chordParsing() throws {
    #expect(try Chord(parsing: "F#m7") == Chord(root: PitchClass(6), quality: .minor7))
    #expect(try Chord(parsing: "Bbmaj9") == Chord(root: PitchClass(10), quality: .major9))
    #expect(try Chord(parsing: "Bø7").quality == .halfDiminished7)
    #expect(throws: (any Error).self) { try Chord(parsing: "H7") }
}
@Test func voicing() throws {
    #expect(Voicer.closeVoicing(try Chord(parsing: "Am")) == [57, 60, 64])
    let v = Voicer.voiceLead([try Chord(parsing: "Am"), try Chord(parsing: "F")])
    #expect(v[1] == [57, 60, 65])
}
```

- [ ] **Step 2: Push. Expect `core-tests` FAIL** (types missing).
- [ ] **Step 3: Implement** the types above in the listed files.
- [ ] **Step 4: Push. Expect `core-tests` PASS.**
- [ ] **Step 5: Commit.** `feat(core): keys, scales, chords, voicing`

---

### Task 4: Timeline models and notation

**Files:**
- Create: `Sources/MusicCore/Timeline/{Ticks,NoteSequence,ChordProgression,DrumPattern,Notation}.swift`
- Test: `Tests/MusicCoreTests/TimelineTests.swift`

**Interfaces:**
- Consumes: `Chord(parsing:)`, `Voicer` (Task 3).
- Produces:
  - `enum Ticks { static let perQuarter = 96, perSixteenth = 24, perBar = 384 }`
  - `struct NoteEvent: Hashable, Codable { var start: Int; var length: Int; var pitch: Int; var velocity: Float = 0.8; var glide: Bool = false }`
  - `struct NoteSequence: Hashable, Codable { var notes: [NoteEvent] /*sorted by start*/; func notes(overlapping range: Range<Int>) -> [NoteEvent] }`
  - `struct ChordSlot: Hashable, Codable { var start: Int; var length: Int; var chord: Chord }`
  - `struct ChordProgression: Hashable, Codable { var slots: [ChordSlot]; func chord(at tick: Int) -> Chord?; func renderedNotes(velocity: Float = 0.7) -> NoteSequence /*uses Voicer.voiceLead*/ }`
  - `enum DrumLane: String, Codable, CaseIterable { kick, snare, clap, closedHat, openHat, rim, perc; var midiNote: Int }` with values kick 36, rim 37, snare 38, clap 39, closedHat 42, perc 45, openHat 46
  - `struct DrumHit: Hashable, Codable { var tick: Int; var velocity: Float; var pitchOffset: Int = 0 }`
  - `struct DrumPattern: Hashable, Codable`:
    - `var lanes: [DrumLane: [DrumHit]]`
    - `mutating func toggle(lane: DrumLane, step: Int)` (16th grid, velocity 0.8)
    - `mutating func fillRoll(lane: DrumLane, from: Int, to: Int, rate: RollRate, velocities: ClosedRange<Float>)`
  - `enum RollRate: Int, Codable, CaseIterable { case sixteenthTriplet = 16, thirtySecond = 12, thirtySecondTriplet = 8, sixtyFourth = 6 }` (raw value = ticks between hits)
  - `enum Notation`:
    - `static func melody(_ s: String) throws -> NoteSequence`
    - `static func chords(_ s: String) throws -> ChordProgression`
    - `static func drumLane(_ s: String) throws -> [DrumHit]`
- Notation rules (content authors depend on these exactly):
  - **Melody:** space-separated tokens `<Pitch><Octave>:<16ths>[~]` or `r:<16ths>`. Pitch accepts `#`/`b`. `C4` = 60. `~` sets `glide`.
  - **Chords:** `<Symbol>:<16ths>`, laid out back to back from tick 0.
  - **Drum lane:** one char per 16th step; length must be a multiple of 16. The characters:

    | Char | Meaning |
    |---|---|
    | `.` | rest |
    | `x` | hit at velocity 0.8 |
    | `X` | hit at velocity 1.0 |
    | `g` | ghost hit at velocity 0.4 |
    | `2` / `3` / `4` | 2/3/4 evenly spaced hits inside the step (1/32, 1/32T, 1/64), velocity 0.8 |
    | `TT` | must appear as a pair; 3 hits over 2 steps (1/16T) |

    Anything else, or a lone `T`, throws.

- [ ] **Step 1: Write failing tests**

```swift
@Test func tickConstants() { #expect(Ticks.perSixteenth == 24 && Ticks.perBar == 384) }
@Test func parseMelody() throws {
    let s = try Notation.melody("A4:4 r:4 C5:2 E5:6~")
    #expect(s.notes == [NoteEvent(start: 0, length: 96, pitch: 69),
                        NoteEvent(start: 192, length: 48, pitch: 72),
                        NoteEvent(start: 240, length: 144, pitch: 76, glide: true)])
}
@Test func parseDrumLane() throws {
    #expect(try Notation.drumLane("x...X...g...2...").map(\.tick) == [0, 96, 192, 288, 300])
    #expect(try Notation.drumLane("x...X...g...2...").map(\.velocity) == [0.8, 1.0, 0.4, 0.8, 0.8])
    #expect(try Notation.drumLane("TT..............").map(\.tick) == [0, 16, 32])
    #expect(try Notation.drumLane("3...............").map(\.tick) == [0, 8, 16])
    #expect(try Notation.drumLane("4...............").map(\.tick) == [0, 6, 12, 18])
    #expect(throws: (any Error).self) { try Notation.drumLane("x...") }
    #expect(throws: (any Error).self) { try Notation.drumLane("T...............") }
}
@Test func parseChords() throws {
    let p = try Notation.chords("Am:16 F:8 G:8")
    #expect(p.slots.map(\.start) == [0, 384, 576] && p.slots.map(\.length) == [384, 192, 192])
    #expect(p.chord(at: 400) == (try Chord(parsing: "F")))
}
@Test func rollFill() {
    var d = DrumPattern(lanes: [:])
    d.fillRoll(lane: .closedHat, from: 288, to: 384, rate: .thirtySecond, velocities: 0.5...1.0)
    let hits = d.lanes[.closedHat]!
    #expect(hits.map(\.tick) == [288, 300, 312, 324, 336, 348, 360, 372])
    #expect(hits.first!.velocity == 0.5 && hits.last!.velocity == 1.0)
}
@Test func toggleStep() {
    var d = DrumPattern(lanes: [:]); d.toggle(lane: .kick, step: 4)
    #expect(d.lanes[.kick]!.map(\.tick) == [96]); d.toggle(lane: .kick, step: 4)
    #expect(d.lanes[.kick, default: []].isEmpty)
}
```

- [ ] **Step 2: Push. Expect FAIL.**
- [ ] **Step 3: Implement.** `fillRoll` replaces existing hits in `[from, to)` on that lane, and velocities interpolate linearly from first to last hit.
- [ ] **Step 4: Push. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(core): timeline models and content notation`

---

### Task 5: Track model and persistence

**Files:**
- Create: `Sources/MusicCore/Track/{Track,TrackStore,Progress}.swift`
- Test: `Tests/MusicCoreTests/PersistenceTests.swift`

**Interfaces:**
- Consumes: `Key`, `NoteSequence`, `ChordProgression`, `DrumPattern`.
- Produces:
  - `enum PartRole: String, Codable, CaseIterable { melody, chords, drums, bass808, counter, texture }`
  - `enum InstrumentID: String, Codable, CaseIterable { trapKit, eight08, bell, pluck, pad, keys }`
  - `enum PartContent: Hashable, Codable { case notes(NoteSequence), chords(ChordProgression), drums(DrumPattern) }`
  - `struct SoundSettings: Hashable, Codable { var volume = 0.8, drive = 0.0, cutoff = 1.0, reverb = 0.15, delay = 0.0 }` (all 0…1)
  - `struct Part: Hashable, Codable, Identifiable { var id = UUID(); var role: PartRole; var instrument: InstrumentID; var content: PartContent; var sound = SoundSettings(); var muted = false }`
  - `struct Track: Hashable, Codable, Identifiable`:
    - `static let currentVersion = 1`
    - `var version = 1, id = UUID(), name: String, createdAt: Date, tempo: Double, key: Key, bars: Int, parts: [Part], completedStages: Set<String> = []`
    - `func part(_ role: PartRole) -> Part?`
    - `mutating func setPart(_ p: Part)` (replaces the part with the same role)
  - `struct LoadReport { var tracks: [Track]; var skipped: [URL] }`
  - `final class TrackStore`:
    - `init(directory: URL)`
    - `func loadAll() -> LoadReport` (sorted by `createdAt` desc)
    - `func save(_ t: Track) throws` (atomic write to `<id>.json`)
    - `func delete(id: UUID) throws`
  - `struct Progress: Codable, Equatable { var version = 1; var completedLessons: Set<String> = []; var currentLessonID: String?; var activeTrackID: UUID?; static let empty }`
  - `final class ProgressStore { init(fileURL: URL); func load() -> Progress; func save(_ p: Progress) throws }`
- Rules:
  - An undecodable track file is renamed to `<name>.corrupt` and listed in `skipped`.
  - A decodable file with `version > currentVersion` is skipped and **not** renamed.
  - An undecodable progress file is renamed `.corrupt` and `.empty` is returned.

- [ ] **Step 1: Write failing tests**: `trackRoundTrip` (encode → decode equal, all three content cases present); `loadAllSkipsCorruptAndRenames` (two valid files plus `bad.json` containing `"garbage"` → 2 tracks, `skipped.count == 1`, `bad.json.corrupt` exists); `newerVersionSkippedNotRenamed` (`"version": 99` → skipped, file still at original name); `deleteRemovesFile`; `corruptProgressResetsToEmpty` (returns `.empty`, `.corrupt` file exists); `setPartReplacesSameRole`. Use a fresh temp directory per test.
- [ ] **Step 2: Push. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Push. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(core): tracks, progress, resilient persistence`

---

### Task 6: Chord Finder

**Files:**
- Create: `Sources/MusicCore/Harmony/ChordFinder.swift`
- Test: `Tests/MusicCoreTests/ChordFinderTests.swift`

**Interfaces:**
- Consumes: `Key.diatonicTriads/diatonicSevenths/borrowedChords`, `NoteSequence`.
- Produces:
  - `struct ChordFit: Hashable { let chord: Chord; let roman: String; let score: Double; let matched: [PitchClass]; let clashes: [PitchClass] }`
  - `enum ChordFinder`:
    - `static func fits(melody: NoteSequence, window: Range<Int>, key: Key) -> [ChordFit]`
    - `static func fitsPerBar(melody: NoteSequence, bars: Int, key: Key) -> [[ChordFit]]`
- Algorithm (pinned):
  - **Candidates**, in tie-break order: diatonic triads, then diatonic sevenths, then borrowed chords.
  - **Note weight** = `(ticks of the note inside window / 96) × (note.start % 192 == 0 ? 1.5 : 1.0)`, summed per pitch class.
  - **Score** for each candidate and melody pitch class `pc` with weight `w`:
    - `pc` is a chord tone → `+w`
    - `(pc − 1) mod 12` is a chord tone (half step above a chord tone) → `−w`, and `pc` is recorded in `clashes`
    - otherwise → `+0.25w`
  - Then subtract `0.1 ×` (number of chord tones not present in the melody).
  - **Sort** by score descending; ties keep candidate order.

- [ ] **Step 1: Write failing tests**

```swift
@Test func minorTriadWinsForACE() throws {
    let m = try Notation.melody("A4:4 C5:4 E5:4 r:4")
    let f = ChordFinder.fits(melody: m, window: 0..<384, key: try Key(parsing: "C major"))
    #expect(f.first!.chord == (try Chord(parsing: "Am")) && abs(f.first!.score - 4.0) < 1e-9)
}
@Test func halfStepAboveChordToneIsClash() throws {
    let m = try Notation.melody("F4:8 C5:8")   // F weight 3.0, C weight 3.0
    let f = ChordFinder.fits(melody: m, window: 0..<384, key: try Key(parsing: "C major"))
    #expect(f.first!.chord == (try Chord(parsing: "F")) && abs(f.first!.score - 5.9) < 1e-9)
    let c = f.first { $0.chord == (try! Chord(parsing: "C")) }!
    #expect(c.clashes == [PitchClass(5)] && abs(c.score - (-0.2)) < 1e-9)
}
@Test func harmonicMinorVForLeadingTone() throws {
    let m = try Notation.melody("G#4:4 B4:4 E5:8")
    #expect(ChordFinder.fits(melody: m, window: 0..<384, key: try Key(parsing: "A minor")).first!.roman == "V")
}
@Test func perBarSplitsWindows() throws {
    let m = try Notation.melody("A4:16 F4:8 C5:8")
    let bars = ChordFinder.fitsPerBar(melody: m, bars: 2, key: try Key(parsing: "A minor"))
    #expect(bars.count == 2 && bars[1].first!.chord == (try Chord(parsing: "F")))
}
@Test func emptyWindowReturnsCandidatesWithoutCrash() throws {
    #expect(!ChordFinder.fits(melody: NoteSequence(notes: []), window: 0..<384, key: try Key(parsing: "A minor")).isEmpty)
}
```

- [ ] **Step 2: Push. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Push. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(core): chord finder`

---

### Task 7: Task checks (rule-based feedback)

**Files:**
- Create: `Sources/MusicCore/Checks/{TaskCheck,CheckRunner}.swift`
- Test: `Tests/MusicCoreTests/CheckTests.swift`

**Interfaces:**
- Consumes: `Track`, `ChordFinder`, `Key`.
- Produces:
  - `enum TaskCheck: Hashable, Codable` with JSON shape `{"kind": "<case>", …params}`. Cases (params in parentheses):
    - `tempoInRange(min: Double, max: Double)`
    - `inKey(role: PartRole)`
    - `noteCount(role: PartRole, min: Int, max: Int?)`
    - `barRhythmRepeats(role: PartRole)`
    - `endsOnDegree(role: PartRole, degrees: [Int])`
    - `chordCount(role: PartRole, min: Int, max: Int?)`
    - `chordsInKey(role: PartRole)`
    - `chordDegrees(role: PartRole, required: [Int])`
    - `chordsFitMelody(chords: PartRole, melody: PartRole, minScoreRatio: Double)`
    - `extendedChordCount(role: PartRole, min: Int)`
    - `drumHitOnBeats(lane: DrumLane, beats: [Int], everyBar: Bool)`
    - `laneHitCount(lane: DrumLane, min: Int)`
    - `hatRollPresent`
    - `syncopatedKicks(min: Int)`
    - `barsDiffer(role: PartRole)`
  - `struct CheckResult: Hashable { let check: TaskCheck; let passed: Bool; let message: String }`
  - `enum CheckRunner { static func run(_ checks: [TaskCheck], on track: Track) -> [CheckResult] }`
- Definitions (pinned):
  - `barRhythmRepeats`: at least two bars share the same set of note-start offsets within the bar.
  - `endsOnDegree`: the pitch class of the last-starting note has a key degree in `degrees`.
  - `chordsInKey`: every chord tone is in the key, or the chord is one of `borrowedChords()`.
  - `chordDegrees`: each listed degree's diatonic root appears as some chord's root.
  - `chordsFitMelody`: for each bar, (score of the chord at bar start) ≥ `minScoreRatio ×` (best score that bar). Bars with no melody pass.
  - `drumHitOnBeats`: beats are 1-based quarter positions; there must be a hit at tick `(beat − 1) × 96` in every bar (or any bar if `everyBar` is false).
  - `hatRollPresent`: the closedHat or openHat lane has two hits less than 24 ticks apart.
  - `syncopatedKicks`: count of kick hits with `tick % 96 != 0`.
  - `barsDiffer`: at least one bar's content differs from bar 1.
  - A role or lane that is missing → `passed: false` with a message naming what's missing.
- Messages: short, friendly, specific. Name the offending notes (spelled in key) or bars, e.g. "Bar 2: G# isn't in A minor." Pass messages praise the specific thing.

- [ ] **Step 1: Write one parameterized failing test** `checksPassAndFail` over this table. Each row builds a track in A minor at 140 BPM, 2 bars, from notation, and asserts `passed` for the pass input and `!passed` for the fail input. Add `missingRoleFailsWithMessage` (message contains `"melody"`).

| Check | Pass input | Fail input |
|---|---|---|
| tempoInRange(60,180) | tempo 140 | tempo 200 |
| inKey(melody) | `A4:4 C5:4 E5:8` | `A4:4 G#4:4 E5:8` |
| noteCount(melody,3,6) | `A4:4 C5:4 E5:8` | `A4:16` |
| barRhythmRepeats(melody) | `A4:4 C5:4 E5:8 A4:4 D5:4 E5:8` | `A4:4 C5:4 E5:8 A4:8 D5:8` |
| endsOnDegree(melody,[1,5]) | `C5:8 A4:8` | `C5:8 B4:8` |
| chordCount(chords,4,nil) | `Am:8 F:8 C:8 G:8` | `Am:16 F:16` |
| chordsInKey(chords) | `Am:16 E7:16` | `Am:16 D:16` |
| chordDegrees(chords,[1,4,5]) | `Am:8 Dm:8 Em:16` | `Am:16 F:16` |
| chordsFitMelody(.6) melody `A4:16 F4:16` | `Am:16 F:16` | `Am:16 E:16` |
| extendedChordCount(chords,2) | `Am7:16 Fmaj7:16` | `Am7:16 F:16` |
| drumHitOnBeats(snare,[3],true) | snare `........x.......` ×2 | bar 2 snare missing |
| laneHitCount(closedHat,8) | hats `x.x.x.x.x.x.x.x.` | `x...x...........` |
| hatRollPresent | hats `x.x.x.x.x.x.2.x.` | `x.x.x.x.x.x.x.x.` |
| syncopatedKicks(2) | kick `x..x..x.........` | `x...x...x...x...` |
| barsDiffer(drums) | kick bar1 `x.......` / bar2 `x..x..x.` | identical bars |

- [ ] **Step 2: Push. Expect FAIL.**
- [ ] **Step 3: Implement.** Codable uses a `kind` discriminator matching the case names exactly.
- [ ] **Step 4: Push. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(core): rule-based task checks`

---

### Task 8: Content model, loader, validator, journey file

**Files:**
- Create: `Sources/MusicCore/Content/{ContentModel,ContentLibrary,ContentValidator}.swift`
- Modify: `Content/journey.json` (all 8 stages)
- Test: `Tests/MusicCoreTests/ContentTests.swift`, fixture `Tests/MusicCoreTests/Fixtures/sample-lesson.json`

**Interfaces:**
- Consumes: `Notation`, `TaskCheck`, `Track`.
- Produces:
  - `struct Stage: Codable, Identifiable { let id, title, tagline: String; let order: Int; let lessons: [String]; var isAvailable: Bool { !lessons.isEmpty } }`
  - `struct Journey: Codable { let version: Int; let stages: [Stage] }`
  - `struct ClipPart: Codable { let role: PartRole; let instrument: InstrumentID; let melody: String?; let chords: String?; let drums: [DrumLane: String]?; let sound: SoundSettings? }` (exactly one of melody/chords/drums)
  - `struct Clip: Codable { let tempo: Double; let key: String; let bars: Int; let parts: [ClipPart]; func makeTrack(name: String) throws -> Track }`
  - `struct Example: Codable { let label, explanation: String; let clip: Clip }`
  - `enum ToolKind: String, Codable { trackSetup, melodyEditor, chordPads, chordFinder, drumGrid }`
  - `enum LessonStep: Codable` (discriminator `type`):
    - `idea(title: String, body: String, deeper: String?)` (body and deeper are Markdown)
    - `listen(title: String, caption: String, examples: [Example])`
    - `task(title: String, prompt: String, tool: ToolKind, targetRole: PartRole?, uses: [PartRole], starter: Clip?, checks: [TaskCheck], hints: [String])`
    - `keep(message: String, roles: [PartRole])`
    - `koala(body: String)`
  - `struct Lesson: Codable, Identifiable { let id, stage, title, summary: String; let steps: [LessonStep] }`
  - `final class ContentLibrary { init(directory: URL) throws; let journey: Journey; func lesson(_ id: String) -> Lesson?; func lessons(in stage: Stage) -> [Lesson] }`
  - `enum ContentValidator { static func validate(directory: URL) -> [String] /* human-readable errors */ }`
- Validator rules (each must produce an error):
  - A stage lists a lesson with no file.
  - A lesson file's `stage` doesn't match the stage listing it.
  - Any clip's notation fails to parse, or its key fails to parse.
  - A task check references a role that is neither `targetRole` nor in `uses`.
  - A task `uses` a role, but its `starter` lacks that role.
  - A drum check exists in a task whose tool isn't `drumGrid`.
  - Duplicate lesson ids.
- Journey stages (ids, titles, taglines exactly as spec §5.1):
  1. `first-sounds` "First sounds" "tempo, key, picking a vibe"
  2. `the-idea` "The idea" "melody or loop as your seed"
  3. `harmony` "Harmony" "chords that fit your melody"
  4. `drums-groove` "Drums & groove" "patterns that lock with it"
  5. `eight08-bass` "808 & bass" "following the chords, sliding"
  6. `layers` "Layers" "counter-melodies, texture"
  7. `arrangement` "Arrangement" "loop → intro/verse/hook/bridge"
  8. `room-for-vocals` "Leave room for vocals" "space for the rapper or singer"

  Stages 5–8 have `lessons: []` in Phase 1.

- [ ] **Step 1: Write failing tests:**
  - `decodesSampleLesson`: the fixture covers every step type → steps count and types match.
  - `clipMakesTrack`: tempo, key, and part roles carried over; melody parsed.
  - `validatorFlagsEachRule`: one malformed temp content dir per rule → at least one error mentioning the lesson id.
  - `repoContentIsValid`: locate `Content/` via `#filePath` → `../../../../Content` → `ContentValidator.validate(...) == []`.
- [ ] **Step 2: Push. Expect FAIL.**
- [ ] **Step 3: Implement**, and write `journey.json` (stages 1–4 lessons lists stay empty until Tasks 20–23 add them).
- [ ] **Step 4: Push. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(core): lesson content model and validator`

---

### Task 9: DSP primitives

**Files:**
- Create: `Sources/SoundEngine/DSP/{Envelope,Oscillators,Filter,Drive,Delay,Reverb}.swift`
- Test: `Tests/SoundEngineTests/DSPTests.swift`, helper `Tests/SoundEngineTests/Measure.swift` (`rms`, `peak`, `estimatedFrequency(zeroCrossings:)`, `allFinite`)

**Interfaces:**
- Produces (all `struct`s with `mutating func process`/`next` and value-only state, no heap allocation after init except `Delay`/`Reverb` buffers allocated in `init`):
  - `ADSR(attack:decay:sustain:release:sampleRate:)` with `gate(on:)`, `next() -> Float`, `isIdle: Bool`
  - `SineOsc`, `SawOsc` (PolyBLEP), `NoiseGen(seed:)`: each has `next(frequency:) -> Float`. `NoiseGen.next() -> Float` is deterministic for a seed.
  - `SVFilter(sampleRate:)`: `process(_ x: Float, cutoff: Float, resonance: Float, mode: .lowpass | .highpass | .bandpass) -> Float`
  - `Drive.process(_ x: Float, amount: Float) -> Float`: `amount == 0` is identity; otherwise `tanh(x·(1+9·amount)) / tanh(1+9·amount)`.
  - `TempoDelay(maxSeconds: 2, sampleRate:)`: `process(_ x: Float, delaySamples: Int, feedback: Float, mix: Float) -> Float`
  - `Reverb(sampleRate:)`: Freeverb topology (8 combs + 4 allpasses per side, standard tunings scaled to sample rate). `process(l:r:mix:) -> (Float, Float)`.

- [ ] **Step 1: Write failing tests:**
  - `adsrTiming`: at 48 kHz with A 0.01 / D 0.1 / S 0.5 / R 0.2, the value is within 0.01 of 0.5 at sample 5280, and idle after 9600 samples of release.
  - `sawFrequency`: 220 Hz is estimated within 2%.
  - `lowpassAttenuates`: a 5 kHz sine through a 500 Hz LP is ≥ 20 dB lower RMS.
  - `driveZeroIsIdentity` and `driveBounded` (|out| ≤ 1 for inputs in ±4).
  - `delayEchoArrives`: an impulse with delay 4800 → peak at 4800.
  - `reverbTailDecays`: after an impulse, RMS of the window at 5 s is < −60 dB relative to the first 100 ms.
  - `noiseDeterministic`: same seed gives the same first 64 values.
  - `allOutputsFinite`.
- [ ] **Step 2: Push. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Push. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(engine): DSP primitives`

---

### Task 10: Instruments, voices, voice pool

**Files:**
- Create: `Sources/SoundEngine/Instruments/{DrumSynth,InstrumentPreset,Voice,VoicePool}.swift`
- Test: `Tests/SoundEngineTests/InstrumentTests.swift`

**Interfaces:**
- Consumes: Task 9 DSP; `InstrumentID`, `DrumLane`, `SoundSettings` (MusicCore).
- Produces:
  - `enum DrumSynth { static func render(_ lane: DrumLane, sampleRate: Double) -> [Float] }` (one-shot buffers, built once at engine init):
    - kick: sine sweeping 150 → 50 Hz over 40 ms, 0.45 s decay
    - snare: 180 Hz tone + band-passed noise, 0.2 s
    - clap: 3 noise bursts 10 ms apart + 0.15 s tail
    - closedHat: high-passed noise, 0.04 s
    - openHat: high-passed noise, 0.3 s
    - rim: short 800 Hz click
    - perc: pitched tom at 140 Hz
  - `struct InstrumentPreset { let id: InstrumentID; static func make(_ id: InstrumentID) -> InstrumentPreset }`. Voice recipes:
    - eight08: sine + 10% 2nd harmonic, +12-semitone pitch drop over 30 ms on onset, A 1 ms / R 0.15 s, glide 60 ms when `NoteEvent.glide`
    - bell: 2-op FM, ratio 1:3.5, index decaying from 4 to 0 over 1 s
    - pluck: Karplus-Strong
    - pad: 3 saws detuned ±7 cents, A 0.4 s / R 1.2 s
    - keys: FM e-piano, 1:1 body + 1:14 tine with fast decay
    - trapKit: plays DrumSynth buffers; pitch maps to lane via `DrumLane.midiNote`, and `pitchOffset` shifts playback rate
  - `struct Voice` (render one sample; owns ADSR + oscillators; `isFinished`)
  - `final class VoicePool`:
    - `init(maxVoices: Int = 32, sampleRate: Double)`
    - `func noteOn(channel: Int, instrument: InstrumentID, pitch: Int, velocity: Float, glide: Bool)`
    - `func noteOff(channel: Int, pitch: Int)`, `func releaseAll(channel: Int?)`
    - `func render(channel: Int, frames: Int, into: UnsafeMutablePointer<Float>)`
    - `var activeCount: Int`
  - Stealing order: oldest released voice first, else oldest voice. A glide note-on on a channel with a sounding eight08 voice retunes that voice instead of starting a new one. Channels = part index (0–7) plus channel 8 for live play.

- [ ] **Step 1: Write failing tests:**
  - `eight08Pitch`: MIDI 33 → frequency 55 Hz ±3% measured over 50–250 ms.
  - `glideMovesPitch`: 33 then 45 with glide → mid-glide frequency strictly between 55 and 110, and `activeCount == 1`.
  - `voiceCapAndStealing`: 200 rapid note-ons → `activeCount <= 32`, output finite.
  - `releaseAllSilences`: after `releaseAll` and 2 s of rendering, peak < 1e-4.
  - `kickIsLow`: kick buffer after 50 ms is estimated < 120 Hz.
  - `everyPresetProducesSound`: each `InstrumentID` at MIDI 60 gives peak > 0.05 within 100 ms.
- [ ] **Step 2: Push. Expect FAIL.**
- [ ] **Step 3: Implement.** Preallocate voice storage; render must not allocate.
- [ ] **Step 4: Push. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(engine): instruments and voice pool`

---

### Task 11: Renderer and sequencer

**Files:**
- Create: `Sources/SoundEngine/Render/{PlaybackSnapshot,CommandQueue,Renderer}.swift`
- Test: `Tests/SoundEngineTests/RendererTests.swift`

**Interfaces:**
- Consumes: `Track`, `ChordProgression.renderedNotes`, `VoicePool`, DSP effects.
- Produces:
  - `struct PlaybackSnapshot { let tempo: Double; let loopTicks: Int; let parts: [PartPlayback]; init(track: Track) }`, where `PartPlayback { instrument; sound: SoundSettings; muted: Bool; events: [ScheduledNote] /*sorted*/ }` and `ScheduledNote { start, end, pitch: Int; velocity: Float; glide: Bool }`. Drums become events with `end = start + 1`.
  - `enum EngineCommand { case play(fromTick: Int), stop, noteOn(InstrumentID, Int, Float), noteOff(InstrumentID, Int) }`
  - `final class CommandQueue` (SPSC ring buffer, capacity 256, built on `Synchronization.Atomic<Int>` indices): `push(_:) -> Bool`, `pop() -> EngineCommand?`
  - `final class Renderer: @unchecked Sendable`:
    - `init(sampleRate: Double)`
    - `func setSnapshot(_ s: PlaybackSnapshot)` (UI thread; stored in `Mutex<PlaybackSnapshot?>` as pending)
    - `func send(_ c: EngineCommand)`
    - `func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>)` (RT)
    - `var playheadTick: Int` (atomic read)
    - `var isPlaying: Bool`
- Rules (pinned):
  - Each render call: take the pending snapshot via `withLockIfAvailable`, drain commands, then render sample-accurately.
  - Event sample offset = `round(tick × sampleRate × 60 / (tempo × 96))`, computed from the absolute tick every time (no accumulation).
  - The loop wraps at `loopTicks`. Notes still sounding at the wrap get note-off at the wrap.
  - On snapshot swap, voices of parts whose events changed are released.
  - `stop` releases all channels.
  - Per-part chain: voice sum → volume → drive → SV lowpass (cutoff mapped 0…1 → 200 Hz–18 kHz exponential) → delay (dotted 1/8 synced to tempo, feedback 0.35, mix = `delay`) → reverb send (`reverb`). A shared reverb is followed by a master soft clip (`tanh`), so output stays within ±1.

- [ ] **Step 1: Write failing tests:**
  - `onsetIsSampleAccurate`: 120 BPM at 48 kHz, one bell note at tick 96 → first |sample| > 1e-6 at index 24000.
  - `loopRetriggers`: 1-bar loop, note at tick 0 → onsets at 0 and 96000.
  - `noteCrossingLoopEndIsReleased`: 1-bar loop, pad note from tick 288 with length 384 → at loop wrap a note-off is issued. Silent by 2 s after stop with no further events (peak < 1e-4).
  - `stopSilences`: stop mid-chord → peak < 1e-4 after 2 s.
  - `snapshotSwapReleasesChangedPart`: replace the melody while playing → old held note stops within release time.
  - `liveNoteOnPlaysWhileStopped`: `send(.noteOn(.keys, 60, 0.8))` → next render block has peak > 0.05.
  - `outputBounded`: 8 parts all at drive 1 and volume 1 → |sample| ≤ 1, all finite.
- [ ] **Step 2: Push. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Push. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(engine): sample-accurate sequencer and renderer`

---

### Task 12: Offline render and WAV export

**Files:**
- Create: `Sources/SoundEngine/Export/{OfflineRenderer,WAVWriter,ExportNaming}.swift`
- Test: `Tests/SoundEngineTests/ExportTests.swift`

**Interfaces:**
- Consumes: `Renderer`, `PlaybackSnapshot`, `Track`.
- Produces:
  - `struct StereoBuffer { var left: [Float]; var right: [Float]; var frameCount: Int }`
  - `enum OfflineRenderer`:
    - `static func render(track: Track, onlyPart: UUID? = nil, loopReady: Bool, sampleRate: Double = 48000) -> StereoBuffer`
    - `static func frameCount(bars: Int, tempo: Double, sampleRate: Double) -> Int` = `round(bars × 4 × 60 / tempo × sampleRate)`
  - `loopReady == true` renders the loop twice and keeps the second pass, so tails wrap into the start like they do when looped in Koala.
  - `enum WAVWriter { static func write(_ b: StereoBuffer, sampleRate: Int = 48000, to url: URL) throws }` (16-bit PCM, interleaved)
  - `enum ExportNaming { static func fileName(track: Track, part: Part?) -> String }` → `"<name>-<tempo>bpm-<Key no spaces>[-<role>].wav"`. Name is sanitized to `[A-Za-z0-9-_]`, max 40 chars, and falls back to `"track"` if empty. Tempo is a rounded integer.

- [ ] **Step 1: Write failing tests:**
  - `exactLength`: 4 bars at 140 BPM → `frameCount == 329143`, and the rendered buffer has exactly that many frames.
  - `loopReadyEqualsSecondPass`: compare with a manual 2-pass render.
  - `wavHeader`: read back the bytes → `RIFF`/`WAVE`/`fmt ` PCM 1, 2 channels, 48000, 16-bit, data size `frames × 4`; samples round-trip within 1/32768.
  - `soloPartRendersOnlyThatPart`: drums-only render of a track with melody and drums ≈ drums-solo render (identical).
  - `fileNameSanitized`: `"My Beat!!"` at 140.4 BPM in A minor, chords → `"My-Beat-140bpm-Aminor-chords.wav"`.
  - `emptyTrackExportsSilence`: no parts → correct length, all zeros, no crash.
- [ ] **Step 2: Push. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Push. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(engine): offline render and WAV export`

---

### Task 13: Audio host and app model

**Files:**
- Create: `App/Sources/Audio/{AudioHost,AVAudioEngineController,AudioPlayer}.swift`, `App/Sources/AppModel.swift`
- Modify: `App/Sources/BrokenApp.swift` (build `AppModel` from bundle `Content/` and Documents `tracks/` + `progress.json`; inject via `.environment`)
- Test: `App/Tests/AudioHostTests.swift`, `App/Tests/AppModelTests.swift`

**Interfaces:**
- Consumes: `Renderer`, `PlaybackSnapshot`, `TrackStore`, `ProgressStore`, `ContentLibrary`, `Clip.makeTrack`.
- Produces:
  - `protocol AudioSessionControlling { func configure() throws }`. The real version sets `.playback`, `[.mixWithOthers]`, preferred IO buffer 0.005 s, and activates.
  - `protocol AudioEngineControlling: AnyObject { var isRunning: Bool { get }; func start() throws; func stop() }`
  - `final class AudioHost`:
    - `init(session:, makeEngine: () -> AudioEngineControlling, center: NotificationCenter = .default)`
    - `func start() throws`
    - `var category: String` (for test assertion)
    - Observes `AVAudioSession.interruptionNotification` (ended → `configure` + `start`), `routeChangeNotification` (restart if not running), `mediaServicesWereResetNotification` (rebuild via `makeEngine`, then start), and `UIApplication.willEnterForegroundNotification` (restart if not running).
  - `AVAudioEngineController: AudioEngineControlling` wraps `AVAudioEngine` plus an `AVAudioSourceNode` (stereo, non-interleaved float, hardware sample rate) that calls `Renderer.render`.
  - `protocol AudioPlaying: AnyObject`:
    - `func setTrack(_ t: Track)`, `func play()`, `func stop()`
    - `func noteOn(_ i: InstrumentID, _ pitch: Int, _ vel: Float)`, `func noteOff(_ i: InstrumentID, _ pitch: Int)`
    - `var playheadTick: Int { get }`, `var isPlaying: Bool { get }`
  - `AudioPlayer: AudioPlaying` sits over `Renderer`.
  - `@Observable @MainActor final class AppModel`:
    - `init(content: ContentLibrary, trackStore: TrackStore, progressStore: ProgressStore, audio: AudioPlaying)`
    - `var tracks: [Track]`, `var activeTrack: Track?`, `var progress: Progress`, `var skippedFiles: [URL]`
    - `func newTrack(name: String, tempo: Double, key: Key) -> Track`
    - `func setActive(_ id: UUID)`
    - `func updateActiveTrack(_ mutate: (inout Track) -> Void)` (persists, then `audio.setTrack`)
    - `func workingTrack(for step: LessonStep, lessonID: String) -> Track`
    - `func keep(roles: [PartRole], from working: Track, lessonID: String)`
    - `func markLessonComplete(_ id: String)`
- Rules:
  - `workingTrack` starts from a copy of the active track. If there's no active track, it uses the starter's tempo/key, or 140 BPM A minor by default. For every role in `uses` that's missing, it inserts the starter's part.
  - `keep` copies those roles' parts into the active track, creating the track from the working track's tempo/key if none exists. It sets `progress.activeTrackID`, marks the lesson complete, and persists both.

- [ ] **Step 1: Write failing tests:**
  - `interruptionEndedRestartsEngine`: fake engine; post began then ended (`AVAudioSessionInterruptionTypeKey`) → `start` called twice in total, and `configure` called again.
  - `routeChangeRestartsStoppedEngine`.
  - `mediaResetRebuildsEngine`: factory called twice.
  - `sessionIsPlaybackCategory`: real session's `category == .playback` after `configure()`; runs on simulator.
  - `workingTrackUsesStarterWhenNoTrack`: no active track, chord-finder step `uses: [.melody]` with a starter melody → working track has the melody.
  - `workingTrackPrefersOwnersPart`.
  - `keepCreatesTrackAndPersists`: new `TrackStore` on the same dir loads one track with the chords part; progress has the lesson complete.
  - `skippedFilesSurfaced`: a corrupt file in the dir → `skippedFiles.count == 1`.
- [ ] **Step 2: Commit and trigger `app` (`workflow_dispatch`). Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Trigger `app`. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(app): audio host with interruption recovery, app model`

---

### Task 14: Melody editor (keyboard, piano roll, live record) and transport

**Files:**
- Create: `App/Sources/Tools/MelodyEditor/{KeyboardView,PianoRollView,PianoRollModel,LiveRecorder}.swift`, `App/Sources/Tools/{TransportBar,SoundControlsView}.swift`
- Test: `App/Tests/ToolModelTests.swift` (melody section)

**Interfaces:**
- Consumes: `AppModel`, `AudioPlaying`, `Key`, `ScaleType`, `NoteSequence`.
- Produces:
  - `KeyboardView(key: Key, scale: ScaleType, scaleLock: Binding<Bool>, octave: Binding<Int>, instrument: InstrumentID, onNote: (Int, Bool) -> Void)`. Two-octave playable keys. Out-of-scale keys are dimmed, or hidden when scale lock is on. Each key shows its note name and scale degree. Note-on fires on touch-down; multitouch is supported.
  - `@Observable final class PianoRollModel`:
    - `init(sequence: NoteSequence, bars: Int, key: Key, lowestPitch: Int)`
    - `func toggle(step: Int, pitch: Int)` (adds a 1-step note or removes the covering note)
    - `func resize(noteAt step: Int, pitch: Int, toSteps: Int)`
    - `func toggleGlide(step: Int, pitch: Int)`
    - `var sequence: NoteSequence`
  - `PianoRollView(model:, playheadTick: Int)`
  - `struct LiveRecorder { mutating func noteOn(pitch: Int, atTick: Int); mutating func noteOff(pitch: Int, atTick: Int); func result(loopTicks: Int) -> NoteSequence }` (quantize start and length to the nearest 16th, minimum length 1 step, wrap at loop end)
  - `TransportBar(isPlaying:, tempo: Binding<Double>, metronome: Binding<Bool>, onPlay:, onStop:)`. Tempo range 60–180. The metronome uses trapKit rim on each beat.
  - `SoundControlsView(settings: Binding<SoundSettings>)`: volume, drive, tone (cutoff), reverb, delay sliders.
- Latency: keyboard touch → `audio.noteOn` synchronously on the main thread (no async hop).

- [ ] **Step 1: Write failing model tests:**
  - `toggleAddsAndRemoves`.
  - `resizeChangesLength`.
  - `glideToggles`.
  - `recorderQuantizes`: on at tick 30, off at tick 70 → note start 24, length 48.
  - `recorderWrapsAtLoopEnd`: note held past `loopTicks` → length clipped to the loop end.
- [ ] **Step 2: Trigger `app`. Expect FAIL.**
- [ ] **Step 3: Implement** models and views, following `ui-notes.md`.
- [ ] **Step 4: Trigger `app`. Expect PASS.**
- [ ] **Step 5: Owner checkpoint (instrument feel).** Temporarily make the keyboard + piano roll the root screen. Build the IPA with `[ipa]` and ask the owner to sideload it. Confirm notes sound instantly, nothing crackles, and sound plays with the silent switch on. Adjust before continuing if the keyboard feels laggy.
- [ ] **Step 6: Commit.** `feat(app): melody editor, live record, transport`

---

### Task 15: Drum grid

**Files:**
- Create: `App/Sources/Tools/DrumGrid/{DrumGridView,DrumGridModel}.swift`
- Test: `App/Tests/ToolModelTests.swift` (drum section)

**Interfaces:**
- Consumes: `DrumPattern`, `RollRate`, `AudioPlaying`.
- Produces:
  - `@Observable final class DrumGridModel`:
    - `init(pattern: DrumPattern, bars: Int)`
    - `var pattern: DrumPattern`, `var selectedBar: Int`
    - `func toggle(lane: DrumLane, step: Int)`
    - `func setVelocity(lane: DrumLane, step: Int, _ v: Float)`
    - `func roll(lane: DrumLane, fromStep: Int, toStep: Int, rate: RollRate, ramp: ClosedRange<Float>)`
    - `func clearRolls(lane: DrumLane, step: Int)`
    - `func copyBar(_ from: Int, to: Int)`
    - `var swing: Double` (0–0.6; applied to off-beat 16ths at snapshot build by shifting `tick % 48 == 24` hits by `swing × 12` ticks)
  - Swing lives on the drums part. Add `var swing: Double = 0` to `DrumPattern` (Codable default 0) and apply it in `PlaybackSnapshot.init`.
  - `DrumGridView(model:, playheadTick:)`:
    - 16 steps × the 7 lanes, plus a bar selector.
    - Tap toggles a step; long-press opens velocity.
    - A roll tool: drag across steps, pick a `RollRate` and a ramp up/down.
    - Pads row for live finger drumming (`noteOn(.trapKit, lane.midiNote, v)`).
- Note: swing changes `Timeline` and `PlaybackSnapshot`. Add a MusicCore test `swingShiftsOffbeats` and a SoundEngine test `swingAppliedInSnapshot` in this task, pushed to `core-tests`.

- [ ] **Step 1: Write failing tests:**
  - `gridToggle`.
  - `rollCreatesSubdividedHits` (1/32 over 2 steps → 4 hits).
  - `copyBar`.
  - `swingShiftsOffbeats` (core).
  - `swingAppliedInSnapshot` (engine).
- [ ] **Step 2: Push + trigger `app`. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Expect PASS** on both jobs.
- [ ] **Step 5: Commit.** `feat(app): drum grid with rolls, velocity, swing`

---

### Task 16: Chord pads and Chord Finder view

**Files:**
- Create: `App/Sources/Tools/Chords/{ChordPadsView,ChordFinderView,ChordFinderModel}.swift`
- Test: `App/Tests/ToolModelTests.swift` (chords section)

**Interfaces:**
- Consumes: `Key.diatonicTriads/diatonicSevenths/borrowedChords`, `ChordFinder.fitsPerBar`, `ChordProgression`, `Voicer`.
- Produces:
  - `ChordPadsView(key: Key, showSevenths: Binding<Bool>, onChord: (Chord) -> Void, progression: Binding<ChordProgression>, bars: Int)`:
    - A pad per diatonic chord (+ borrowed), labeled symbol + roman numeral; tap to hear it.
    - A quality switcher on long-press: triad / 7 / 9 / sus2 / sus4.
    - A slot strip (1 chord per bar, or 2 per bar via a toggle) to place chords.
  - `@Observable final class ChordFinderModel`:
    - `init(melody: NoteSequence, bars: Int, key: Key)`
    - `var fitsPerBar: [[ChordFit]]` (top 5 per bar)
    - `func choose(bar: Int, fit: ChordFit)`
    - `var progression: ChordProgression`
    - `func audition(bar: Int, fit: ChordFit) -> Track` (temporary track: melody + that chord over that bar, looped)
  - `ChordFinderView(model:)`:
    - Per bar, show the melody notes as chips, colored chord-tone / color / clash per the fit.
    - Ranked fits with a score bar.
    - Tap a fit to audition it under the melody; "Use" sets that bar's chord.

- [ ] **Step 1: Write failing tests:**
  - `finderTopFitsLimitedToFive`.
  - `chooseWritesSlotForBar` (bar 1 → slot start 384, length 384).
  - `auditionTrackHasMelodyAndChord`.
- [ ] **Step 2: Trigger `app`. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Trigger `app`. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(app): chord pads and chord finder`

---

### Task 17: Journey map, Your Track bar, track setup and management

**Files:**
- Create: `App/Sources/Journey/{JourneyMapView,YourTrackBar,TrackListView}.swift`, `App/Sources/Tools/TrackSetupView.swift`
- Modify: `BrokenApp.swift` (root = `JourneyMapView` in a `NavigationStack`; remove the Task 14 temporary root)
- Test: `App/Tests/AppModelTests.swift` (journey section)

**Interfaces:**
- Consumes: `AppModel`, `ContentLibrary.journey`, `Progress`.
- Produces:
  - `extension AppModel`:
    - `func stageStatus(_ s: Stage) -> StageStatus` (`.done` / `.inProgress` / `.notStarted` / `.comingLater`)
    - `var currentStageID: String?` (first available stage not done)
    - `func nextLesson(in s: Stage) -> Lesson?`
  - `JourneyMapView`:
    - Your Track bar on top.
    - All 8 stages in order, each with status icon, title, and tagline; a "you're here" marker on the current stage.
    - Stages 5–8 show "coming in a later update" and can't be opened.
    - Tapping an available stage lists its lessons with completion state. **Nothing is locked.**
    - A "Style guides" row shows "coming later" in Phase 1.
  - `YourTrackBar`: track name, play/stop of the full loop, segment chips per role present (melody/chords/drums…), tap to open `TrackListView`.
  - `TrackListView`: list, new, rename, delete (with confirmation), set active; shows "N files couldn't be read" if `skippedFiles` is non-empty.
  - `TrackSetupView(tempo:, key:)`: tempo slider 60–180 with genre hints (trap 130–170, cloud 60–80 / 130–160) and a key picker (12 tonics × major/minor). Used by the `trackSetup` tool.

- [ ] **Step 1: Write failing tests:**
  - `stageStatuses` (available/coming-later/done from progress).
  - `currentStageIsFirstUnfinished`.
  - `nextLessonSkipsCompleted`.
- [ ] **Step 2: Trigger `app`. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Trigger `app`. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(app): journey map, your track bar, track management`

---

### Task 18: Lesson player

**Files:**
- Create: `App/Sources/Lesson/{LessonPlayerView,StepViews,TaskStepModel}.swift`
- Test: `App/Tests/AppModelTests.swift` (lesson section)

**Interfaces:**
- Consumes: `Lesson`, `LessonStep`, `CheckRunner`, `AppModel.workingTrack/keep/markLessonComplete`, all tool views.
- Produces:
  - `@Observable @MainActor final class TaskStepModel`:
    - `init(step: LessonStep /*task*/, lessonID: String, app: AppModel)`
    - `var working: Track`
    - `func runChecks() -> [CheckResult]`
    - `var allPassed: Bool`
    - `var hintIndex: Int`, `func nextHint() -> String?`
  - `LessonPlayerView(lesson:)`: one step per page with a progress dots header; Next/Back. Step views:
    - **idea:** Markdown body via `AttributedString(markdown:)`, plus a "Go deeper" disclosure.
    - **listen:** example cards; each plays its clip (`Clip.makeTrack`) with mute toggles per part, so the owner can hear what each part adds.
    - **task:** the prompt plus the tool for `ToolKind`, bound to the working track's `targetRole` part (created empty if missing) and with `uses` parts audible. A **Check** button shows each result (✓/✗ + message). Hints appear on demand. "Continue" is always enabled, but labeled "Continue anyway" until all checks pass.
    - **keep:** shows the message and calls `keep(roles:)`. For each role the active track already has, it asks first: replace, or skip that role.
    - **koala:** the body, plus a button that opens the Export sheet (Task 19).
  - Finishing the last step calls `markLessonComplete`.

- [ ] **Step 1: Write failing tests:**
  - `taskChecksRunAgainstWorkingTrack`.
  - `continueAnywayAvailableWhenFailing` (model exposes `canContinue == true` and `allPassed == false`).
  - `hintsAdvanceAndStop`.
  - `finishingMarksComplete`.
- [ ] **Step 2: Trigger `app`. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Trigger `app`. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(app): lesson player`

---

### Task 19: Export to Koala

**Files:**
- Create: `App/Sources/Export/{ExportSheet,ExportModel}.swift`
- Test: `App/Tests/ExportModelTests.swift`

**Interfaces:**
- Consumes: `OfflineRenderer`, `WAVWriter`, `ExportNaming`, `Track`.
- Produces:
  - `enum ExportScope: Hashable { case fullMix, part(UUID), stems }`
  - `@MainActor final class ExportModel`:
    - `init(track: Track, directory: URL /*Documents/Exports*/)`
    - `func export(scope: ExportScope, loopReady: Bool) async throws -> [URL]` (renders off the main actor; stems = one file per non-muted part)
  - `ExportSheet(track:)`: pick scope and toggle "Loop-ready (tails wrap)", which defaults on. Shows progress, then presents `ShareLink(items:)` for the files. Includes a short "In Koala: tap ＋ → Import → Files" helper line. Files also stay in Documents/Exports, visible in the Files app.

- [ ] **Step 1: Write failing tests:**
  - `fullMixWritesOneFileNamedCorrectly`.
  - `stemsOnePerUnmutedPart` (3 parts, 1 muted → 2 files).
  - `exportedFileFrameCountExact` (read the WAV data size → `frames × 4` for 2 bars at 140 BPM).
- [ ] **Step 2: Trigger `app`. Expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Trigger `app`. Expect PASS.**
- [ ] **Step 5: Commit.** `feat(app): audio export and share to Koala`

---

### Content tasks (20–23): shared rules

These apply to every content task:

- **One JSON file per lesson** in `Content/lessons/`. Add each id to its stage in `journey.json`.
- **Step order:** follow spec §5.3 (idea → listen → task → keep → optional koala). Longer lessons may repeat idea/listen pairs before the task.
- **Writing style:**
  - Plain, direct, second person, hip hop context.
  - Bodies stay short: 120 words or fewer per idea body.
  - The full theory goes in `deeper`.
- **Listen steps:** every one has at least 2 examples, and most should be A/B comparisons that isolate one idea. Examples are original compositions written in Notation. Never transcribe or imitate an identifiable existing song.
- **Default context:** A minor or another minor key, 130–160 BPM half-time trap feel, unless the lesson is about contrast.
- **Starters:** every task with `uses` has a `starter` clip so the lesson works when jumped to directly (Review Focus 1).
- **Accuracy:** before committing, self-review every theory claim against a standard reference and check that genre claims are commonly agreed. Remove anything uncertain rather than hedge. Use `ContentValidator`'s `repoContentIsValid` test as the gate (push → `core-tests` PASS).
- **Owner check:** after all four content tasks, build an IPA with `[ipa]` and have the owner run through Stage 1 on the phone before the final task.

Each content task's steps:

1. Write the lesson files.
2. Push and expect `repoContentIsValid` to PASS.
3. Self-review for accuracy and tone against the shared rules.
4. Commit.

### Task 20: Content — Stage 1 "First sounds"

| id | title | teaches | task (tool → checks) | keep |
|---|---|---|---|---|
| `first-sounds.before-you-start` | Before you touch a key | What producers decide first (vibe/reference, tempo, key) and why that order. Listen: same idea at 75 vs 150 BPM half-time; same loop in major vs minor. | trackSetup → `tempoInRange(60,180)` | `[]` (creates Your Track) |
| `first-sounds.the-grid` | Bars, beats, and the grid | 4/4, bars, beats, 16ths; half-time feel (snare on 3) vs normal (2 & 4). Listen: half-time vs double-time hats. | drumGrid → `drumHitOnBeats(kick,[1],true)`, `drumHitOnBeats(snare,[3],true)` | `[]` (practice only) |
| `first-sounds.keys-and-scales` | Keys and scales, the short version | 7 notes of a key, minor vs major mood, why trap lives in minor, scale lock as training wheels. Listen: A natural minor vs A harmonic minor vs A minor pentatonic. | melodyEditor (scale lock on) → `inKey(melody)`, `noteCount(melody,4,nil)` | `[]` |

### Task 21: Content — Stage 2 "The idea"

| id | title | teaches | task | keep |
|---|---|---|---|---|
| `the-idea.what-sticks` | What makes a melody stick | Motif, rhythm before pitch, space/rests, range. A/B: random notes vs a repeated 3-note motif. | melodyEditor → `inKey`, `noteCount(melody,3,6)` | `[]` |
| `the-idea.repeat-then-change` | Repeat, then change one thing | AAAB / ABAB phrasing, call and response, varying one dimension (pitch, rhythm, or ending). A/B: AAAA vs AAAB. | melodyEditor (starter: motif) → `inKey`, `barRhythmRepeats(melody)`, `barsDiffer(melody)` | `[]` |
| `the-idea.ending-home` | Ending on home | Tonic and 5th as resolution, tension notes, ending a loop so it wants to restart. A/B: ending on 1 vs on 2. | melodyEditor → `endsOnDegree(melody,[1,5])`, `inKey` | `[]` |
| `the-idea.fumble-to-find` | From fumbling to finding | The owner's real workflow made intentional: noodle with scale lock while the loop plays, record, keep the best 2 bars, fix in the piano roll. | melodyEditor (live record) → `inKey(melody)`, `noteCount(melody,4,nil)` | `[melody]` + koala mission |

### Task 22: Content — Stage 3 "Harmony"

| id | title | teaches | task | keep |
|---|---|---|---|---|
| `harmony.stacked-notes` | Chords are stacked notes | Triads by skipping scale notes; minor/major/diminished sound. Listen: each diatonic chord in A minor. | chordPads → `chordDegrees(chords,[1,4,5])` | `[]` |
| `harmony.chords-in-your-key` | The chords in your key | Roman numerals; common minor-key hip hop progressions (i–VI–III–VII, i–iv–VI–v, i–VI, i–iv–v) and their moods; harmonic-minor V for tension. | chordPads → `chordCount(chords,4,nil)`, `chordsInKey(chords)` | `[]` |
| `harmony.chords-from-melody` | Chords from your melody | Strong and long notes pick the chord; chord tones vs color tones vs clashes (half step above a chord tone). A/B: fitting vs clashing chord under the same melody. | chordFinder (uses melody; starter melody) → `chordsFitMelody(chords,melody,0.6)` | `[chords]` |
| `harmony.sound-expensive` | Make chords sound expensive | 7ths and 9ths, why min7/min9/maj7 dominate dark and dreamy beats, close voicing and smooth voice-leading in the middle register. A/B: triads vs 7ths, jumpy vs voice-led. | chordPads (uses melody + chords; starter) → `extendedChordCount(chords,2)`, `chordsFitMelody(chords,melody,0.6)` | `[chords]` |

### Task 23: Content — Stage 4 "Drums & groove"

| id | title | teaches | task | keep |
|---|---|---|---|---|
| `drums-groove.trap-skeleton` | The trap skeleton | Half-time: kick on 1, snare/clap on 3; 8th/16th hats; why half-time leaves room for vocals. Listen: skeleton built one lane at a time. | drumGrid → `drumHitOnBeats(kick,[1],true)`, `drumHitOnBeats(snare,[3],true)`, `laneHitCount(closedHat,8)` | `[]` |
| `drums-groove.hat-rolls` | Hi-hat rolls and movement | 1/32, 1/16T, 1/32T, 1/64 rolls; velocity ramps; pitched rolls; where rolls go (end of bar, into the snare). A/B: straight hats vs rolled. | drumGrid (starter skeleton) → `hatRollPresent`, `laneHitCount(closedHat,8)` | `[]` |
| `drums-groove.kick-bounce` | Kick placement and bounce | Syncopated kicks, keeping kicks off the snare, kick rhythm echoing the melody (sets up the 808 stage). A/B: on-beat vs syncopated kicks. | drumGrid (uses melody; starter) → `syncopatedKicks(2)`, `drumHitOnBeats(snare,[3],true)` | `[]` |
| `drums-groove.drums-meet-melody` | Drums over melody, melody over drums | Both directions; matching density; leaving gaps; 2-bar variation and fills; open hat placement; swing. | drumGrid (uses melody + chords; starter) → `drumHitOnBeats(snare,[3],true)`, `hatRollPresent`, `barsDiffer(drums)` | `[drums]` + koala mission |

---

### Task 24: Phase 1 acceptance and release

**Files:**
- Modify: `docs/BUILD.md` (add "What's in this version")

- [ ] **Step 1: Full CI.** Push, `core-tests` PASS, trigger `app` PASS.
- [ ] **Step 2: Whole-branch review** per the execution skill's final review.
- [ ] **Step 3: Tag `v0.1.0`.** Confirm the Release has `Broken.ipa` attached.
- [ ] **Step 4: Owner acceptance checklist.** Send to the owner and have them tick each item on the phone:
  - Map shows all 8 stages with "you're here".
  - Can open any lesson directly.
  - Every listen example plays.
  - Keyboard and drum pads respond instantly.
  - Sound plays with the silent switch on.
  - Switching to Koala and back keeps audio working.
  - Completing the four stages builds a track with melody + chords + drums.
  - Export (full mix, loop-ready) imports into Koala and loops without a gap or click.
- [ ] **Step 5: Commit.** `docs: phase 1 release notes`
