import Testing
import Foundation
@testable import MusicCore

struct Row: Sendable, CustomTestStringConvertible {
    let name: String
    let check: TaskCheck
    let pass: Track
    let fail: Track
    var testDescription: String { name }
}

func checkTrack(tempo: Double = 140, melody: String? = nil, chords: String? = nil,
                   drums: [DrumLane: String]? = nil) -> Track {
    var parts: [Part] = []
    if let melody {
        parts.append(Part(role: .melody, instrument: .bell, content: .notes(try! Notation.melody(melody))))
    }
    if let chords {
        parts.append(Part(role: .chords, instrument: .pad, content: .chords(try! Notation.chords(chords))))
    }
    if let drums {
        let lanes = drums.mapValues { try! Notation.drumLane($0) }
        parts.append(Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: lanes))))
    }
    return Track(name: "t", createdAt: Date(timeIntervalSince1970: 0), tempo: tempo,
                 key: try! Key(parsing: "A minor"), bars: 2, parts: parts)
}

func checkRep(_ s: String) -> String { s + s }

let checkRows: [Row] = [
    Row(name: "tempoInRange", check: .tempoInRange(min: 60, max: 180),
        pass: checkTrack(tempo: 140), fail: checkTrack(tempo: 200)),
    Row(name: "inKey", check: .inKey(role: .melody),
        pass: checkTrack(melody: "A4:4 C5:4 E5:8"), fail: checkTrack(melody: "A4:4 G#4:4 E5:8")),
    Row(name: "noteCount", check: .noteCount(role: .melody, min: 3, max: 6),
        pass: checkTrack(melody: "A4:4 C5:4 E5:8"), fail: checkTrack(melody: "A4:16")),
    Row(name: "barRhythmRepeats", check: .barRhythmRepeats(role: .melody),
        pass: checkTrack(melody: "A4:4 C5:4 E5:8 A4:4 D5:4 E5:8"), fail: checkTrack(melody: "A4:4 C5:4 E5:8 A4:8 D5:8")),
    Row(name: "endsOnDegree", check: .endsOnDegree(role: .melody, degrees: [1, 5]),
        pass: checkTrack(melody: "C5:8 A4:8"), fail: checkTrack(melody: "C5:8 B4:8")),
    Row(name: "chordCount", check: .chordCount(role: .chords, min: 4, max: nil),
        pass: checkTrack(chords: "Am:8 F:8 C:8 G:8"), fail: checkTrack(chords: "Am:16 F:16")),
    Row(name: "chordsInKey", check: .chordsInKey(role: .chords),
        pass: checkTrack(chords: "Am:16 E7:16"), fail: checkTrack(chords: "Am:16 D:16")),
    Row(name: "chordDegrees", check: .chordDegrees(role: .chords, required: [1, 4, 5]),
        pass: checkTrack(chords: "Am:8 Dm:8 Em:16"), fail: checkTrack(chords: "Am:16 F:16")),
    Row(name: "chordsFitMelody", check: .chordsFitMelody(chords: .chords, melody: .melody, minScoreRatio: 0.6),
        pass: checkTrack(melody: "A4:16 F4:16", chords: "Am:16 F:16"),
        fail: checkTrack(melody: "A4:16 F4:16", chords: "Am:16 E:16")),
    Row(name: "extendedChordCount", check: .extendedChordCount(role: .chords, min: 2),
        pass: checkTrack(chords: "Am7:16 Fmaj7:16"), fail: checkTrack(chords: "Am7:16 F:16")),
    Row(name: "drumHitOnBeats", check: .drumHitOnBeats(lane: .snare, beats: [3], everyBar: true),
        pass: checkTrack(drums: [.snare: checkRep("........x.......")]),
        fail: checkTrack(drums: [.snare: "........x......."])),
    Row(name: "laneHitCount", check: .laneHitCount(lane: .closedHat, min: 8),
        pass: checkTrack(drums: [.closedHat: "x.x.x.x.x.x.x.x."]),
        fail: checkTrack(drums: [.closedHat: "x...x..........."])),
    Row(name: "hatRollPresent", check: .hatRollPresent,
        pass: checkTrack(drums: [.closedHat: "x.x.x.x.x.x.2.x."]),
        fail: checkTrack(drums: [.closedHat: "x.x.x.x.x.x.x.x."])),
    Row(name: "syncopatedKicks", check: .syncopatedKicks(min: 2),
        pass: checkTrack(drums: [.kick: "x..x..x........."]),
        fail: checkTrack(drums: [.kick: "x...x...x...x..."])),
    Row(name: "barsDiffer", check: .barsDiffer(role: .drums),
        pass: checkTrack(drums: [.kick: "x...............x..x..x........."]),
        fail: checkTrack(drums: [.kick: checkRep("x...............")])),
]

