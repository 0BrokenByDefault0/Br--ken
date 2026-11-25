import Foundation

public enum ContentError: Error, Equatable {
    /// A clip part must have exactly one of melody / chords / drums.
    case invalidClipPart(String)
}

public struct Stage: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let tagline: String
    public let order: Int
    public let lessons: [String]
    public var isAvailable: Bool { !lessons.isEmpty }

    public init(id: String, title: String, tagline: String, order: Int, lessons: [String]) {
        self.id = id
        self.title = title
        self.tagline = tagline
        self.order = order
        self.lessons = lessons
    }
}

public struct Journey: Codable, Sendable {
    public let version: Int
    public let stages: [Stage]

    public init(version: Int, stages: [Stage]) {
        self.version = version
        self.stages = stages
    }
}

/// Exactly one of `melody` / `chords` / `drums` must be set.
public struct ClipPart: Codable, Sendable {
    public let role: PartRole
    public let instrument: InstrumentID
    public let melody: String?
    public let chords: String?
    public let drums: [DrumLane: String]?
    public let sound: SoundSettings?

    public init(role: PartRole, instrument: InstrumentID, melody: String? = nil, chords: String? = nil,
                drums: [DrumLane: String]? = nil, sound: SoundSettings? = nil) {
        self.role = role
        self.instrument = instrument
        self.melody = melody
        self.chords = chords
        self.drums = drums
        self.sound = sound
    }
}

public struct Clip: Codable, Sendable {
    public let tempo: Double
    public let key: String
    public let bars: Int
    public let parts: [ClipPart]

    public init(tempo: Double, key: String, bars: Int, parts: [ClipPart]) {
        self.tempo = tempo
        self.key = key
        self.bars = bars
        self.parts = parts
    }

    public func makeTrack(name: String) throws -> Track {
        let parsedKey = try Key(parsing: key)
        var madeParts: [Part] = []
        for p in parts {
            let given = [p.melody != nil, p.chords != nil, p.drums != nil].filter { $0 }.count
            guard given == 1 else {
                throw ContentError.invalidClipPart("part '\(p.role.rawValue)' needs exactly one of melody/chords/drums, has \(given)")
            }
            let content: PartContent
            if let m = p.melody {
                content = .notes(try Notation.melody(m))
            } else if let c = p.chords {
                content = .chords(try Notation.chords(c))
            } else {
                var lanes: [DrumLane: [DrumHit]] = [:]
                for (lane, text) in p.drums ?? [:] { lanes[lane] = try Notation.drumLane(text) }
                content = .drums(DrumPattern(lanes: lanes))
            }
            madeParts.append(Part(role: p.role, instrument: p.instrument, content: content,
                                  sound: p.sound ?? SoundSettings()))
        }
        return Track(name: name, createdAt: Date(), tempo: tempo, key: parsedKey, bars: bars, parts: madeParts)
    }
}

public struct Example: Codable, Sendable {
    public let label: String
    public let explanation: String
    public let clip: Clip

    public init(label: String, explanation: String, clip: Clip) {
        self.label = label
        self.explanation = explanation
        self.clip = clip
    }
}

public enum ToolKind: String, Codable, Sendable {
    case trackSetup, melodyEditor, chordPads, chordFinder, drumGrid
}

public enum LessonStep: Codable, Sendable {
    case idea(title: String, body: String, deeper: String?)
    case listen(title: String, caption: String, examples: [Example])
    case task(title: String, prompt: String, tool: ToolKind, targetRole: PartRole?, uses: [PartRole],
              starter: Clip?, checks: [TaskCheck], hints: [String])
    case keep(message: String, roles: [PartRole])
    case koala(body: String)

    private enum Kind: String, Codable { case idea, listen, task, keep, koala }

    private enum CodingKeys: String, CodingKey {
        case type, title, body, deeper, caption, examples, prompt, tool, targetRole, uses, starter, checks, hints
        case message, roles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .idea:
            self = .idea(title: try c.decode(String.self, forKey: .title), body: try c.decode(String.self, forKey: .body),
                         deeper: try c.decodeIfPresent(String.self, forKey: .deeper))
        case .listen:
            self = .listen(title: try c.decode(String.self, forKey: .title), caption: try c.decode(String.self, forKey: .caption),
                           examples: try c.decode([Example].self, forKey: .examples))
        case .task:
            self = .task(title: try c.decode(String.self, forKey: .title), prompt: try c.decode(String.self, forKey: .prompt),
                         tool: try c.decode(ToolKind.self, forKey: .tool),
                         targetRole: try c.decodeIfPresent(PartRole.self, forKey: .targetRole),
                         uses: try c.decodeIfPresent([PartRole].self, forKey: .uses) ?? [],
                         starter: try c.decodeIfPresent(Clip.self, forKey: .starter),
                         checks: try c.decodeIfPresent([TaskCheck].self, forKey: .checks) ?? [],
                         hints: try c.decodeIfPresent([String].self, forKey: .hints) ?? [])
        case .keep:
            self = .keep(message: try c.decode(String.self, forKey: .message),
                         roles: try c.decodeIfPresent([PartRole].self, forKey: .roles) ?? [])
        case .koala:
            self = .koala(body: try c.decode(String.self, forKey: .body))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idea(let title, let body, let deeper):
            try c.encode(Kind.idea, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(body, forKey: .body)
            try c.encodeIfPresent(deeper, forKey: .deeper)
        case .listen(let title, let caption, let examples):
            try c.encode(Kind.listen, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(caption, forKey: .caption)
            try c.encode(examples, forKey: .examples)
        case .task(let title, let prompt, let tool, let targetRole, let uses, let starter, let checks, let hints):
            try c.encode(Kind.task, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(prompt, forKey: .prompt)
            try c.encode(tool, forKey: .tool)
            try c.encodeIfPresent(targetRole, forKey: .targetRole)
            try c.encode(uses, forKey: .uses)
            try c.encodeIfPresent(starter, forKey: .starter)
            try c.encode(checks, forKey: .checks)
            try c.encode(hints, forKey: .hints)
        case .keep(let message, let roles):
            try c.encode(Kind.keep, forKey: .type)
            try c.encode(message, forKey: .message)
            try c.encode(roles, forKey: .roles)
        case .koala(let body):
            try c.encode(Kind.koala, forKey: .type)
            try c.encode(body, forKey: .body)
        }
    }
}

public struct Lesson: Codable, Identifiable, Sendable {
    public let id: String
    public let stage: String
    public let title: String
    public let summary: String
    public let steps: [LessonStep]

    public init(id: String, stage: String, title: String, summary: String, steps: [LessonStep]) {
        self.id = id
        self.stage = stage
        self.title = title
        self.summary = summary
        self.steps = steps
    }
}
