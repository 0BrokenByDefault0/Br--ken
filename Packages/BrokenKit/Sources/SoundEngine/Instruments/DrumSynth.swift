import Foundation
import MusicCore

/// Builds one-shot drum buffers. Called once at engine init, never on the render path.
public enum DrumSynth {
    public static func render(_ lane: DrumLane, sampleRate: Double) -> [Float] {
        switch lane {
        case .kick: return kick(sampleRate)
        case .snare: return snare(sampleRate)
        case .clap: return clap(sampleRate)
        case .closedHat: return hat(sampleRate, seconds: 0.04, decay: 0.01, seed: 11)
        case .openHat: return hat(sampleRate, seconds: 0.3, decay: 0.08, seed: 12)
        case .rim: return rim(sampleRate)
        case .perc: return perc(sampleRate)
        }
    }

    private static func count(_ seconds: Double, _ sr: Double) -> Int { max(1, Int((seconds * sr).rounded())) }

    /// Fades the last 2 ms to zero (no end click) and scales the peak to `target`.
    private static func finish(_ x: inout [Float], sampleRate: Double, target: Float) {
        let fade = min(x.count, max(1, Int(0.002 * sampleRate)))
        for i in 0..<fade { x[x.count - 1 - i] *= Float(i) / Float(fade) }
        var p: Float = 0
        for v in x { p = max(p, abs(v)) }
        if p > 0 {
            let g = target / p
            for i in x.indices { x[i] *= g }
        }
    }

    private static func kick(_ sr: Double) -> [Float] {
        let n = count(0.45, sr)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        let sweep = 0.04
        for i in 0..<n {
            let t = Double(i) / sr
            let f = t < sweep ? 150 - 100 * (t / sweep) : 50
            let env = exp(-6.9 * t / 0.45)
            out[i] = Float(sin(2 * Double.pi * phase) * env)
            phase += f / sr
        }
        finish(&out, sampleRate: sr, target: 0.9)
        return out
    }

    private static func snare(_ sr: Double) -> [Float] {
        let n = count(0.2, sr)
        var out = [Float](repeating: 0, count: n)
        var noise = NoiseGen(seed: 7)
        var bp = SVFilter(sampleRate: sr)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let tone = sin(2 * Double.pi * phase) * exp(-t / 0.05)
            phase += 180 / sr
            let nz = bp.process(noise.next(), cutoff: 2200, resonance: 0.3, mode: .bandpass)
            out[i] = Float(tone) * 0.6 + nz * Float(exp(-t / 0.06)) * 1.5
        }
        finish(&out, sampleRate: sr, target: 0.9)
        return out
    }

    private static func clap(_ sr: Double) -> [Float] {
        let n = count(0.02 + 0.15, sr)
        var out = [Float](repeating: 0, count: n)
        var noise = NoiseGen(seed: 9)
        var bp = SVFilter(sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let env: Double
            if t < 0.02 {
                env = exp(-(t.truncatingRemainder(dividingBy: 0.01)) / 0.003)  // bursts at 0 and 10 ms
            } else {
                env = exp(-(t - 0.02) / 0.04)  // third burst at 20 ms rings out as the tail
            }
            out[i] = bp.process(noise.next(), cutoff: 1300, resonance: 0.4, mode: .bandpass) * Float(env)
        }
        finish(&out, sampleRate: sr, target: 0.9)
        return out
    }

    private static func hat(_ sr: Double, seconds: Double, decay: Double, seed: UInt64) -> [Float] {
        let n = count(seconds, sr)
        var out = [Float](repeating: 0, count: n)
        var noise = NoiseGen(seed: seed)
        var hp = SVFilter(sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            out[i] = hp.process(noise.next(), cutoff: 7000, resonance: 0.2, mode: .highpass) * Float(exp(-t / decay))
        }
        finish(&out, sampleRate: sr, target: 0.6)
        return out
    }

    private static func rim(_ sr: Double) -> [Float] {
        let n = count(0.03, sr)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            out[i] = Float(sin(2 * Double.pi * 800 * t) * exp(-t / 0.006))
        }
        finish(&out, sampleRate: sr, target: 0.9)
        return out
    }

    private static func perc(_ sr: Double) -> [Float] {
        let n = count(0.3, sr)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let f = 140 * (1 + 0.3 * exp(-t / 0.015))  // settles at 140 Hz
            out[i] = Float(sin(2 * Double.pi * phase) * exp(-t / 0.08))
            phase += f / sr
        }
        finish(&out, sampleRate: sr, target: 0.9)
        return out
    }
}

/// All drum one-shots in unmanaged memory, owned by the voice pool and freed in `deinit`,
/// so the render path never touches array reference counts.
final class DrumBank {
    let laneCount: Int
    let notes: UnsafeMutablePointer<Int>
    let data: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    let lengths: UnsafeMutablePointer<Int>
    let closedHatIndex: Int
    let openHatIndex: Int

    init(sampleRate: Double) {
        let lanes = DrumLane.allCases
        laneCount = lanes.count
        notes = .allocate(capacity: lanes.count)
        data = .allocate(capacity: lanes.count)
        lengths = .allocate(capacity: lanes.count)
        for (i, lane) in lanes.enumerated() {
            let buf = DrumSynth.render(lane, sampleRate: sampleRate)
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, buf.count))
            p.initialize(repeating: 0, count: max(1, buf.count))
            for j in buf.indices { p[j] = buf[j] }
            notes[i] = lane.midiNote
            data[i] = p
            lengths[i] = buf.count
        }
        closedHatIndex = lanes.firstIndex(of: .closedHat) ?? -1
        openHatIndex = lanes.firstIndex(of: .openHat) ?? -1
    }

    deinit {
        for i in 0..<laneCount { data[i].deallocate() }
        notes.deallocate()
        data.deallocate()
        lengths.deallocate()
    }

    func laneIndex(midiNote: Int) -> Int? {
        for i in 0..<laneCount where notes[i] == midiNote { return i }
        return nil
    }
}
