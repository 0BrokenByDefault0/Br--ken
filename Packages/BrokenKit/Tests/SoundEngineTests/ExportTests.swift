import Testing
import Foundation
import MusicCore
@testable import SoundEngine

private func exportTrack(name: String = "t", tempo: Double = 140, bars: Int = 4, _ parts: [Part]) -> Track {
    Track(name: name, createdAt: Date(timeIntervalSince1970: 0), tempo: tempo,
          key: try! Key(parsing: "A minor"), bars: bars, parts: parts)
}

private func melodyPart(muted: Bool = false) -> Part {
    Part(role: .melody, instrument: .bell,
         content: .notes(NoteSequence(notes: [NoteEvent(start: 0, length: 96, pitch: 72, velocity: 1),
                                              NoteEvent(start: 192, length: 96, pitch: 76, velocity: 1)])),
         sound: SoundSettings(volume: 0.8, reverb: 0), muted: muted)
}

private func drumsPart() -> Part {
    var lanes: [DrumLane: [DrumHit]] = [:]
    lanes[.kick] = (0..<8).map { DrumHit(tick: $0 * 48, velocity: 1) }
    lanes[.snare] = [DrumHit(tick: 96, velocity: 1), DrumHit(tick: 288, velocity: 1)]
    return Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: lanes)),
                sound: SoundSettings(volume: 0.8, reverb: 0))
}

/// Manual reference: fresh renderer, play from 0, render `count` frames in 1024-frame blocks.
private func manualRender(_ t: Track, frames count: Int) -> StereoBuffer {
    let r = Renderer(sampleRate: 48_000)
    r.setSnapshot(PlaybackSnapshot(track: t))
    _ = r.send(.play(fromTick: 0))
    var l = [Float](repeating: 0, count: count)
    var rr = [Float](repeating: 0, count: count)
    l.withUnsafeMutableBufferPointer { lp in
        rr.withUnsafeMutableBufferPointer { rp in
            var done = 0
            while done < count {
                let n = min(1024, count - done)
                r.render(frames: n, left: lp.baseAddress! + done, right: rp.baseAddress! + done)
                done += n
            }
        }
    }
    return StereoBuffer(left: l, right: rr, frameCount: count)
}

@Test func exactLength() {
    let n = OfflineRenderer.frameCount(bars: 4, tempo: 140, sampleRate: 48_000)
    #expect(n == 329_143)
    let b = OfflineRenderer.render(track: exportTrack([melodyPart()]), loopReady: false)
    #expect(b.frameCount == 329_143)
    #expect(b.left.count == 329_143)
    #expect(b.right.count == 329_143)
}

@Test func loopReadyEqualsSecondPass() {
    let t = exportTrack(tempo: 140, bars: 1, [melodyPart(), drumsPart()])
    let n = OfflineRenderer.frameCount(bars: 1, tempo: 140, sampleRate: 48_000)
    let two = manualRender(t, frames: 2 * n)
    let b = OfflineRenderer.render(track: t, loopReady: true)
    #expect(b.frameCount == n)
    #expect(b.left == Array(two.left[n...]))
    #expect(b.right == Array(two.right[n...]))
}

@Test func wavHeader() throws {
    let frames = 1000
    let l = (0..<frames).map { Float(sin(Double($0) * 0.05)) * 0.9 }
    let r = (0..<frames).map { Float(cos(Double($0) * 0.03)) * 0.5 }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wavHeader-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try WAVWriter.write(StereoBuffer(left: l, right: r, frameCount: frames), sampleRate: 48_000, to: url)
    let d = try Data(contentsOf: url)
    func u32(_ o: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(d[o + $1]) << (8 * UInt32($1)) } }
    func u16(_ o: Int) -> UInt16 { UInt16(d[o]) | UInt16(d[o + 1]) << 8 }
    func tag(_ o: Int) -> String { String(decoding: d[o..<o + 4], as: UTF8.self) }
    #expect(d.count == 44 + frames * 4)
    #expect(tag(0) == "RIFF")
    #expect(u32(4) == UInt32(36 + frames * 4))
    #expect(tag(8) == "WAVE")
    #expect(tag(12) == "fmt ")
    #expect(u32(16) == 16)
    #expect(u16(20) == 1)
    #expect(u16(22) == 2)
    #expect(u32(24) == 48_000)
    #expect(u32(28) == 48_000 * 4)
    #expect(u16(32) == 4)
    #expect(u16(34) == 16)
    #expect(tag(36) == "data")
    #expect(u32(40) == UInt32(frames * 4))
    for i in [0, 1, 17, 500, 999] {
        let sl = Float(Int16(bitPattern: u16(44 + i * 4))) / 32767
        let sr = Float(Int16(bitPattern: u16(46 + i * 4))) / 32767
        #expect(abs(sl - l[i]) <= 1.0 / 32768)
        #expect(abs(sr - r[i]) <= 1.0 / 32768)
    }
}

