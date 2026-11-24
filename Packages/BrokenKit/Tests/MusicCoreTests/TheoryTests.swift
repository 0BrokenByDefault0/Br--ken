import Testing
import Foundation
@testable import MusicCore

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

private func staysNear(_ next: [Int], _ previous: [Int]) -> Bool {
    next.allSatisfy { n in previous.contains { abs(n - $0) <= 12 } }
}

@Test func voiceLeadTriadToSeventh() throws {
    let f = try Chord(parsing: "F"), g7 = try Chord(parsing: "G7")
    let v = Voicer.voiceLead([f, g7])
    #expect(v[0] == [53, 57, 60])
    // Candidate costs vs [53,57,60]: [55,59,62,65]=15, [59,62,65,67]=24, [62,65,67,71]=41,
    // [50,53,55,59]=9, [53,55,59,62]=8 (best).
    #expect(v[1] == [53, 55, 59, 62])
    #expect(staysNear(v[1], v[0]))
}

@Test func voiceLeadSeventhToNinth() throws {
    let am7 = try Chord(parsing: "Am7"), cmaj9 = try Chord(parsing: "Cmaj9")
    let v = Voicer.voiceLead([am7, cmaj9])
    #expect(v[0] == [57, 60, 64, 67])
    // Candidate costs vs [57,60,64,67]: [48,52,55,59,62]=29, [60,64,67,71,74]=14, [52,55,59,60,62]=19,
    // [55,59,60,62,64]=10, [59,60,62,64,67]=5 (best), [60,62,64,67,71]=9, [48,50,52,55,59]=40.
    #expect(v[1] == [59, 60, 62, 64, 67])
    #expect(staysNear(v[1], v[0]))
}

@Test func pitchClassDecodingWraps() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(PitchClass.self, from: Data("14".utf8)).rawValue == 2)
    #expect(try decoder.decode(PitchClass.self, from: Data("-1".utf8)).rawValue == 11)
    let key = Key(tonic: PitchClass(3), mode: .minor)
    let round = try decoder.decode(Key.self, from: JSONEncoder().encode(key))
    #expect(round == key)
}
