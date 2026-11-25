import Foundation

public enum FilterMode: Sendable {
    case lowpass, highpass, bandpass
}

/// Zero-delay-feedback state-variable filter (TPT topology), stable under modulation.
public struct SVFilter: Sendable {
    private var ic1: Float = 0
    private var ic2: Float = 0
    private let sampleRate: Double

    public init(sampleRate: Double) { self.sampleRate = sampleRate }

    public mutating func process(_ x: Float, cutoff: Float, resonance: Float, mode: FilterMode) -> Float {
        let fc = min(max(Double(cutoff), 20), 0.45 * sampleRate)
        let g = Float(tan(Double.pi * fc / sampleRate))
        let r = min(max(resonance, 0), 1)
        let k = 2 - 1.9 * r  // k >= 0.1: strongly resonant but never self-oscillating
        let a1 = 1 / (1 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        switch mode {
        case .lowpass: return v2
        case .bandpass: return v1
        case .highpass: return x - k * v1 - v2
        }
    }
}
