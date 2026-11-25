import Foundation

func rms(_ x: ArraySlice<Float>) -> Double {
    guard !x.isEmpty else { return 0 }
    var sum = 0.0
    for v in x { sum += Double(v) * Double(v) }
    return (sum / Double(x.count)).squareRoot()
}

func rms(_ x: [Float]) -> Double { rms(x[...]) }

func peak(_ x: [Float]) -> Float {
    var p: Float = 0
    for v in x { p = max(p, abs(v)) }
    return p
}

func allFinite(_ x: [Float]) -> Bool {
    for v in x where !v.isFinite { return false }
    return true
}

/// Frequency estimated from positive-going zero crossings (linear interpolation).
func estimatedFrequency(_ samples: [Float], sampleRate: Double) -> Double {
    var crossings: [Double] = []
    if samples.count > 1 {
        for i in 1..<samples.count where samples[i - 1] < 0 && samples[i] >= 0 {
            let a = Double(samples[i - 1]), b = Double(samples[i])
            crossings.append(Double(i - 1) + (-a) / (b - a))
        }
    }
    guard crossings.count >= 2, let first = crossings.first, let last = crossings.last else { return 0 }
    return Double(crossings.count - 1) / (last - first) * sampleRate
}
