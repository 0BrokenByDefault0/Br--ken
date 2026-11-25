public struct ChordFit: Hashable, Sendable {
    public let chord: Chord
    public let roman: String
    public let score: Double
    public let matched: [PitchClass]
    public let clashes: [PitchClass]

    public init(chord: Chord, roman: String, score: Double, matched: [PitchClass], clashes: [PitchClass]) {
        self.chord = chord
        self.roman = roman
        self.score = score
        self.matched = matched
        self.clashes = clashes
    }
}

public enum ChordFinder {
    /// Ranks diatonic triads, diatonic sevenths and borrowed chords by how well they fit the melody in `window`.
    public static func fits(melody: NoteSequence, window: Range<Int>, key: Key) -> [ChordFit] {
        var weights = [Int: Double](minimumCapacity: 12)
        for note in melody.notes(overlapping: window) {
            let inside = min(note.start + note.length, window.upperBound) - max(note.start, window.lowerBound)
            guard inside > 0 else { continue }
            let beat = note.start % 192 == 0 ? 1.5 : 1.0
            let pc = PitchClass(note.pitch).rawValue
            weights[pc, default: 0] += Double(inside) / 96.0 * beat
        }
        let melodyPCs = weights.keys.sorted()

        let candidates = key.diatonicTriads() + key.diatonicSevenths() + key.borrowedChords()
        let fits: [ChordFit] = candidates.map { candidate in
            let tones = candidate.chord.pitchClasses
            var score = 0.0
            var matched: [PitchClass] = []
            var clashes: [PitchClass] = []
            for raw in melodyPCs {
                let w = weights[raw]!
                let pc = PitchClass(raw)
                if tones.contains(pc) {
                    score += w
                    matched.append(pc)
                } else if tones.contains(PitchClass(raw - 1)) {
                    score -= w
                    clashes.append(pc)
                } else {
                    score += 0.25 * w
                }
            }
            let missing = tones.filter { weights[$0.rawValue] == nil }.count
            score -= 0.1 * Double(missing)
            return ChordFit(chord: candidate.chord, roman: candidate.roman, score: score,
                            matched: matched, clashes: clashes)
        }

        // Stable by construction: ties keep candidate order.
        return fits.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element)
    }

    public static func fitsPerBar(melody: NoteSequence, bars: Int, key: Key) -> [[ChordFit]] {
        (0..<max(bars, 0)).map { bar in
            fits(melody: melody, window: (bar * Ticks.perBar)..<((bar + 1) * Ticks.perBar), key: key)
        }
    }
}
