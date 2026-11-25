import Testing
import Foundation
import MusicCore
@testable import SoundEngine

private let sr = 48_000.0

private func frames(_ seconds: Double) -> Int { Int((seconds * sr).rounded()) }

/// No reverb, so tails end exactly and silence can be measured.
private let dry = SoundSettings(volume: 0.8, reverb: 0)

private func track(tempo: Double = 120, bars: Int = 1, _ parts: [Part]) -> Track {
    Track(name: "t", createdAt: Date(timeIntervalSince1970: 0), tempo: tempo,
          key: try! Key(parsing: "A minor"), bars: bars, parts: parts)
}

private func notes(_ instrument: InstrumentID, _ events: [NoteEvent], role: PartRole = .melody,
                   sound: SoundSettings = dry) -> Part {
    Part(role: role, instrument: instrument, content: .notes(NoteSequence(notes: events)), sound: sound)
}

private struct Stereo {
    var left: [Float]
    var right: [Float]
}

/// Renders offline in 512-frame blocks, like a device callback.
private func render(_ r: Renderer, frames count: Int, block: Int = 512) -> Stereo {
    var left = [Float](repeating: 0, count: count)
    var right = [Float](repeating: 0, count: count)
    left.withUnsafeMutableBufferPointer { l in
        right.withUnsafeMutableBufferPointer { rr in
            var done = 0
            while done < count {
                let n = min(block, count - done)
                r.render(frames: n, left: l.baseAddress! + done, right: rr.baseAddress! + done)
                done += n
            }
        }
    }
    return Stereo(left: left, right: right)
}

private func peak(_ s: Stereo) -> Float { max(peak(s.left), peak(s.right)) }

@Test func onsetIsSampleAccurate() {
    let r = Renderer(sampleRate: sr)
    r.setSnapshot(PlaybackSnapshot(track: track([notes(.bell, [NoteEvent(start: 96, length: 96, pitch: 72)])])))
    r.send(.play(fromTick: 0))
    let out = render(r, frames: 30_000)
    #expect(out.left.firstIndex { abs($0) > 1e-6 } == 24_000)
    #expect(out.right.firstIndex { abs($0) > 1e-6 } == 24_000)
}

@Test func loopRetriggers() {
    let r = Renderer(sampleRate: sr)
    r.setSnapshot(PlaybackSnapshot(track: track(bars: 1, [notes(.bell, [NoteEvent(start: 0, length: 96, pitch: 72)])])))
    r.send(.play(fromTick: 0))
    let out = render(r, frames: 100_000).left
    #expect(out.firstIndex { abs($0) > 1e-6 } == 0)
    // The first note has ended (and released) long before the 1-bar loop wraps at 2 s.
    #expect(out[95_000...].firstIndex { abs($0) > 1e-6 } == 96_000)
}

@Test func noteCrossingLoopEndIsReleased() {
    let r = Renderer(sampleRate: sr)
    // 1-bar loop (2 s at 120 BPM). The pad starts at 1.5 s and would end at 3.5 s, past the loop end.
    r.setSnapshot(PlaybackSnapshot(track: track(bars: 1, [notes(.pad, [NoteEvent(start: 288, length: 384, pitch: 60)])])))
    r.send(.play(fromTick: 0))
    let before = render(r, frames: frames(2))
    #expect(peak(before) > 0.05)
    // Note-off at the wrap (2 s) + pad release 1.2 s: silent by 3.3 s, before the retrigger at 3.5 s.
    _ = render(r, frames: frames(1.3))
    #expect(r.activeVoiceCount == 0)
    #expect(peak(render(r, frames: frames(0.15))) < 1e-4)

    _ = render(r, frames: frames(0.5))  // retriggered at 3.5 s
    #expect(r.activeVoiceCount > 0)
    r.send(.stop)
    _ = render(r, frames: frames(2))
    #expect(peak(render(r, frames: 4800)) < 1e-4)
    #expect(r.activeVoiceCount == 0)
}

