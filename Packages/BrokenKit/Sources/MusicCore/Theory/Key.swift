import Foundation

public enum Mode: String, Codable, Sendable {
    case major, minor
}

public enum ScaleType: CaseIterable, Sendable {
    case major, naturalMinor, harmonicMinor, dorian, phrygian, majorPentatonic, minorPentatonic

    var intervals: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: [0, 2, 3, 5, 7, 8, 11]
        case .dorian: [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: [0, 1, 3, 5, 7, 8, 10]
        case .majorPentatonic: [0, 2, 4, 7, 9]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        }
    }

    public func pitchClasses(tonic: PitchClass) -> [PitchClass] {
        intervals.map { PitchClass(tonic.rawValue + $0) }
    }
}

public struct DiatonicChord: Hashable, Sendable {
    public let degree: Int
    public let roman: String
    public let chord: Chord

    public init(degree: Int, roman: String, chord: Chord) {
        self.degree = degree
        self.roman = roman
        self.chord = chord
    }
}

public struct Key: Hashable, Codable, Sendable {
    public let tonic: PitchClass
    public let mode: Mode

    public init(tonic: PitchClass, mode: Mode) {
        self.tonic = tonic
        self.mode = mode
    }

    /// Parses e.g. "A minor", "Eb major", "C# minor".
    public init(parsing string: String) throws {
        let parts = string.split(separator: " ").map(String.init)
        guard parts.count == 2,
              let (pc, rest) = PitchClass.parsePrefix(parts[0]), rest.isEmpty,
              let mode = Mode(rawValue: parts[1].lowercased())
        else { throw TheoryError.invalidKey(string) }
        self.init(tonic: pc, mode: mode)
    }

    private var usesFlats: Bool {
        let flatTonics: Set<Int> = mode == .major ? [5, 10, 3, 8, 1, 6] : [2, 7, 0, 5, 10, 3]
        return flatTonics.contains(tonic.rawValue)
    }

    public var name: String { "\(spell(tonic)) \(mode.rawValue)" }

    private var scaleType: ScaleType { mode == .major ? .major : .naturalMinor }

    public var scalePitchClasses: [PitchClass] { scaleType.pitchClasses(tonic: tonic) }

    public func contains(_ pc: PitchClass) -> Bool { scalePitchClasses.contains(pc) }

    public func degree(of pc: PitchClass) -> Int? {
        scalePitchClasses.firstIndex(of: pc).map { $0 + 1 }
    }

    public func spell(_ pc: PitchClass) -> String {
        (usesFlats ? PitchClass.flatNames : PitchClass.sharpNames)[pc.rawValue]
    }

    /// Octave numbering with C4 = 60.
    public func spell(midi: Int) -> String {
        let pc = PitchClass(midi)
        let octave = (midi - pc.rawValue) / 12 - 1
        return "\(spell(pc))\(octave)"
    }

    private static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

    private func stacked(_ steps: [Int], degreeIndex i: Int) -> (root: PitchClass, intervals: [Int]) {
        let scale = scalePitchClasses
        let root = scale[i]
        let ivs = steps.map { (scale[(i + $0) % 7].rawValue - root.rawValue + 12) % 12 }
        return (root, ivs)
    }

    public func diatonicTriads() -> [DiatonicChord] {
        (0..<7).map { i in
            let (root, ivs) = stacked([2, 4], degreeIndex: i)
            let quality: ChordQuality
            let numeral = Key.numerals[i]
            let roman: String
            switch ivs {
            case [4, 7]: quality = .major; roman = numeral
            case [3, 7]: quality = .minor; roman = numeral.lowercased()
            case [3, 6]: quality = .diminished; roman = numeral.lowercased() + "°"
            default: quality = .augmented; roman = numeral + "+"
            }
            return DiatonicChord(degree: i + 1, roman: roman, chord: Chord(root: root, quality: quality))
        }
    }

    public func diatonicSevenths() -> [DiatonicChord] {
        (0..<7).map { i in
            let (root, ivs) = stacked([2, 4, 6], degreeIndex: i)
            let quality: ChordQuality
            let numeral = Key.numerals[i]
            let roman: String
            switch ivs {
            case [4, 7, 11]: quality = .major7; roman = numeral + "maj7"
            case [3, 7, 10]: quality = .minor7; roman = numeral.lowercased() + "7"
            case [3, 6, 10]: quality = .halfDiminished7; roman = numeral.lowercased() + "ø7"
            default: quality = .dominant7; roman = numeral + "7"
            }
            return DiatonicChord(degree: i + 1, roman: roman, chord: Chord(root: root, quality: quality))
        }
    }

    /// Minor keys: harmonic-minor V and V7. Major keys: none.
    public func borrowedChords() -> [DiatonicChord] {
        guard mode == .minor else { return [] }
        let dominant = PitchClass(tonic.rawValue + 7)
        return [
            DiatonicChord(degree: 5, roman: "V", chord: Chord(root: dominant, quality: .major)),
            DiatonicChord(degree: 5, roman: "V7", chord: Chord(root: dominant, quality: .dominant7)),
        ]
    }
}
