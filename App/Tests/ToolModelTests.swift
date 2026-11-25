import Testing
import Foundation
import MusicCore
@testable import Broken

// MARK: - Melody editor

private func rollModel(_ notes: [NoteEvent] = []) -> PianoRollModel {
    PianoRollModel(sequence: NoteSequence(notes: notes), bars: 2,
                   key: Key(tonic: PitchClass(9), mode: .minor), lowestPitch: 57)
}

@MainActor
struct MelodyModelTests {
    @Test func toggleAddsAndRemoves() {
        let model = rollModel()
        model.toggle(step: 4, pitch: 60)
        #expect(model.sequence.notes == [NoteEvent(start: 96, length: 24, pitch: 60, velocity: 0.8)])
        model.toggle(step: 4, pitch: 60)
        #expect(model.sequence.notes.isEmpty)
    }

    @Test func toggleOnCoveredCellRemovesTheNote() {
        let model = rollModel([NoteEvent(start: 0, length: 96, pitch: 60)])
        model.toggle(step: 2, pitch: 60)
        #expect(model.sequence.notes.isEmpty)
    }

    @Test func sequenceStaysSorted() {
        let model = rollModel()
        model.toggle(step: 8, pitch: 60)
        model.toggle(step: 2, pitch: 62)
        #expect(model.sequence.notes.map(\.start) == [48, 192])
    }

    @Test func resizeChangesLength() {
        let model = rollModel([NoteEvent(start: 24, length: 24, pitch: 60)])
        model.resize(noteAt: 1, pitch: 60, toSteps: 4)
        #expect(model.sequence.notes[0].length == 96)
        model.resize(noteAt: 1, pitch: 60, toSteps: 0)
        #expect(model.sequence.notes[0].length == 24)
        model.resize(noteAt: 1, pitch: 60, toSteps: 100)  // clipped to the loop end (2 bars = 768 ticks)
        #expect(model.sequence.notes[0].length == 768 - 24)
    }

    @Test func glideToggles() {
        let model = rollModel([NoteEvent(start: 0, length: 24, pitch: 60)])
        model.toggleGlide(step: 0, pitch: 60)
        #expect(model.sequence.notes[0].glide)
        model.toggleGlide(step: 0, pitch: 60)
        #expect(!model.sequence.notes[0].glide)
    }

    @Test func recorderQuantizes() {
        var recorder = LiveRecorder()
        recorder.noteOn(pitch: 60, atTick: 30)
        recorder.noteOff(pitch: 60, atTick: 70)
        let notes = recorder.result(loopTicks: 768).notes
        #expect(notes.count == 1)
        #expect(notes[0].start == 24)
        #expect(notes[0].length == 48)
        #expect(notes[0].pitch == 60)
    }

    @Test func recorderMinimumLengthIsOneStep() {
        var recorder = LiveRecorder()
        recorder.noteOn(pitch: 60, atTick: 100)
        recorder.noteOff(pitch: 60, atTick: 103)
        #expect(recorder.result(loopTicks: 768).notes[0].length == 24)
    }

    @Test func recorderWrapsAtLoopEnd() {
        var recorder = LiveRecorder()
        recorder.noteOn(pitch: 64, atTick: 700)
        recorder.noteOff(pitch: 64, atTick: 900)
        let note = recorder.result(loopTicks: 768).notes[0]
        #expect(note.start + note.length == 768)
    }

    @Test func recorderEndsHeldNotesAtLoopEnd() {
        var recorder = LiveRecorder()
        recorder.noteOn(pitch: 64, atTick: 384)
        let note = recorder.result(loopTicks: 768).notes[0]
        #expect(note.start == 384)
        #expect(note.length == 384)
    }
}

// MARK: - Transport

struct MetronomeTests {
    private func track() -> Track {
        Track(name: "t", createdAt: Date(), tempo: 120, key: Key(tonic: PitchClass(9), mode: .minor), bars: 2,
              parts: [Part(role: .melody, instrument: .bell, content: .notes(NoteSequence(notes: [])))])
    }

