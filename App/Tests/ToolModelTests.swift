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