@Test func stopSilences() throws {
    let r = Renderer(sampleRate: sr)
    let progression = ChordProgression(slots: [
        ChordSlot(start: 0, length: 384, chord: try Chord(parsing: "Am")),
        ChordSlot(start: 384, length: 384, chord: try Chord(parsing: "F")),
    ])
    let chords = Part(role: .chords, instrument: .pad, content: .chords(progression), sound: dry)
    r.setSnapshot(PlaybackSnapshot(track: track(bars: 2, [chords])))
    r.send(.play(fromTick: 0))
    #expect(peak(render(r, frames: frames(1))) > 0.05)
    #expect(r.isPlaying)
    r.send(.stop)
    _ = render(r, frames: frames(2))
    #expect(!r.isPlaying)
    #expect(peak(render(r, frames: 4800)) < 1e-4)
    #expect(r.activeVoiceCount == 0)
}

@Test func snapshotSwapReleasesChangedPart() {
    let r = Renderer(sampleRate: sr)
    r.setSnapshot(PlaybackSnapshot(track: track(bars: 2, [notes(.pad, [NoteEvent(start: 0, length: 768, pitch: 60)])])))
    r.send(.play(fromTick: 0))
    #expect(peak(render(r, frames: frames(1))) > 0.05)
    // New melody: its only note starts at 3.5 s.
    r.setSnapshot(PlaybackSnapshot(track: track(bars: 2, [notes(.pad, [NoteEvent(start: 672, length: 96, pitch: 72)])])))
    _ = render(r, frames: frames(1.4))  // pad release is 1.2 s
    #expect(r.activeVoiceCount == 0)
    #expect(peak(render(r, frames: 4800)) < 1e-4)
    #expect(r.isPlaying)
}

@Test func snapshotSwapKeepsUnchangedPart() {
    let r = Renderer(sampleRate: sr)
    let melody = notes(.pad, [NoteEvent(start: 0, length: 768, pitch: 72)])
    var bass = notes(.pad, [NoteEvent(start: 0, length: 768, pitch: 48)], role: .bass808)
    r.setSnapshot(PlaybackSnapshot(track: track(bars: 2, [melody, bass])))
    r.send(.play(fromTick: 0))
    _ = render(r, frames: frames(1))
    #expect(r.activeVoiceCount == 2)
    // Only a sound setting changes: no part's events change, so nothing is released.
    bass.sound.volume = 0.5
    r.setSnapshot(PlaybackSnapshot(track: track(bars: 2, [melody, bass])))
    _ = render(r, frames: frames(1.4))
    #expect(r.activeVoiceCount == 2)
}

@Test func liveNoteOnPlaysWhileStopped() {
    let r = Renderer(sampleRate: sr)
    r.send(.noteOn(.keys, 60, 0.8))
    #expect(peak(render(r, frames: 512)) > 0.05)
    #expect(!r.isPlaying)
    r.send(.noteOff(.keys, 60))
    _ = render(r, frames: frames(1))
    #expect(r.activeVoiceCount == 0)
}

@Test func outputBounded() {
    let loud = SoundSettings(volume: 1, drive: 1, cutoff: 1, reverb: 1, delay: 1)
    let roles: [PartRole] = [.melody, .chords, .bass808, .counter, .texture, .melody, .chords, .counter]
    let instruments: [InstrumentID] = [.bell, .pad, .eight08, .pluck, .keys, .bell, .pad, .keys]
    var parts: [Part] = []
    for i in 0..<7 {
        var events: [NoteEvent] = []
        for step in 0..<16 {
            for k in 0..<3 {
                events.append(NoteEvent(start: step * 24, length: 48, pitch: 40 + i * 5 + k * 4, velocity: 1))
            }
        }
        parts.append(notes(instruments[i], events, role: roles[i], sound: loud))
    }
    var lanes: [DrumLane: [DrumHit]] = [:]
    for lane in DrumLane.allCases {
        lanes[lane] = (0..<16).map { DrumHit(tick: $0 * 24, velocity: 1) }
    }
    parts.append(Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: lanes)), sound: loud))
    #expect(parts.count == 8)

    let r = Renderer(sampleRate: sr)
    r.setSnapshot(PlaybackSnapshot(track: track(bars: 1, parts)))
    r.send(.play(fromTick: 0))
    let out = render(r, frames: frames(2.5))
    #expect(peak(out) <= 1)
    #expect(peak(out) > 0.5)
    #expect(allFinite(out.left) && allFinite(out.right))
}

