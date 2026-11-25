import Foundation

public struct TempoDelay: Sendable {
    private var buffer: [Float]
    private var writeIndex = 0

    public init(maxSeconds: Double = 2, sampleRate: Double) {
        buffer = [Float](repeating: 0, count: max(2, Int(maxSeconds * sampleRate) + 1))
    }

    public mutating func process(_ x: Float, delaySamples: Int, feedback: Float, mix: Float) -> Float {
        let cap = buffer.count
        let d = min(max(delaySamples, 1), cap - 1)
        var readIndex = writeIndex - d
        if readIndex < 0 { readIndex += cap }
        let delayed = buffer[readIndex]
        buffer[writeIndex] = x + delayed * feedback
        writeIndex += 1
        if writeIndex == cap { writeIndex = 0 }
        return x * (1 - mix) + delayed * mix
    }
}
