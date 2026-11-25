public enum TaskCheck: Hashable, Codable, Sendable {
    case tempoInRange(min: Double, max: Double)
    case inKey(role: PartRole)
    case noteCount(role: PartRole, min: Int, max: Int?)
    case barRhythmRepeats(role: PartRole)
    case endsOnDegree(role: PartRole, degrees: [Int])
    case chordCount(role: PartRole, min: Int, max: Int?)
    case chordsInKey(role: PartRole)
    case chordDegrees(role: PartRole, required: [Int])
    case chordsFitMelody(chords: PartRole, melody: PartRole, minScoreRatio: Double)
    case extendedChordCount(role: PartRole, min: Int)
    case drumHitOnBeats(lane: DrumLane, beats: [Int], everyBar: Bool)
    case laneHitCount(lane: DrumLane, min: Int)
    case hatRollPresent
    case syncopatedKicks(min: Int)
    case barsDiffer(role: PartRole)

    private enum Kind: String, Codable {
        case tempoInRange, inKey, noteCount, barRhythmRepeats, endsOnDegree, chordCount, chordsInKey
        case chordDegrees, chordsFitMelody, extendedChordCount, drumHitOnBeats, laneHitCount
        case hatRollPresent, syncopatedKicks, barsDiffer
    }

    private enum CodingKeys: String, CodingKey {
        case kind, role, min, max, degrees, required, chords, melody, minScoreRatio, lane, beats, everyBar
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .tempoInRange:
            self = .tempoInRange(min: try c.decode(Double.self, forKey: .min), max: try c.decode(Double.self, forKey: .max))
        case .inKey:
            self = .inKey(role: try c.decode(PartRole.self, forKey: .role))
        case .noteCount:
            self = .noteCount(role: try c.decode(PartRole.self, forKey: .role), min: try c.decode(Int.self, forKey: .min),
                              max: try c.decodeIfPresent(Int.self, forKey: .max))
        case .barRhythmRepeats:
            self = .barRhythmRepeats(role: try c.decode(PartRole.self, forKey: .role))
        case .endsOnDegree:
            self = .endsOnDegree(role: try c.decode(PartRole.self, forKey: .role), degrees: try c.decode([Int].self, forKey: .degrees))
        case .chordCount:
            self = .chordCount(role: try c.decode(PartRole.self, forKey: .role), min: try c.decode(Int.self, forKey: .min),
                               max: try c.decodeIfPresent(Int.self, forKey: .max))
        case .chordsInKey:
            self = .chordsInKey(role: try c.decode(PartRole.self, forKey: .role))
        case .chordDegrees:
            self = .chordDegrees(role: try c.decode(PartRole.self, forKey: .role), required: try c.decode([Int].self, forKey: .required))
        case .chordsFitMelody:
            self = .chordsFitMelody(chords: try c.decode(PartRole.self, forKey: .chords),
                                    melody: try c.decode(PartRole.self, forKey: .melody),
                                    minScoreRatio: try c.decode(Double.self, forKey: .minScoreRatio))
        case .extendedChordCount:
            self = .extendedChordCount(role: try c.decode(PartRole.self, forKey: .role), min: try c.decode(Int.self, forKey: .min))
        case .drumHitOnBeats:
            self = .drumHitOnBeats(lane: try c.decode(DrumLane.self, forKey: .lane), beats: try c.decode([Int].self, forKey: .beats),
                                   everyBar: try c.decode(Bool.self, forKey: .everyBar))
        case .laneHitCount:
            self = .laneHitCount(lane: try c.decode(DrumLane.self, forKey: .lane), min: try c.decode(Int.self, forKey: .min))
        case .hatRollPresent:
            self = .hatRollPresent
        case .syncopatedKicks:
            self = .syncopatedKicks(min: try c.decode(Int.self, forKey: .min))
        case .barsDiffer:
            self = .barsDiffer(role: try c.decode(PartRole.self, forKey: .role))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tempoInRange(let lo, let hi):
            try c.encode(Kind.tempoInRange, forKey: .kind)
            try c.encode(lo, forKey: .min)
            try c.encode(hi, forKey: .max)
        case .inKey(let role):
            try c.encode(Kind.inKey, forKey: .kind)
            try c.encode(role, forKey: .role)
        case .noteCount(let role, let lo, let hi):
            try c.encode(Kind.noteCount, forKey: .kind)
            try c.encode(role, forKey: .role)
            try c.encode(lo, forKey: .min)
            try c.encodeIfPresent(hi, forKey: .max)
        case .barRhythmRepeats(let role):
            try c.encode(Kind.barRhythmRepeats, forKey: .kind)
            try c.encode(role, forKey: .role)
        case .endsOnDegree(let role, let degrees):
            try c.encode(Kind.endsOnDegree, forKey: .kind)
            try c.encode(role, forKey: .role)
            try c.encode(degrees, forKey: .degrees)
        case .chordCount(let role, let lo, let hi):
            try c.encode(Kind.chordCount, forKey: .kind)
            try c.encode(role, forKey: .role)
            try c.encode(lo, forKey: .min)
            try c.encodeIfPresent(hi, forKey: .max)
        case .chordsInKey(let role):
            try c.encode(Kind.chordsInKey, forKey: .kind)
            try c.encode(role, forKey: .role)
        case .chordDegrees(let role, let required):
            try c.encode(Kind.chordDegrees, forKey: .kind)
            try c.encode(role, forKey: .role)
            try c.encode(required, forKey: .required)
        case .chordsFitMelody(let chords, let melody, let ratio):
            try c.encode(Kind.chordsFitMelody, forKey: .kind)
            try c.encode(chords, forKey: .chords)
            try c.encode(melody, forKey: .melody)
            try c.encode(ratio, forKey: .minScoreRatio)
        case .extendedChordCount(let role, let lo):
            try c.encode(Kind.extendedChordCount, forKey: .kind)
            try c.encode(role, forKey: .role)
            try c.encode(lo, forKey: .min)
        case .drumHitOnBeats(let lane, let beats, let everyBar):
            try c.encode(Kind.drumHitOnBeats, forKey: .kind)
            try c.encode(lane, forKey: .lane)
            try c.encode(beats, forKey: .beats)
            try c.encode(everyBar, forKey: .everyBar)
        case .laneHitCount(let lane, let lo):
            try c.encode(Kind.laneHitCount, forKey: .kind)
            try c.encode(lane, forKey: .lane)
            try c.encode(lo, forKey: .min)
        case .hatRollPresent:
            try c.encode(Kind.hatRollPresent, forKey: .kind)
        case .syncopatedKicks(let lo):
            try c.encode(Kind.syncopatedKicks, forKey: .kind)
            try c.encode(lo, forKey: .min)
        case .barsDiffer(let role):
            try c.encode(Kind.barsDiffer, forKey: .kind)
            try c.encode(role, forKey: .role)
        }
    }
}

public struct CheckResult: Hashable, Sendable {
    public let check: TaskCheck
    public let passed: Bool
    public let message: String

    public init(check: TaskCheck, passed: Bool, message: String) {
        self.check = check
        self.passed = passed
        self.message = message
    }
}