@Test func backToBackGlideNotesGlide() {
    let r = Renderer(sampleRate: sr)
    let bass = notes(.eight08, [
        NoteEvent(start: 0, length: 96, pitch: 33),
        NoteEvent(start: 96, length: 96, pitch: 45, glide: true),  // starts exactly where the first ends
    ], role: .bass808)
    r.setSnapshot(PlaybackSnapshot(track: track(bars: 1, [bass])))
    r.send(.play(fromTick: 0))
    let first = render(r, frames: frames(0.5))
    let f1 = estimatedFrequency(Array(first.left[frames(0.1)...]), sampleRate: sr)
    #expect(abs(f1 - 55) / 55 < 0.03)
    _ = render(r, frames: frames(0.1))  // 0.5-0.6 s: the 60 ms glide
    #expect(r.activeVoiceCount == 1)
    let second = render(r, frames: frames(0.3))  // 0.6-0.9 s
    let f2 = estimatedFrequency(second.left, sampleRate: sr)
    #expect(abs(f2 - 110) / 110 < 0.03)
    #expect(r.activeVoiceCount == 1)
}

@Test func snapshotMapsTrack() throws {
    let melody = notes(.bell, [NoteEvent(start: 96, length: 0, pitch: 72), NoteEvent(start: 0, length: 48, pitch: 69)])
    let drums = Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: [
        .snare: [DrumHit(tick: 96, velocity: 0.9)], .kick: [DrumHit(tick: 0, velocity: 1)],
    ])))
    let chords = Part(role: .chords, instrument: .pad, content: .chords(ChordProgression(slots: [
        ChordSlot(start: 0, length: 384, chord: try Chord(parsing: "Am")),
    ])))
    let s = PlaybackSnapshot(track: track(tempo: 140, bars: 0, [melody, drums, chords]))
    #expect(s.tempo == 140)
    #expect(s.loopTicks == 384)
    #expect(s.parts.count == 3)
    #expect(s.parts[0].events.map(\.start) == [0, 96])
    #expect(s.parts[0].events[1].end == 97)  // zero-length notes still get a note-off after the note-on
    #expect(s.parts[1].events == [
        ScheduledNote(start: 0, end: 1, pitch: DrumLane.kick.midiNote, velocity: 1, glide: false),
        ScheduledNote(start: 96, end: 97, pitch: DrumLane.snare.midiNote, velocity: 0.9, glide: false),
    ])
    #expect(s.parts[2].events.count == 3)
    #expect(s.parts[2].events.allSatisfy { $0.velocity == 0.7 && $0.end == 384 })

    let many = PlaybackSnapshot(track: track(bars: 4, Array(repeating: melody, count: 10)))
    #expect(many.parts.count == 8)
    #expect(many.loopTicks == 1536)
}

@Test func commandQueueIsFIFOAndBounded() {
    let q = CommandQueue()
    #expect(q.pop() == nil)
    for i in 0..<256 { #expect(q.push(.play(fromTick: i))) }
    #expect(!q.push(.stop))
    for i in 0..<256 {
        guard case .play(let t)? = q.pop() else { Issue.record("expected play"); return }
        #expect(t == i)
    }
    #expect(q.pop() == nil)
    #expect(q.push(.stop))
}

@Test func largeBlocksRenderInChunks() {
    let r = Renderer(sampleRate: sr)
    r.setSnapshot(PlaybackSnapshot(track: track([notes(.bell, [NoteEvent(start: 96, length: 96, pitch: 72)])])))
    r.send(.play(fromTick: 0))
    let out = render(r, frames: 30_000, block: 10_000)
    #expect(out.left.firstIndex { abs($0) > 1e-6 } == 24_000)
    #expect(r.playheadTick > 96 && r.playheadTick < 384)
}