    @Test func addsRimOnEveryBeatWithoutTouchingTheOriginal() {
        let original = track()
        let result = withMetronome(original)
        #expect(original.parts.count == 1)
        #expect(result.parts.count == 2)
        guard let part = result.parts.last, case .drums(let pattern) = part.content else {
            Issue.record("expected a drum part"); return
        }
        #expect(part.instrument == .trapKit)
        #expect(pattern.lanes[.rim]?.map(\.tick) == Array(stride(from: 0, to: 768, by: 96)))
    }

    @Test func keepsTheTrackDrumsAndAddsTheClickAlongside() {
        var base = track()
        base.setPart(Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: [.kick: [DrumHit(tick: 0, velocity: 1)]]))))
        let result = withMetronome(base)
        #expect(result.parts.count == base.parts.count + 1)
        #expect(result.part(.drums) == base.part(.drums))
    }
}

// MARK: - Keyboard press tracking

struct KeyPressTrackerTests {
    @Test func pressReportsOnlyTheFirstTouch() {
        var tracker = KeyPressTracker()
        let first = tracker.press(60)
        let second = tracker.press(60)
        #expect(first)
        #expect(!second)
    }

    @Test func releaseOfAnUnheldPitchIsIgnored() {
        var tracker = KeyPressTracker()
        let early = tracker.release(60)
        _ = tracker.press(60)
        let real = tracker.release(60)
        let again = tracker.release(60)
        #expect(!early)
        #expect(real)
        #expect(!again)
    }

    @Test func octaveChangeReleasesEveryHeldPitchOnce() {
        var tracker = KeyPressTracker()
        _ = tracker.press(64)
        _ = tracker.press(60)
        let released = tracker.releaseAll()
        let secondRelease = tracker.releaseAll()
        // The late lift of the old finger must not send a second note-off, and new keys work.
        let lateLift = tracker.release(60)
        let newPress = tracker.press(72)
        #expect(released == [60, 64])
        #expect(secondRelease.isEmpty)
        #expect(!lateLift)
        #expect(newPress)
    }
}

// MARK: - Drum grid

@MainActor
struct DrumGridModelTests {
    private func model() -> DrumGridModel { DrumGridModel(pattern: DrumPattern(lanes: [:]), bars: 2) }

    @Test func gridToggle() {
        let m = model()
        m.toggle(lane: .kick, step: 4)
        #expect(m.pattern.lanes[.kick]?.map(\.tick) == [96])
        m.selectedBar = 1
        m.toggle(lane: .kick, step: 4)  // bar 2, step 4 = tick 384 + 96
        #expect(m.pattern.lanes[.kick]?.map(\.tick) == [96, 480])
        m.toggle(lane: .kick, step: 4)
        m.selectedBar = 0
        m.toggle(lane: .kick, step: 4)
        #expect(m.pattern.lanes[.kick]?.isEmpty == true)
    }

    @Test func velocityTargetsTheHitOnTheStep() {
        let m = model()
        m.toggle(lane: .snare, step: 2)
        m.setVelocity(lane: .snare, step: 2, 0.4)
        #expect(m.pattern.lanes[.snare]?.first?.velocity == 0.4)
        m.setVelocity(lane: .snare, step: 3, 0.1)  // no hit there: no-op
        #expect(m.pattern.lanes[.snare]?.count == 1)
    }

    @Test func rollCreatesSubdividedHits() {
        let m = model()
        m.roll(lane: .closedHat, fromStep: 0, toStep: 1, rate: .thirtySecond, ramp: 0.35...1.0)
        let hits = m.pattern.lanes[.closedHat] ?? []
        #expect(hits.map(\.tick) == [0, 12, 24, 36])
        #expect(hits.first?.velocity == 0.35)
        #expect(hits.last?.velocity == 1.0)
    }

    @Test func descendingRollRampsDown() {
        let m = model()
        m.roll(lane: .closedHat, fromStep: 0, toStep: 1, rate: .thirtySecond, ramp: 0.35...1.0, descending: true)
        let hits = m.pattern.lanes[.closedHat] ?? []
        #expect(hits.first?.velocity == 1.0)
        #expect(hits.last?.velocity == 0.35)
    }

