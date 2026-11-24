import Testing
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
