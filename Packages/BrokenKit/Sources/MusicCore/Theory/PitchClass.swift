import Foundation

public enum TheoryError: Error, Equatable {
    case invalidKey(String)
    case invalidChord(String)
}

public struct PitchClass: Hashable, Codable, Sendable {
    /// 0–11, C = 0.
    public let rawValue: Int

    /// Wraps any integer (negative included) modulo 12.
    public init(_ v: Int) {
        rawValue = ((v % 12) + 12) % 12
    }

    /// Decodes a bare integer and wraps it modulo 12, so persisted data can never hold an out-of-range value.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// Parses a leading note name (A–G plus optional `#` or `b`) and returns it with the remaining text.
    static func parsePrefix(_ s: String) -> (PitchClass, String)? {
        guard let first = s.first else { return nil }
        let base: Int
        switch first {
        case "C": base = 0
        case "D": base = 2
        case "E": base = 4
        case "F": base = 5
        case "G": base = 7
        case "A": base = 9
        case "B": base = 11
        default: return nil
        }
        var rest = String(s.dropFirst())
        var offset = 0
        if rest.hasPrefix("#") {
            offset = 1
            rest.removeFirst()
        } else if rest.hasPrefix("b") {
            offset = -1
            rest.removeFirst()
        }
        return (PitchClass(base + offset), rest)
    }
}
