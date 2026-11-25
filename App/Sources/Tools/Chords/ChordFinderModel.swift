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

    /// Same rule as `ChordFinder`: a chord tone, or a clash if it is a half step above a chord tone, else a color tone.
    static func chipRole(pitch: Int, chord: Chord) -> ChipRole {
        let tones = chord.pitchClasses
        let pc = PitchClass(pitch)
        if tones.contains(pc) { return .chordTone }
        if tones.contains(PitchClass(pc.rawValue - 1)) { return .clash }
        return .colorTone
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

    let melody: NoteSequence
    let bars: Int
    let key: Key
    var tempo: Double = 140
    private(set) var fitsPerBar: [[ChordFit]]
    var progression = ChordProgression(slots: [])
    /// The fit last tapped in each bar; chips are colored under it.
    private(set) var selection: [Int: ChordFit] = [:]
    var focusedBar = 0

    init(melody: NoteSequence, bars: Int, key: Key) {
        self.melody = melody
        self.bars = bars
        self.key = key
        fitsPerBar = ChordFinder.fitsPerBar(melody: melody, bars: bars, key: key)
            .map { Array($0.prefix(Self.fitsShown)) }
    }

    func select(bar: Int, fit: ChordFit) { selection[bar] = fit }

    /// Writes the chord into the bar (start bar*384, length 384), replacing what overlaps, and moves focus to the next bar.
    func choose(bar: Int, fit: ChordFit) {
        progression = progression.placing(fit.chord, start: bar * Ticks.perBar, length: Ticks.perBar)
        selection[bar] = fit
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
