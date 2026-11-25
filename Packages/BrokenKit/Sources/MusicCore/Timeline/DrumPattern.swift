public enum DrumLane: String, Codable, CaseIterable, Sendable {
    case kick, snare, clap, closedHat, openHat, rim, perc

    public var midiNote: Int {
        switch self {
        case .kick: 36
        case .rim: 37
        case .snare: 38
        case .clap: 39
        case .closedHat: 42
        case .perc: 45
        case .openHat: 46
        }
    }
}

public struct DrumHit: Hashable, Codable, Sendable {
    public var tick: Int
    public var velocity: Float
    public var pitchOffset: Int

    public init(tick: Int, velocity: Float, pitchOffset: Int = 0) {
        self.tick = tick
        self.velocity = velocity
        self.pitchOffset = pitchOffset
    }
}

/// Raw value = ticks between hits.
public enum RollRate: Int, Codable, CaseIterable, Sendable {
    case sixteenthTriplet = 16
    case thirtySecond = 12
    case thirtySecondTriplet = 8
    case sixtyFourth = 6
}

public struct DrumPattern: Hashable, Codable, Sendable {
    /// Each lane's hits are kept sorted by tick.
    public var lanes: [DrumLane: [DrumHit]]
    /// 0...0.6. Applied only when a snapshot is built (`swungTick`); stored ticks stay on the grid.
    public var swing: Double = 0

    public init(lanes: [DrumLane: [DrumHit]]) {
        self.lanes = lanes.mapValues { $0.sorted { $0.tick < $1.tick } }
    }

    private enum CodingKeys: String, CodingKey { case lanes, swing }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(lanes: try container.decode([DrumLane: [DrumHit]].self, forKey: .lanes))
        swing = try container.decodeIfPresent(Double.self, forKey: .swing) ?? 0
    }

    /// Off-beat 16ths (`tick % 48 == 24`) move later by `round(swing * 12)` ticks; other ticks are unchanged.
    public func swungTick(_ tick: Int) -> Int {
        guard tick % 48 == 24 else { return tick }
        return tick + Int((swing * 12).rounded())
    }

    /// Toggles a 0.8-velocity hit on the 16th grid.
    public mutating func toggle(lane: DrumLane, step: Int) {
        let tick = step * Ticks.perSixteenth
        var hits = lanes[lane, default: []]
        if let index = hits.firstIndex(where: { $0.tick == tick }) {
            hits.remove(at: index)
        } else {
            hits.append(DrumHit(tick: tick, velocity: 0.8))
            hits.sort { $0.tick < $1.tick }
        }
        lanes[lane] = hits
    }

    /// Replaces the lane's hits in `[from, to)` with a roll; velocities interpolate linearly from first to last hit.
    public mutating func fillRoll(lane: DrumLane, from: Int, to: Int, rate: RollRate, velocities: ClosedRange<Float>) {
        var hits = lanes[lane, default: []].filter { $0.tick < from || $0.tick >= to }
        let ticks = Array(stride(from: from, to: to, by: rate.rawValue))
        for (i, tick) in ticks.enumerated() {
            let t: Float = ticks.count > 1 ? Float(i) / Float(ticks.count - 1) : 0
            let velocity = velocities.lowerBound + (velocities.upperBound - velocities.lowerBound) * t
            hits.append(DrumHit(tick: tick, velocity: velocity))
        }
        hits.sort { $0.tick < $1.tick }
        lanes[lane] = hits
    }
}

/// Lets `[DrumLane: T]` encode as a JSON object keyed by lane name.
extension DrumLane: CodingKeyRepresentable {}