@Test(arguments: checkRows) func checksPassAndFail(_ row: Row) {
    let pass = CheckRunner.run([row.check], on: row.pass)
    #expect(pass.count == 1 && pass[0].passed, "pass input: \(pass.first?.message ?? "")")
    let fail = CheckRunner.run([row.check], on: row.fail)
    #expect(fail.count == 1 && !fail[0].passed && !fail[0].message.isEmpty)
}

@Test func missingRoleFailsWithMessage() {
    let r = CheckRunner.run([.inKey(role: .melody)], on: checkTrack())
    #expect(!r[0].passed && r[0].message.contains("melody"))
}

@Test func resultsKeepCheckOrder() {
    let checks: [TaskCheck] = [.tempoInRange(min: 60, max: 100), .hatRollPresent, .tempoInRange(min: 100, max: 180)]
    let r = CheckRunner.run(checks, on: checkTrack())
    #expect(r.map(\.check) == checks && r.map(\.passed) == [false, false, true])
}

@Test func inKeyMessageNamesNoteAndBar() {
    let r = CheckRunner.run([.inKey(role: .melody)], on: checkTrack(melody: "A4:16 G#4:16"))
    #expect(r[0].message == "Bar 2: G# isn't in A minor.")
}

@Test func endsOnDegreeWithNoNotesFails() {
    let r = CheckRunner.run([.endsOnDegree(role: .melody, degrees: [1])], on: checkTrack(melody: "r:32"))
    #expect(!r[0].passed)
}

@Test func barsDifferOnOneBarTrackFails() {
    var t = checkTrack(drums: [.kick: "x..............."])
    t.bars = 1
    let r = CheckRunner.run([.barsDiffer(role: .drums)], on: t)
    #expect(!r[0].passed && r[0].message.contains("one bar"))
}

@Test func chordsFitMelodyIgnoresBarsWithoutMelody() {
    let t = checkTrack(melody: "A4:16", chords: "Am:16 E:16")
    let r = CheckRunner.run([.chordsFitMelody(chords: .chords, melody: .melody, minScoreRatio: 0.6)], on: t)
    #expect(r[0].passed)
}

@Test func checkCodableShape() throws {
    let dec = JSONDecoder()
    let a = try dec.decode(TaskCheck.self, from: Data(#"{"kind":"noteCount","role":"melody","min":3,"max":6}"#.utf8))
    #expect(a == .noteCount(role: .melody, min: 3, max: 6))
    let b = try dec.decode(TaskCheck.self, from: Data(#"{"kind":"noteCount","role":"melody","min":3}"#.utf8))
    #expect(b == .noteCount(role: .melody, min: 3, max: nil))
    let c = try dec.decode(TaskCheck.self, from: Data(#"{"kind":"drumHitOnBeats","lane":"snare","beats":[3],"everyBar":true}"#.utf8))
    #expect(c == .drumHitOnBeats(lane: .snare, beats: [3], everyBar: true))
    let d = try dec.decode(TaskCheck.self, from: Data(#"{"kind":"hatRollPresent"}"#.utf8))
    #expect(d == .hatRollPresent)
    let all: [TaskCheck] = [a, b, c, d, .tempoInRange(min: 60, max: 180),
                            .chordsFitMelody(chords: .chords, melody: .melody, minScoreRatio: 0.6)]
    let back = try dec.decode([TaskCheck].self, from: JSONEncoder().encode(all))
    #expect(back == all)
}
