public struct ChordSlot: Hashable, Codable, Sendable {
    public var start: Int
    public var length: Int
    public var chord: Chord

    public init(start: Int, length: Int, chord: Chord) {
        self.start = start
        self.length = length
        self.chord = chord
    }
}

public struct ChordProgression: Hashable, Codable, Sendable {
    public var slots: [ChordSlot]

    public init(slots: [ChordSlot]) {
        self.slots = slots
    }

    public func chord(at tick: Int) -> Chord? {
        slots.first { tick >= $0.start && tick < $0.start + $0.length }?.chord
    }

    /// One note per voiced pitch per slot, voiced with `Voicer.voiceLead`.
    public func renderedNotes(velocity: Float = 0.7) -> NoteSequence {
        let voicings = Voicer.voiceLead(slots.map(\.chord))
        var notes: [NoteEvent] = []
        for (slot, voicing) in zip(slots, voicings) {
            for pitch in voicing {
                notes.append(NoteEvent(start: slot.start, length: slot.length, pitch: pitch, velocity: velocity))
            }
        }
        return NoteSequence(notes: notes)
    }
}
