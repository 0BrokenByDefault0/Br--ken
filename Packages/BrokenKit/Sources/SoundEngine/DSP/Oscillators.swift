import Foundation

public struct SineOsc: Sendable {
    private var phase = 0.0
    private let invSampleRate: Double

    public init(sampleRate: Double) { invSampleRate = 1 / sampleRate }

    public mutating func next(frequency: Float) -> Float {
        let out = Float(sin(2 * Double.pi * phase))
        phase += Double(frequency) * invSampleRate
        phase -= phase.rounded(.down)
        return out
    }
}

/// Band-limited sawtooth (PolyBLEP).
public struct SawOsc: Sendable {
    private var phase = 0.0
    private let invSampleRate: Double

    public init(sampleRate: Double) { invSampleRate = 1 / sampleRate }

    public mutating func next(frequency: Float) -> Float {
        let dt = min(max(Double(frequency) * invSampleRate, 0), 0.5)
        var out = 2 * phase - 1
        if dt > 0 {
            if phase < dt {
                let x = phase / dt
                out -= x + x - x * x - 1
            } else if phase > 1 - dt {
                let x = (phase - 1) / dt
                out -= x * x + x + x + 1
            }
        }
        phase += dt
        phase -= phase.rounded(.down)
        return Float(out)
    }
}

/// Deterministic white noise (xorshift64*), output in [-1, 1].
public struct NoiseGen: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func next() -> Float {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let r = state &* 2_685_821_657_736_338_717
        return Float(r >> 40) / 8_388_607.5 - 1
    }

    public mutating func next(frequency: Float) -> Float { next() }
}
