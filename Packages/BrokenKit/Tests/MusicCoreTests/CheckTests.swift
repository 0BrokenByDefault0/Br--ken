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

private func firstMessage(_ check: TaskCheck, _ t: Track) -> CheckResult {
    CheckRunner.run([check], on: t)[0]
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
}

@Test func checkCodableRoundTripsEveryCase() throws {
    let all: [(TaskCheck, String)] = [
        (.tempoInRange(min: 60, max: 180), "tempoInRange"),
        (.inKey(role: .melody), "inKey"),
        (.noteCount(role: .melody, min: 3, max: 6), "noteCount"),
        (.noteCount(role: .melody, min: 3, max: nil), "noteCount"),
        (.barRhythmRepeats(role: .melody), "barRhythmRepeats"),
        (.endsOnDegree(role: .melody, degrees: [1, 5]), "endsOnDegree"),
        (.chordCount(role: .chords, min: 4, max: 8), "chordCount"),
        (.chordCount(role: .chords, min: 4, max: nil), "chordCount"),
        (.chordsInKey(role: .chords), "chordsInKey"),
        (.chordDegrees(role: .chords, required: [1, 4, 5]), "chordDegrees"),
        (.chordsFitMelody(chords: .chords, melody: .melody, minScoreRatio: 0.6), "chordsFitMelody"),
        (.extendedChordCount(role: .chords, min: 2), "extendedChordCount"),
        (.drumHitOnBeats(lane: .snare, beats: [3], everyBar: true), "drumHitOnBeats"),
        (.laneHitCount(lane: .closedHat, min: 8), "laneHitCount"),
        (.hatRollPresent, "hatRollPresent"),
        (.syncopatedKicks(min: 2), "syncopatedKicks"),
        (.barsDiffer(role: .drums), "barsDiffer"),
    ]
    #expect(Set(all.map(\.1)).count == 15)
    for (check, kind) in all {
        let data = try JSONEncoder().encode(check)
        #expect(try JSONDecoder().decode(TaskCheck.self, from: data) == check)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["kind"] as? String == kind)
        if case .noteCount(_, _, nil) = check { #expect(obj["max"] == nil) }
        if case .chordCount(_, _, nil) = check { #expect(obj["max"] == nil) }
        if case .noteCount(_, _, let m?) = check { #expect(obj["max"] as? Int == m) }
    }
}

@Test func scorePassesWhenBestIsNotPositive() {
    #expect(CheckRunner.scorePasses(-0.2, best: -0.2, ratio: 0.6))
    #expect(!CheckRunner.scorePasses(-1.0, best: -0.2, ratio: 0.6))
    #expect(!CheckRunner.scorePasses(0.0, best: 0.0 - 0.1, ratio: 0.6))
    #expect(CheckRunner.scorePasses(3.5, best: 5.8, ratio: 0.6))
    #expect(!CheckRunner.scorePasses(3.4, best: 5.8, ratio: 0.6))
}

@Test func chordOutsideCandidatesUsesFallbackScore() {
    // Bb major is not diatonic to A minor, so it is not among ChordFinder's candidates.
    let t = checkTrack(melody: "A4:16", chords: "Bb:16 Am:16")
    let strict = firstMessage(.chordsFitMelody(chords: .chords, melody: .melody, minScoreRatio: 0.6), t)
    #expect(!strict.passed && strict.message.contains("Bar 1") && strict.message.contains("A#"))
    let lax = firstMessage(.chordsFitMelody(chords: .chords, melody: .melody, minScoreRatio: 0.1), t)
    #expect(lax.passed)
}

@Test func barWithMelodyButNoChordFails() {
    let t = checkTrack(melody: "A4:16 F4:16", chords: "Am:16")
    let r = firstMessage(.chordsFitMelody(chords: .chords, melody: .melody, minScoreRatio: 0.6), t)
    #expect(!r.passed && r.message.contains("Bar 2") && r.message.contains("no chord"))
}

@Test func drumHitOnBeatsAnyBarWhenNotEveryBar() {
    let t = checkTrack(drums: [.snare: "................" + "........x......."])
    #expect(firstMessage(.drumHitOnBeats(lane: .snare, beats: [3], everyBar: false), t).passed)
    let strict = firstMessage(.drumHitOnBeats(lane: .snare, beats: [3], everyBar: true), t)
    #expect(!strict.passed && strict.message.contains("Bar 1"))
    let none = checkTrack(drums: [.snare: "x..............."])
    #expect(!firstMessage(.drumHitOnBeats(lane: .snare, beats: [3], everyBar: false), none).passed)
}

@Test func drumHitOnBeatsNamesOnlyMissingBeats() {
    // Beats 1 and 3 present in bar 1; bar 2 has beat 1 only.
    let t = checkTrack(drums: [.snare: "x.......x......." + "x..............."])
    let r = firstMessage(.drumHitOnBeats(lane: .snare, beats: [1, 3], everyBar: true), t)
    #expect(!r.passed && r.message == "Bar 2: the snare is missing on beat 3.")
    let both = checkTrack(drums: [.snare: "................" + "................"])
    let r2 = firstMessage(.drumHitOnBeats(lane: .snare, beats: [1, 3], everyBar: true), both)
    #expect(r2.message == "Bar 1: the snare is missing on beats 1 and 3.")
}

@Test func hatRollDetectedOnOpenHatLane() {
    let t = checkTrack(drums: [.openHat: "x.x.x.x.x.x.2.x."])
    #expect(firstMessage(.hatRollPresent, t).passed)
}

@Test func missingDrumLaneAndPartMessages() {
    let kickOnly = checkTrack(drums: [.kick: "x..............."])
    let snare = firstMessage(.drumHitOnBeats(lane: .snare, beats: [3], everyBar: true), kickOnly)
    #expect(!snare.passed && snare.message.contains("snare"))
    let lane = firstMessage(.laneHitCount(lane: .closedHat, min: 2), kickOnly)
    #expect(!lane.passed && lane.message.contains("closed hat"))
    for check in [TaskCheck.hatRollPresent, .syncopatedKicks(min: 1), .laneHitCount(lane: .kick, min: 1),
                  .drumHitOnBeats(lane: .snare, beats: [3], everyBar: true), .barsDiffer(role: .drums)] {
        let r = firstMessage(check, checkTrack())
        #expect(!r.passed && r.message.contains("drums"))
    }
}

@Test func singularMessagesUseCorrectPlurals() {
    let ext = firstMessage(.extendedChordCount(role: .chords, min: 1), checkTrack(chords: "Am7:16 F:16"))
    #expect(ext.passed && ext.message.contains("1 extended chord ") && !ext.message.contains("chords"))
    let extFail = firstMessage(.extendedChordCount(role: .chords, min: 2), checkTrack(chords: "Am7:16 F:16"))
    #expect(extFail.message.contains("Only 1 extended chord;"))
    let hat = firstMessage(.laneHitCount(lane: .closedHat, min: 1), checkTrack(drums: [.closedHat: "x..............."]))
    #expect(hat.passed && hat.message.contains("1 closed hat hit "))
    let kick = firstMessage(.syncopatedKicks(min: 1), checkTrack(drums: [.kick: "x..x............"]))
    #expect(kick.passed && kick.message.contains("1 off-beat kick "))
    let kickFail = firstMessage(.syncopatedKicks(min: 2), checkTrack(drums: [.kick: "x..x............"]))
    #expect(kickFail.message.contains("1 off-beat kick;"))
    let note = firstMessage(.noteCount(role: .melody, min: 2, max: nil), checkTrack(melody: "A4:16"))
    #expect(note.message.hasPrefix("1 note;"))
}