@Test func soloPartRendersOnlyThatPart() {
    // Melody plays only in bar 1, drums only in bar 2 (dry). Solo drums must be silent in bar 1.
    let dryS = SoundSettings(volume: 0.8, reverb: 0, delay: 0)
    let melody = Part(role: .melody, instrument: .bell,
                      content: .notes(NoteSequence(notes: [NoteEvent(start: 0, length: 48, pitch: 72, velocity: 1)])),
                      sound: dryS)
    let drums = Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: [
        .kick: [DrumHit(tick: 384, velocity: 1), DrumHit(tick: 480, velocity: 1)],
        .snare: [DrumHit(tick: 432, velocity: 1)],
    ])), sound: dryS)
    let full = exportTrack(tempo: 120, bars: 2, [melody, drums])
    let bar1 = OfflineRenderer.frameCount(bars: 1, tempo: 120, sampleRate: 48_000)
    let solo = OfflineRenderer.render(track: full, onlyPart: drums.id, loopReady: false)
    let mix = OfflineRenderer.render(track: full, loopReady: false)
    func peak(_ a: [Float], _ r: Range<Int>) -> Float { a[r].map { abs($0) }.max() ?? 0 }
    #expect(peak(solo.left, 0..<bar1) < 1e-6)
    #expect(peak(solo.right, 0..<bar1) < 1e-6)
    #expect(peak(mix.left, 0..<bar1) > 1e-3)
    #expect(peak(solo.left, bar1..<solo.frameCount) > 1e-3)
    // Same index kept: solo equals the track with the melody swapped for a muted placeholder.
    let ref = OfflineRenderer.render(track: exportTrack(tempo: 120, bars: 2, [melodyPart(muted: true), drums]),
                                     loopReady: false)
    #expect(solo.left == ref.left)
}

@Test func tempoIsClamped() {
    let sr = 48_000.0
    let lo = Int((4.0 * 60 / 20 * sr).rounded())
    let hi = Int((4.0 * 60 / 999 * sr).rounded())
    for t in [0.0, -5, .nan, .infinity, 10] {
        #expect(OfflineRenderer.frameCount(bars: 1, tempo: t, sampleRate: sr) == lo)
        let b = OfflineRenderer.render(track: exportTrack(tempo: t, bars: 1, []), loopReady: false)
        #expect(b.frameCount == lo)
        #expect(b.left.count == lo)
    }
    #expect(OfflineRenderer.frameCount(bars: 1, tempo: 5000, sampleRate: sr) == hi)
    #expect(OfflineRenderer.render(track: exportTrack(tempo: 5000, bars: 1, []), loopReady: false).frameCount == hi)
    #expect(Renderer.tempoRange == 20...999)
}

@Test func loopReadyWrapsTail() {
    // A pad held to the loop end: the second pass starts with the wrapped tail, the first does not.
    let pad = Part(role: .chords, instrument: .pad,
                   content: .notes(NoteSequence(notes: [NoteEvent(start: 192, length: 192, pitch: 60, velocity: 1)])),
                   sound: SoundSettings(volume: 0.8, reverb: 0))
    let t = exportTrack(tempo: 120, bars: 1, [pad])
    let plain = OfflineRenderer.render(track: t, loopReady: false)
    let loop = OfflineRenderer.render(track: t, loopReady: true)
    #expect(plain.left != loop.left)
    #expect(plain.left[0..<1000].allSatisfy { abs($0) < 1e-6 })
    #expect(loop.left[0..<1000].contains { abs($0) > 1e-6 })
}

@Test func fileNameSanitized() throws {
    let part = Part(role: .chords, instrument: .pad, content: .drums(DrumPattern(lanes: [:])))
    let t = exportTrack(name: "My Beat!!", tempo: 140.4, [part])
    #expect(ExportNaming.fileName(track: t, part: part) == "My-Beat-140bpm-Aminor-chords.wav")
    #expect(ExportNaming.fileName(track: t, part: nil) == "My-Beat-140bpm-Aminor.wav")
    #expect(ExportNaming.fileName(track: exportTrack(name: "!!!", [part]), part: nil) == "track-140bpm-Aminor.wav")
    #expect(ExportNaming.sanitize("My - Beat") == "My-Beat")
    #expect(ExportNaming.sanitize("a__b--c") == "a__b-c")
    let sharp = Track(name: "k", createdAt: Date(timeIntervalSince1970: 0), tempo: 90,
                      key: try Key(parsing: "F# minor"), bars: 1, parts: [])
    #expect(ExportNaming.fileName(track: sharp, part: nil) == "k-90bpm-Fsharpminor.wav")
    let long = exportTrack(name: String(repeating: "a", count: 60), [part])
    #expect(ExportNaming.fileName(track: long, part: nil).hasPrefix(String(repeating: "a", count: 40) + "-140bpm"))
}

@Test func emptyTrackExportsSilence() {
    let b = OfflineRenderer.render(track: exportTrack(bars: 2, []), loopReady: true)
    #expect(b.frameCount == OfflineRenderer.frameCount(bars: 2, tempo: 140, sampleRate: 48_000))
    #expect(b.left.count == b.frameCount)
    #expect(b.left.allSatisfy { $0 == 0 })
    #expect(b.right.allSatisfy { $0 == 0 })
}