    @Test func everyRampCanRoll() {
        for ramp in RollRamp.allCases {
            let m = model()
            m.roll(lane: .closedHat, fromStep: 0, toStep: 3, rate: .sixtyFourth, ramp: ramp.velocities,
                   descending: ramp.descending)
            #expect(!(m.pattern.lanes[.closedHat] ?? []).isEmpty)
        }
        #expect(RollRamp.down.descending && !RollRamp.up.descending && !RollRamp.flat.descending)
    }

    @Test func clearRollsEmptiesTheStep() {
        let m = model()
        m.roll(lane: .closedHat, fromStep: 0, toStep: 1, rate: .thirtySecond, ramp: 0.75...0.75)
        m.clearRolls(lane: .closedHat, step: 0)
        #expect(m.pattern.lanes[.closedHat]?.map(\.tick) == [24, 36])
    }

    @Test func copyBar() {
        let m = model()
        m.toggle(lane: .kick, step: 0)
        m.toggle(lane: .snare, step: 4)
        m.selectedBar = 1
        m.toggle(lane: .closedHat, step: 3)  // replaced by the copy
        m.copyBar(0, to: 1)
        #expect(m.pattern.lanes[.kick]?.map(\.tick) == [0, 384])
        #expect(m.pattern.lanes[.snare]?.map(\.tick) == [96, 480])
        #expect(m.pattern.lanes[.closedHat]?.isEmpty ?? true)
    }

    @Test func swingIsClamped() {
        let m = model()
        m.swing = 0.9
        #expect(m.swing == 0.6)
        m.swing = -1
        #expect(m.swing == 0)
        m.swing = 0.3
        #expect(m.pattern.swing == 0.3)
    }

    @Test func editsNotifyTheOwner() {
        let m = model()
        var seen: [DrumPattern] = []
        m.onChange = { seen.append($0) }
        m.toggle(lane: .kick, step: 0)
        m.swing = 0.2
        #expect(seen.count == 2)
        #expect(seen.last?.swing == 0.2)
    }
}

// MARK: - Chords

private let chordsKey = Key(tonic: PitchClass(9), mode: .minor)

/// Bar 1 outlines A minor (A C E); bar 2 outlines F major (F A C).
private let chordsMelody = NoteSequence(notes: [
    NoteEvent(start: 0, length: 96, pitch: 69), NoteEvent(start: 96, length: 96, pitch: 72),
    NoteEvent(start: 192, length: 96, pitch: 76), NoteEvent(start: 288, length: 96, pitch: 72),
    NoteEvent(start: 384, length: 96, pitch: 77), NoteEvent(start: 480, length: 96, pitch: 69),
    NoteEvent(start: 576, length: 96, pitch: 72), NoteEvent(start: 672, length: 96, pitch: 77),
])

@MainActor
struct ChordFinderModelTests {
    private func model() -> ChordFinderModel { ChordFinderModel(melody: chordsMelody, bars: 2, key: chordsKey) }

    @Test func finderTopFitsLimitedToFive() {
        let m = model()
        #expect(m.fitsPerBar.count == 2)
        #expect(m.fitsPerBar.allSatisfy { $0.count == 5 })
        #expect(m.fitsPerBar[0][0].chord == Chord(root: PitchClass(9), quality: .minor))
    }

    @Test func chooseWritesSlotForBar() {
        let m = model()
        let fit = m.fitsPerBar[1][0]
        m.choose(bar: 1, fit: fit)
        #expect(m.progression.slots == [ChordSlot(start: 384, length: 384, chord: fit.chord)])
    }

