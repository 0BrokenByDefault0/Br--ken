import Testing
import Foundation
@testable import MusicCore

@Test func tickConstants() { #expect(Ticks.perSixteenth == 24 && Ticks.perBar == 384) }
@Test func parseMelody() throws {
    let s = try Notation.melody("A4:4 r:4 C5:2 E5:6~")
    #expect(s.notes == [NoteEvent(start: 0, length: 96, pitch: 69),
                        NoteEvent(start: 192, length: 48, pitch: 72),
                        NoteEvent(start: 240, length: 144, pitch: 76, glide: true)])
}
@Test func parseMelodyAccidentals() throws {
    let s = try Notation.melody("Bb3:1 F#4:1")
    #expect(s.notes.map(\.pitch) == [58, 66])
    #expect(throws: (any Error).self) { try Notation.melody("C4:0") }
    #expect(throws: (any Error).self) { try Notation.melody("H4:2") }
    #expect(throws: (any Error).self) { try Notation.melody("C4") }
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
@Test func drumMidiNotes() {
    #expect(DrumLane.kick.midiNote == 36 && DrumLane.openHat.midiNote == 46 && DrumLane.perc.midiNote == 45)
}
@Test func notesOverlapping() throws {
    let s = try Notation.melody("C4:4 D4:4 E4:4")
    #expect(s.notes(overlapping: 90..<100).map(\.pitch) == [60, 62])
    #expect(s.notes(overlapping: 96..<192).map(\.pitch) == [62])
}
@Test func renderedProgression() throws {
    let p = try Notation.chords("C:16 F:16")
    let notes = p.renderedNotes().notes
    let voiced = Voicer.voiceLead(p.slots.map(\.chord))
    #expect(notes.count == voiced[0].count + voiced[1].count)
    #expect(notes.filter { $0.start == 384 }.map(\.pitch).sorted() == voiced[1])
    #expect(notes.allSatisfy { $0.length == 384 && $0.velocity == 0.7 })
}
@Test func drumPatternRoundTrip() throws {
    var d = DrumPattern(lanes: [:])
    d.toggle(lane: .kick, step: 0); d.toggle(lane: .snare, step: 4)
    let data = try JSONEncoder().encode(d)
    #expect(try JSONDecoder().decode(DrumPattern.self, from: data) == d)
}
@Test func progressionRoundTrip() throws {
    let p = try Notation.chords("Am:16 F:8")
    #expect(try JSONDecoder().decode(ChordProgression.self, from: JSONEncoder().encode(p)) == p)
}
@Test func rollFillReplacesOnlyInsideRange() {
    var d = DrumPattern(lanes: [.closedHat: [DrumHit(tick: 0, velocity: 0.8), DrumHit(tick: 287, velocity: 0.8),
                                             DrumHit(tick: 290, velocity: 0.8), DrumHit(tick: 384, velocity: 0.8)]])
    d.fillRoll(lane: .closedHat, from: 288, to: 384, rate: .thirtySecond, velocities: 0.5...1.0)
    let ticks = d.lanes[.closedHat]!.map(\.tick)
    #expect(!ticks.contains(290))
    #expect(ticks.contains(0) && ticks.contains(287) && ticks.contains(384))
    #expect(ticks == ticks.sorted())
    #expect(ticks.count == 3 + 8)
}
@Test func decodingSortsUnsortedInput() throws {
    var s = NoteSequence(notes: [])
    s.notes = [NoteEvent(start: 96, length: 24, pitch: 62), NoteEvent(start: 0, length: 24, pitch: 60)]
    let ds = try JSONDecoder().decode(NoteSequence.self, from: JSONEncoder().encode(s))
    #expect(ds.notes.map(\.start) == [0, 96])
    var d = DrumPattern(lanes: [:])
    d.lanes[.kick] = [DrumHit(tick: 96, velocity: 0.8), DrumHit(tick: 0, velocity: 0.8)]
    let dd = try JSONDecoder().decode(DrumPattern.self, from: JSONEncoder().encode(d))
    #expect(dd.lanes[.kick]!.map(\.tick) == [0, 96])
}
