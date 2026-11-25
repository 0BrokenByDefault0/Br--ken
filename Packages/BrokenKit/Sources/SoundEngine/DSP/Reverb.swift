import Foundation

/// Freeverb topology: 8 parallel damped combs into 4 series allpasses per channel.
public struct Reverb: Sendable {
    /// 0...1, maps to comb feedback 0.7...0.98.
    public var roomSize: Float = 0.5
    /// 0...1 high-frequency damping inside the combs.
    public var damping: Float = 0.5

    private struct Comb: Sendable {
        var buffer: [Float]
        var index = 0
        var store: Float = 0
        init(length: Int) { buffer = [Float](repeating: 0, count: max(1, length)) }

        mutating func process(_ input: Float, feedback: Float, damp: Float) -> Float {
            let out = buffer[index]
            store = out * (1 - damp) + store * damp
            if abs(store) < 1e-20 { store = 0 }  // flush denormals
            buffer[index] = input + store * feedback
            index += 1
            if index == buffer.count { index = 0 }
            return out
        }
    }

    private struct Allpass: Sendable {
        var buffer: [Float]
        var index = 0
        init(length: Int) { buffer = [Float](repeating: 0, count: max(1, length)) }

        mutating func process(_ input: Float) -> Float {
            let held = buffer[index]
            let out = held - input
            buffer[index] = input + held * 0.5
            index += 1
            if index == buffer.count { index = 0 }
            return out
        }
    }

    private static let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private static let allpassTunings = [556, 441, 341, 225]
    private static let stereoSpread = 23
    private static let inputGain: Float = 0.015

    private var combsL: [Comb]
    private var combsR: [Comb]
    private var allpassL: [Allpass]
    private var allpassR: [Allpass]

    public init(sampleRate: Double) {
        let scale = sampleRate / 44_100
        func scaled(_ n: Int) -> Int { max(1, Int((Double(n) * scale).rounded())) }
        combsL = Self.combTunings.map { Comb(length: scaled($0)) }
        combsR = Self.combTunings.map { Comb(length: scaled($0 + Self.stereoSpread)) }
        allpassL = Self.allpassTunings.map { Allpass(length: scaled($0)) }
        allpassR = Self.allpassTunings.map { Allpass(length: scaled($0 + Self.stereoSpread)) }
    }

    public mutating func process(l: Float, r: Float, mix: Float) -> (Float, Float) {
        let feedback = min(max(roomSize, 0), 1) * 0.28 + 0.7
        let damp = min(max(damping, 0), 1) * 0.4
        let input = (l + r) * Self.inputGain
        var wetL: Float = 0
        var wetR: Float = 0
        for i in combsL.indices {
            wetL += combsL[i].process(input, feedback: feedback, damp: damp)
            wetR += combsR[i].process(input, feedback: feedback, damp: damp)
        }
        for i in allpassL.indices {
            wetL = allpassL[i].process(wetL)
            wetR = allpassR[i].process(wetR)
        }
        return (l * (1 - mix) + wetL * mix, r * (1 - mix) + wetR * mix)
    }
}