    @Test func chooseReplacesOverlappingSlotAndMovesFocus() {
        let m = model()
        m.progression = ChordProgression(slots: [
            ChordSlot(start: 0, length: 192, chord: Chord(root: PitchClass(0), quality: .major)),
            ChordSlot(start: 192, length: 192, chord: Chord(root: PitchClass(2), quality: .minor)),
        ])
        let fit = m.fitsPerBar[0][0]
        m.choose(bar: 0, fit: fit)
        #expect(m.progression.slots == [ChordSlot(start: 0, length: 384, chord: fit.chord)])
        #expect(m.focusedBar == 1)
        m.choose(bar: 1, fit: m.fitsPerBar[1][0])
        #expect(m.focusedBar == 1)
        #expect(m.progression.slots.count == 2)
    }

    @Test func auditionTrackHasMelodyAndChord() {
        let m = model()
        let fit = m.fitsPerBar[1][0]
        let track = m.audition(bar: 1, fit: fit)
        #expect(track.bars == 2)
        #expect(track.part(.melody)?.instrument == .bell)
        #expect(track.part(.melody)?.content == .notes(chordsMelody))
        #expect(track.part(.chords)?.instrument == .pad)
        #expect(track.part(.chords)?.content
            == .chords(ChordProgression(slots: [ChordSlot(start: 384, length: 384, chord: fit.chord)])))
    }

    @Test func placingKeepsTheEdgesOfALongSlot() {
        let c = Chord(root: PitchClass(0), quality: .major)
        let d = Chord(root: PitchClass(2), quality: .minor)
        let p = ChordProgression(slots: [ChordSlot(start: 0, length: 768, chord: c)]).placing(d, start: 192, length: 192)
        #expect(p.slots == [ChordSlot(start: 0, length: 192, chord: c), ChordSlot(start: 192, length: 192, chord: d),
                            ChordSlot(start: 384, length: 384, chord: c)])
    }

    @Test func relativeScoreIsBestRelative() {
        #expect(ChordFinderRules.relativeScore(4, best: 4) == 100)
        #expect(ChordFinderRules.relativeScore(2, best: 4) == 50)
        #expect(ChordFinderRules.relativeScore(-1, best: 4) == 0)
        #expect(ChordFinderRules.relativeScore(1, best: 0) == 0)
        #expect(ChordFinderRules.band(forRelative: 70) == .tone)
        #expect(ChordFinderRules.band(forRelative: 69) == .color)
        #expect(ChordFinderRules.band(forRelative: 40) == .color)
        #expect(ChordFinderRules.band(forRelative: 39) == .clash)
    }

    @Test func chipRolesAndIntervalLabels() {
        let am = Chord(root: PitchClass(9), quality: .minor)  // A C E
        #expect(ChordFinderRules.chipRole(pitch: 69, chord: am) == .chordTone)
        #expect(ChordFinderRules.chipRole(pitch: 77, chord: am) == .clash)      // F is a half step above E
        #expect(ChordFinderRules.chipRole(pitch: 74, chord: am) == .colorTone)  // D
        #expect(ChordFinderRules.intervalLabel(pitch: 69, chord: am) == "R")
        #expect(ChordFinderRules.intervalLabel(pitch: 72, chord: am) == "♭3")
        #expect(ChordFinderRules.intervalLabel(pitch: 76, chord: am) == "5")
        #expect(ChordFinderRules.intervalLabel(pitch: 74, chord: am) == "11")
        #expect(ChordFinderRules.intervalLabel(pitch: 67, chord: am) == "♭7")
    }

    @Test func reasonNamesChordTonesAndClashes() {
        let fit = ChordFit(chord: Chord(root: PitchClass(9), quality: .minor), roman: "i", score: 1,
                           matched: [PitchClass(9), PitchClass(4)], clashes: [PitchClass(5)])
        #expect(ChordFinderRules.reason(for: fit, key: chordsKey)
            == "A and E are chord tones; F rubs a half step above E")
    }
}

struct ChordPadTests {
    @Test func padsCoverTheScalePlusBorrowedDominant() {
        let pads = ChordPad.pads(key: chordsKey)
        #expect(pads.count == 8)
        #expect(pads[7].borrowed && pads[7].triad.quality == .major)
    }

