import Foundation

public enum Voicer {
    /// Close voicing with the root in MIDI 48–59; `inversion` moves that many lowest notes up an octave.
    public static func closeVoicing(_ c: Chord, inversion: Int = 0) -> [Int] {
        let base = 48 + c.root.rawValue
        var notes = c.quality.intervals.map { base + $0 }
        let inv = ((inversion % notes.count) + notes.count) % notes.count
        for i in 0..<inv { notes[i] += 12 }
        return notes.sorted()
    }

    /// Voice-leads a progression. The first chord uses `closeVoicing`. For each later chord, every inversion
    /// (shifted by whole octaves so its lowest note is in 48...62) is a candidate, and the lowest-cost one wins;
    /// ties go to the lower inversion, then the lower octave.
    ///
    /// Cost rule: when both voicings have the same note count, the sum of |differences| between the sorted
    /// voicings. When the counts differ, the sum over each new note of its distance to the nearest previous note,
    /// plus the sum over each previous note of its distance to the nearest new note.
    public static func voiceLead(_ chords: [Chord]) -> [[Int]] {
        guard let first = chords.first else { return [] }
        var result = [closeVoicing(first)]
        for chord in chords.dropFirst() {
            let previous = result[result.count - 1]
            var best: [Int] = []
            var bestCost = Int.max
            for inversion in 0..<chord.quality.intervals.count {
                let close = closeVoicing(chord, inversion: inversion)
                for octave in -10...10 {
                    let candidate = close.map { $0 + 12 * octave }
                    guard (48...62).contains(candidate[0]) else { continue }
                    let cost = movementCost(from: previous, to: candidate)
                    if cost < bestCost {
                        bestCost = cost
                        best = candidate
                    }
                }
            }
            result.append(best)
        }
        return result
    }

    private static func movementCost(from previous: [Int], to candidate: [Int]) -> Int {
        if previous.count == candidate.count {
            return zip(candidate, previous).reduce(0) { $0 + abs($1.0 - $1.1) }
        }
        func nearest(_ n: Int, in notes: [Int]) -> Int {
            notes.map { abs($0 - n) }.min() ?? 0
        }
        return candidate.reduce(0) { $0 + nearest($1, in: previous) }
            + previous.reduce(0) { $0 + nearest($1, in: candidate) }
    }
}
