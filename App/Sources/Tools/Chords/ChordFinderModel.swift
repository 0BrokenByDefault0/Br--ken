import Foundation
import MusicCore
import Observation

/// Pure rules the Chord Finder screen uses (kept apart from SwiftUI so they can be tested).
enum ChordFinderRules {
    enum ChipRole: Equatable { case chordTone, colorTone, clash }
    enum ScoreBand: Equatable { case tone, color, clash }

    /// 0...100 relative to the bar's best score: the best is 100, zero or negative scores are 0.
    static func relativeScore(_ score: Double, best: Double) -> Int {
        guard best > 0, score > 0 else { return 0 }
        return min(100, Int((score / best * 100).rounded()))
    }

    /// 70 and up = chord-tone color, 40 and up = color-tone color, else clash color.
    static func band(forRelative value: Int) -> ScoreBand {
        value >= 70 ? .tone : (value >= 40 ? .color : .clash)
    }

    /// Uses `ChordFinder.role`, the same rule that scores the fits.
    static func chipRole(pitch: Int, chord: Chord) -> ChipRole {
        switch ChordFinder.role(of: PitchClass(pitch), in: chord) {
        case .chordTone: return .chordTone
        case .color: return .colorTone
        case .clash: return .clash
        }
    }

    private static let intervalNames = ["R", "♭2", "9", "♭3", "3", "11", "♭5", "5", "♭6", "6", "♭7", "7"]

    /// Interval of the note above the chord's root: R, ♭3, 3, 5, ♭7, 7, 9...
    static func intervalLabel(pitch: Int, chord: Chord) -> String {
        intervalNames[((pitch - chord.root.rawValue) % 12 + 12) % 12]
    }

    /// One line: which melody notes are chord tones, and which rub a half step above a chord tone.
    static func reason(for fit: ChordFit, key: Key) -> String {
        func names(_ pcs: [PitchClass]) -> String {
            let n = pcs.map { key.spell($0) }
            if n.count <= 1 { return n.first ?? "" }
            return n.dropLast().joined(separator: ", ") + " and " + n[n.count - 1]
        }
        var parts: [String] = []
        if fit.matched.isEmpty {
            parts.append("No melody note is a chord tone")
        } else {
            parts.append("\(names(fit.matched)) \(fit.matched.count == 1 ? "is a chord tone" : "are chord tones")")
        }
        for pc in fit.clashes {
            parts.append("\(key.spell(pc)) rubs a half step above \(key.spell(PitchClass(pc.rawValue - 1)))")
        }
        return parts.joined(separator: "; ")
    }
}

extension ChordProgression {
    /// A copy with `chord` in [start, start+length). Slots that overlap are replaced; the parts of them
    /// that stick out on either side stay.
    func placing(_ chord: Chord, start: Int, length: Int) -> ChordProgression {
        let end = start + length
        var result: [ChordSlot] = []
        for slot in slots {
            let slotEnd = slot.start + slot.length
            if slotEnd <= start || slot.start >= end { result.append(slot); continue }
            if slot.start < start { result.append(ChordSlot(start: slot.start, length: start - slot.start, chord: slot.chord)) }
            if slotEnd > end { result.append(ChordSlot(start: end, length: slotEnd - end, chord: slot.chord)) }
        }
        result.append(ChordSlot(start: start, length: length, chord: chord))
        return ChordProgression(slots: result.sorted { $0.start < $1.start })
    }
}

extension ChordProgression {
    /// The distinct chords sounding in `bar` (at its start and at its second half), in order.
    func chords(inBar bar: Int) -> [Chord] {
        var result: [Chord] = []
        for tick in [bar * Ticks.perBar, bar * Ticks.perBar + Ticks.perBar / 2] {
            if let c = chord(at: tick), c != result.last { result.append(c) }
        }
        return result
    }
}

extension Key {
    /// Roman numeral of `chord` among the diatonic and borrowed chords, if it is one of them.
    func roman(of chord: Chord) -> String? {
        (diatonicTriads() + diatonicSevenths() + borrowedChords()).first { $0.chord == chord }?.roman
    }
}

/// Chord Finder state: the best chords for each bar of a melody, and the progression the owner builds.
@Observable @MainActor
final class ChordFinderModel {
    static let fitsShown = 5

    private(set) var melody: NoteSequence
    let bars: Int
    let key: Key
    var tempo: Double = 140
    private(set) var fitsPerBar: [[ChordFit]]
    /// Placing a different chord in a bar (pads, or `choose`) drops that bar's tapped selection, so the
    /// chips and header follow the slot.
    var progression = ChordProgression(slots: []) {
        didSet {
            for bar in Array(selection.keys) where oldValue.chord(at: bar * Ticks.perBar) != progression.chord(at: bar * Ticks.perBar)
                || oldValue.chord(at: bar * Ticks.perBar + Ticks.perBar / 2) != progression.chord(at: bar * Ticks.perBar + Ticks.perBar / 2) {
                selection[bar] = nil
            }
        }
    }
    /// The fit last tapped in each bar; chips are colored under it.
    private(set) var selection: [Int: ChordFit] = [:]
    var focusedBar = 0

    init(melody: NoteSequence, bars: Int, key: Key) {
        self.melody = melody
        self.bars = bars
        self.key = key
        fitsPerBar = Self.topFits(melody: melody, bars: bars, key: key)
    }

    private static func topFits(melody: NoteSequence, bars: Int, key: Key) -> [[ChordFit]] {
        ChordFinder.fitsPerBar(melody: melody, bars: bars, key: key).map { Array($0.prefix(fitsShown)) }
    }

    /// Replaces the melody and re-ranks every bar. Tapped selections are dropped (their fits are stale);
    /// the chosen progression stays.
    func update(melody: NoteSequence) {
        self.melody = melody
        fitsPerBar = Self.topFits(melody: melody, bars: bars, key: key)
        selection = [:]
    }

    func select(bar: Int, fit: ChordFit) { selection[bar] = fit }

    /// Writes the chord into the bar (start bar*384, length 384), replacing what overlaps, and moves focus to the next bar.
    func choose(bar: Int, fit: ChordFit) {
        progression = progression.placing(fit.chord, start: bar * Ticks.perBar, length: Ticks.perBar)
        selection[bar] = nil
        focusedBar = min(bar + 1, max(bars - 1, 0))
    }

    /// The chord the chips of `bar` are judged against: the tapped fit, else the chord in that bar.
    func chord(forBar bar: Int) -> Chord? {
        selection[bar]?.chord ?? progression.chord(at: bar * Ticks.perBar)
    }

    func notes(inBar bar: Int) -> [NoteEvent] {
        melody.notes(overlapping: (bar * Ticks.perBar)..<((bar + 1) * Ticks.perBar))
    }

    /// A temporary track: the melody (bell) and only this chord (pad) over this bar.
    func audition(bar: Int, fit: ChordFit) -> Track {
        track(chords: ChordProgression(slots: [ChordSlot(start: bar * Ticks.perBar, length: Ticks.perBar, chord: fit.chord)]))
    }

    /// The melody with the chosen progression.
    func fullTrack() -> Track { track(chords: progression) }

    private func track(chords: ChordProgression) -> Track {
        Track(name: "Chord Finder", createdAt: Date(), tempo: tempo, key: key, bars: bars, parts: [
            Part(role: .melody, instrument: .bell, content: .notes(melody)),
            Part(role: .chords, instrument: .pad, content: .chords(chords)),
        ])
    }
}