    @Test func variantsMapToQualities() {
        let pads = ChordPad.pads(key: chordsKey)  // A minor: i, ii°, III, iv, v, VI, VII, V
        #expect(pads[0].chord(.seventh).quality == .minor7)
        #expect(pads[0].chord(.ninth).quality == .minor9)
        #expect(pads[2].chord(.ninth).quality == .major9)      // III: Cmaj7 -> Cmaj9
        #expect(pads[6].chord(.ninth).quality == .dominant7)   // VII: G7 stays a seventh
        #expect(pads[1].chord(.ninth).quality == .halfDiminished7)
        #expect(pads[3].chord(.sus2) == Chord(root: PitchClass(2), quality: .sus2))
        #expect(pads[3].chord(.sus4).root == pads[3].triad.root)
        #expect(pads[7].chord(.seventh).quality == .dominant7)
    }
}

struct PadTouchStateTests {
    private let voicing = [57, 60, 64]

    @Test func tapSoundsOnceAndReleasesTheSameNotes() {
        var s = PadTouchState()
        #expect(s.press(0, voicing: voicing) == voicing)
        #expect(s.press(0, voicing: voicing) == nil)  // repeated drag events
        let end = s.finish(0, completed: true)
        #expect(end.release == voicing && end.place)
        let reset = s.finish(0, completed: false)  // the gesture reset arrives too
        #expect(reset.release.isEmpty && !reset.place)
    }

    @Test func tapAfterLongPressSounds() {
        var s = PadTouchState()
        _ = s.press(0, voicing: voicing)
        #expect(s.longPress(0) == voicing)                  // hold stops the sound
        #expect(s.press(0, voicing: voicing) == nil)        // finger jitter does not re-sound it
        let cancel = s.finish(0, completed: false)           // the dialog cancels the touch
        #expect(cancel.release.isEmpty && !cancel.place)
        #expect(s.press(0, voicing: voicing) == voicing)    // the next tap is heard
        #expect(s.finish(0, completed: true).place)
    }

    @Test func holdThenLiftDoesNotPlace() {
        var s = PadTouchState()
        _ = s.press(0, voicing: voicing)
        _ = s.longPress(0)
        #expect(!s.finish(0, completed: true).place)
        #expect(s.finish(0, completed: false).release.isEmpty)
    }

    @Test func gestureResetBeforeLiftStillPlaces() {
        var s = PadTouchState()
        _ = s.press(0, voicing: voicing)
        #expect(s.finish(0, completed: false).release == voicing)
        #expect(s.finish(0, completed: true).place)
    }

    @Test func qualityChangeMidPressReleasesTheOriginalVoicing() {
        var s = PadTouchState()
        _ = s.press(0, voicing: voicing)
        // The pad's chord changes to a 7th while held; a later finish still releases what was pressed.
        #expect(s.finish(0, completed: true).release == voicing)
    }

    @Test func releaseAllHandsBackEverythingSounding() {
        var s = PadTouchState()
        _ = s.press(0, voicing: [57, 60])
        _ = s.press(1, voicing: [59])
        #expect(s.releaseAll() == [57, 59, 60])
        #expect(s.releaseAll().isEmpty)
        #expect(s.press(0, voicing: [57]) == [57])
    }
}

@MainActor
struct ChordFinderFixTests {
    private func model() -> ChordFinderModel { ChordFinderModel(melody: chordsMelody, bars: 2, key: chordsKey) }

    @Test func placingAChordClearsTheBarSelection() {
        let m = model()
        m.select(bar: 0, fit: m.fitsPerBar[0][1])
        m.select(bar: 1, fit: m.fitsPerBar[1][1])
        #expect(m.chord(forBar: 0) == m.fitsPerBar[0][1].chord)
        // A pad places a chord into bar 0.
        m.progression = m.progression.placing(Chord(root: PitchClass(0), quality: .major), start: 0, length: 384)
        #expect(m.selection[0] == nil)
        #expect(m.selection[1] != nil)
        #expect(m.chord(forBar: 0) == Chord(root: PitchClass(0), quality: .major))
    }

