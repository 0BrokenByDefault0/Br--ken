extension Key {
    /// The shift (in -6...5) that maps this key's pitch set onto `target`'s. Across modes, the target is first
    /// replaced by its relative key in this key's mode, so the transposed pitch set equals the target key's.
    public func semitones(toMatch target: Key) -> Int {
        var targetTonic = target.tonic.rawValue
        if mode != target.mode {
            targetTonic += target.mode == .major ? 9 : 3
        }
        let shift = ((targetTonic - tonic.rawValue) % 12 + 12) % 12
        return shift >= 6 ? shift - 12 : shift
    }
}

extension Part {
    /// Notes shift by `semitones` (clamped to 0...127); chord roots shift with their quality kept; drums are unchanged.
    public func transposed(by semitones: Int) -> Part {
        var part = self
        switch content {
        case .notes(var seq):
            for i in seq.notes.indices {
                seq.notes[i].pitch = min(127, max(0, seq.notes[i].pitch + semitones))
            }
            part.content = .notes(seq)
        case .chords(var prog):
            for i in prog.slots.indices {
                let chord = prog.slots[i].chord
                prog.slots[i].chord = Chord(root: PitchClass(chord.root.rawValue + semitones), quality: chord.quality)
            }
            part.content = .chords(prog)
        case .drums:
            break
        }
        return part
    }
}
