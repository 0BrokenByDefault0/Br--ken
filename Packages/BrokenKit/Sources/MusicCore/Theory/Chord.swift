import Foundation

public enum ChordQuality: String, Codable, CaseIterable, Sendable {
    case major, minor, diminished, augmented
    case major7, minor7, dominant7, halfDiminished7
    case sus2, sus4, add9, minor9, major9

    public var intervals: [Int] {
        switch self {
        case .major: [0, 4, 7]
        case .minor: [0, 3, 7]
        case .diminished: [0, 3, 6]
        case .augmented: [0, 4, 8]
        case .major7: [0, 4, 7, 11]
        case .minor7: [0, 3, 7, 10]
        case .dominant7: [0, 4, 7, 10]
        case .halfDiminished7: [0, 3, 6, 10]
        case .sus2: [0, 2, 7]
        case .sus4: [0, 5, 7]
        case .add9: [0, 4, 7, 14]
        case .minor9: [0, 3, 7, 10, 14]
        case .major9: [0, 4, 7, 11, 14]
        }
    }

    public var symbolSuffix: String {
        switch self {
        case .major: ""
        case .minor: "m"
        case .diminished: "dim"
        case .augmented: "aug"
        case .major7: "maj7"
        case .minor7: "m7"
        case .dominant7: "7"
        case .halfDiminished7: "m7b5"
        case .sus2: "sus2"
        case .sus4: "sus4"
        case .add9: "add9"
        case .minor9: "m9"
        case .major9: "maj9"
        }
    }

    public var isExtended: Bool {
        switch self {
        case .major7, .minor7, .dominant7, .halfDiminished7, .add9, .minor9, .major9: true
        default: false
        }
    }
}

public struct Chord: Hashable, Codable, Sendable {
    public let root: PitchClass
    public let quality: ChordQuality

    public init(root: PitchClass, quality: ChordQuality) {
        self.root = root
        self.quality = quality
    }

    /// Parses e.g. "F#m7", "Bbmaj9", "Bø7", "C°", "G+".
    public init(parsing string: String) throws {
        guard let (pc, rest) = PitchClass.parsePrefix(string) else {
            throw TheoryError.invalidChord(string)
        }
        let aliases: [String: ChordQuality] = ["°": .diminished, "+": .augmented, "ø7": .halfDiminished7]
        guard let quality = aliases[rest]
            ?? ChordQuality.allCases.first(where: { $0.symbolSuffix == rest })
        else { throw TheoryError.invalidChord(string) }
        self.init(root: pc, quality: quality)
    }

    public var pitchClasses: Set<PitchClass> {
        Set(quality.intervals.map { PitchClass(root.rawValue + $0) })
    }

    public func symbol(in key: Key?) -> String {
        let name = key?.spell(root) ?? PitchClass.sharpNames[root.rawValue]
        return name + quality.symbolSuffix
    }
}
