import Testing
import Foundation
@testable import MusicCore

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
    let f = try Chord(parsing: "F")
    #expect(bars.count == 2 && bars[1].first!.chord == f)
}

@Test func emptyWindowReturnsCandidatesWithoutCrash() throws {
    #expect(!ChordFinder.fits(melody: NoteSequence(notes: []), window: 0..<384, key: try Key(parsing: "A minor")).isEmpty)
}

@Test func toneRolesFollowTheFinderRule() throws {
    let am = try Chord(parsing: "Am")  // A C E
    #expect(ChordFinder.role(of: PitchClass(9), in: am) == .chordTone)
    #expect(ChordFinder.role(of: PitchClass(5), in: am) == .clash)  // F is a half step above E
    #expect(ChordFinder.role(of: PitchClass(2), in: am) == .color)  // D
}
