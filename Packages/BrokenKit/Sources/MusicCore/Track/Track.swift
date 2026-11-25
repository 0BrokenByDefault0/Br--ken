import Foundation

public enum PartRole: String, Codable, CaseIterable, Sendable {
    case melody, chords, drums, bass808, counter, texture
}

public enum InstrumentID: String, Codable, CaseIterable, Sendable {
    case trapKit, eight08, bell, pluck, pad, keys
}

public enum PartContent: Hashable, Codable, Sendable {
    case notes(NoteSequence)
    case chords(ChordProgression)
    case drums(DrumPattern)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case notes, chords, drums }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .notes: self = .notes(try c.decode(NoteSequence.self, forKey: .value))
        case .chords: self = .chords(try c.decode(ChordProgression.self, forKey: .value))
        case .drums: self = .drums(try c.decode(DrumPattern.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notes(let v):
            try c.encode(Kind.notes, forKey: .type)
            try c.encode(v, forKey: .value)
        case .chords(let v):
            try c.encode(Kind.chords, forKey: .type)
            try c.encode(v, forKey: .value)
        case .drums(let v):
            try c.encode(Kind.drums, forKey: .type)
            try c.encode(v, forKey: .value)
        }
    }
}

/// All values are 0...1.
public struct SoundSettings: Hashable, Codable, Sendable {
    public var volume: Double
    public var drive: Double
    public var cutoff: Double
    public var reverb: Double
    public var delay: Double

    public init(volume: Double = 0.8, drive: Double = 0.0, cutoff: Double = 1.0,
                reverb: Double = 0.15, delay: Double = 0.0) {
        self.volume = volume
        self.drive = drive
        self.cutoff = cutoff
        self.reverb = reverb
        self.delay = delay
    }
}

public struct Part: Hashable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var role: PartRole
    public var instrument: InstrumentID
    public var content: PartContent
    public var sound: SoundSettings
    public var muted: Bool

    public init(id: UUID = UUID(), role: PartRole, instrument: InstrumentID, content: PartContent,
                sound: SoundSettings = SoundSettings(), muted: Bool = false) {
        self.id = id
        self.role = role
        self.instrument = instrument
        self.content = content
        self.sound = sound
        self.muted = muted
    }
}

public struct Track: Hashable, Codable, Identifiable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var tempo: Double
    public var key: Key
    public var bars: Int
    public var parts: [Part]
    public var completedStages: Set<String>

    public init(version: Int = Track.currentVersion, id: UUID = UUID(), name: String, createdAt: Date,
                tempo: Double, key: Key, bars: Int, parts: [Part], completedStages: Set<String> = []) {
        self.version = version
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.tempo = tempo
        self.key = key
        self.bars = bars
        self.parts = parts
        self.completedStages = completedStages
    }

    public func part(_ role: PartRole) -> Part? {
        parts.first { $0.role == role }
    }

    /// Replaces the first part with the same role, else appends.
    public mutating func setPart(_ p: Part) {
        if let i = parts.firstIndex(where: { $0.role == p.role }) {
            parts[i] = p
        } else {
            parts.append(p)
        }
    }
}
