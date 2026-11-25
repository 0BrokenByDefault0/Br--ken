public struct NoteEvent: Hashable, Codable, Sendable {
    public var start: Int
    public var length: Int
    public var pitch: Int
    public var velocity: Float
    public var glide: Bool

    public init(start: Int, length: Int, pitch: Int, velocity: Float = 0.8, glide: Bool = false) {
        self.start = start
        self.length = length
        self.pitch = pitch
        self.velocity = velocity
        self.glide = glide
    }
}

public struct NoteSequence: Hashable, Codable, Sendable {
    /// Sorted by start.
    public var notes: [NoteEvent]

    public init(notes: [NoteEvent]) {
        self.notes = notes.sorted { $0.start < $1.start }
    }

    private enum CodingKeys: String, CodingKey { case notes }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(notes: try container.decode([NoteEvent].self, forKey: .notes))
    }

    /// Notes whose `[start, start + length)` intersects `range`.
    public func notes(overlapping range: Range<Int>) -> [NoteEvent] {
        notes.filter { $0.start < range.upperBound && $0.start + $0.length > range.lowerBound }
    }
}