    @Test func chooseClearsTheSelection() {
        let m = model()
        let fit = m.fitsPerBar[0][1]
        m.select(bar: 0, fit: fit)
        m.choose(bar: 0, fit: fit)
        #expect(m.selection[0] == nil)
        #expect(m.chord(forBar: 0) == fit.chord)
    }

    @Test func updateMelodyRerankssAndKeepsProgression() {
        let m = model()
        m.choose(bar: 0, fit: m.fitsPerBar[0][0])
        let kept = m.progression
        // Bar 1 now outlines G major (G B D).
        let g = NoteSequence(notes: [NoteEvent(start: 0, length: 96, pitch: 67), NoteEvent(start: 96, length: 96, pitch: 71),
                                     NoteEvent(start: 192, length: 96, pitch: 74)])
        m.select(bar: 1, fit: m.fitsPerBar[1][0])
        m.update(melody: g)
        #expect(m.melody == g)
        #expect(m.fitsPerBar[0][0].chord == Chord(root: PitchClass(7), quality: .major))
        #expect(m.fitsPerBar.allSatisfy { $0.count == 5 })
        #expect(m.selection.isEmpty)
        #expect(m.progression == kept)
    }

    @Test func barShowsBothChordsOfTwoPerBar() {
        let a = Chord(root: PitchClass(9), quality: .minor)
        let f = Chord(root: PitchClass(5), quality: .major)
        let p = ChordProgression(slots: [ChordSlot(start: 0, length: 192, chord: a), ChordSlot(start: 192, length: 192, chord: f),
                                         ChordSlot(start: 384, length: 384, chord: a)])
        #expect(p.chords(inBar: 0) == [a, f])
        #expect(p.chords(inBar: 1) == [a])
        #expect(ChordProgression(slots: []).chords(inBar: 0).isEmpty)
    }
}

// MARK: - Live recording latency

struct LatencyCompensationTests {
    @Test func secondsBecomeTicksAtTheTempo() {
        // 25 ms at 150 BPM: 0.025 s x 2.5 beats/s x 96 ticks/beat = 6 ticks.
        #expect(LatencyCompensation.ticks(seconds: 0.025, tempo: 150) == 6)
        #expect(LatencyCompensation.ticks(seconds: 0.0125, tempo: 120) == 2)  // 2.4 rounds down
        #expect(LatencyCompensation.ticks(seconds: 0, tempo: 140) == 0)
        #expect(LatencyCompensation.ticks(seconds: -1, tempo: 140) == 0, "never negative")
        #expect(LatencyCompensation.ticks(seconds: .nan, tempo: 140) == 0)
    }

    @Test func heardTickWrapsWithinTheLoop() {
        #expect(LatencyCompensation.heardTick(playhead: 100, latency: 16, loopTicks: 768) == 84)
        #expect(LatencyCompensation.heardTick(playhead: 4, latency: 6, loopTicks: 768) == 766, "wraps to the loop end")
        #expect(LatencyCompensation.heardTick(playhead: 10, latency: 0, loopTicks: 768) == 10)
        #expect(LatencyCompensation.heardTick(playhead: 10, latency: 2000, loopTicks: 768) == (10 - 2000 % 768 + 768) % 768)
        #expect(LatencyCompensation.heardTick(playhead: 10, latency: 5, loopTicks: 0) == 10, "no loop: unchanged")
    }

    @MainActor
    @Test func playerReportsLatencyAtTheTrackTempo() {
        let player = AudioPlayer(latencySeconds: { 0.025 })
        #expect(player.latencyTicks == 0, "no track yet")
        player.setTrack(Track(name: "t", createdAt: Date(), tempo: 150, key: Key(tonic: PitchClass(9), mode: .minor),
                              bars: 2, parts: []))
        #expect(player.latencyTicks == 6)
    }
}

// MARK: - Part names

struct PartRoleNameTests {
    @Test func displayNames() {
        #expect(PartRole.allCases.map(\.displayName) == ["Melody", "Chords", "Drums", "808", "Counter", "Texture"])
    }
}
