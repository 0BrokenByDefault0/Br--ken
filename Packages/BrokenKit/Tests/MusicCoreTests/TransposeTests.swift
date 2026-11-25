import Testing
@testable import MusicCore

private func key(_ s: String) -> Key { try! Key(parsing: s) }

@Test func semitonesSameMode() {
    #expect(key("A minor").semitones(toMatch: key("C minor")) == 3)
    #expect(key("A minor").semitones(toMatch: key("E minor")) == -5)
    #expect(key("A minor").semitones(toMatch: key("D# minor")) == -6)
    #expect(key("A minor").semitones(toMatch: key("A minor")) == 0)
}

@Test func semitonesAcrossModes() {
    #expect(key("A minor").semitones(toMatch: key("C major")) == 0)
    #expect(key("A minor").semitones(toMatch: key("G major")) == -2)
    #expect(key("C major").semitones(toMatch: key("A minor")) == 0)
}

@Test func transposedNotesStayInTargetKey() throws {
    let melody = Part(role: .melody, instrument: .bell, content: .notes(try Notation.melody("E4:4 G4:4 A4:8")))
    for target in ["C minor", "G major"] {
        let k = key(target)
        let moved = melody.transposed(by: key("A minor").semitones(toMatch: k))
        guard case .notes(let seq) = moved.content else { Issue.record("not notes"); return }
        #expect(seq.notes.count == 3)
        #expect(seq.notes.allSatisfy { k.contains(PitchClass($0.pitch)) }, "in \(target)")
    }
}

@Test func transposedChordsShiftRoots() throws {
    let part = Part(role: .chords, instrument: .pad, content: .chords(try Notation.chords("Am:16 F:16")))
    let c = key("C minor")
    let moved = part.transposed(by: key("A minor").semitones(toMatch: c))
    guard case .chords(let prog) = moved.content else { Issue.record("not chords"); return }
    #expect(prog.slots.map { $0.chord.symbol(in: c) } == ["Cm", "Ab"])
    #expect(prog.slots.map(\.length) == [Ticks.perBar, Ticks.perBar])
}

@Test func drumsUnchanged() {
    let part = Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: [.kick: [DrumHit(tick: 0, velocity: 1)]])))
    #expect(part.transposed(by: 5) == part)
}
