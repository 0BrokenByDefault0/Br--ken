import Testing
import Foundation
@testable import SoundEngine

private let sr = 48_000.0

@Test func adsrTiming() {
    var env = ADSR(attack: 0.01, decay: 0.1, sustain: 0.5, release: 0.2, sampleRate: sr)
    #expect(env.isIdle)
    env.gate(on: true)
    #expect(!env.isIdle)
    var level: Float = 0
    for _ in 0..<5280 { level = env.next() }
    #expect(abs(level - 0.5) < 0.01)
    for _ in 0..<1000 { level = env.next() }
    #expect(abs(level - 0.5) < 0.0001)
    env.gate(on: false)
    var mid: Float = 0
    for i in 0..<9600 {
        let v = env.next()
        if i == 4799 { mid = v }
    }
    #expect(abs(mid - 0.25) < 0.01)
    #expect(env.isIdle)
    #expect(env.next() == 0)
}

@Test func adsrRetriggerContinuesFromCurrentLevel() {
    var env = ADSR(attack: 0.01, decay: 0.1, sustain: 0.5, release: 0.2, sampleRate: sr)
    env.gate(on: true)
    for _ in 0..<5280 { _ = env.next() }
    env.gate(on: false)
    for _ in 0..<2000 { _ = env.next() }
    let before = env.next()
    env.gate(on: true)
    let after = env.next()
    #expect(abs(after - before) < 0.01)
    #expect(after > before)
}

@Test func sawFrequency() {
    var osc = SawOsc(sampleRate: sr)
    let out = (0..<48_000).map { _ in osc.next(frequency: 220) }
    let f = estimatedFrequency(out, sampleRate: sr)
    #expect(abs(f - 220) / 220 < 0.02)
    #expect(peak(out) < 1.2)
}

@Test func sineFrequency() {
    var osc = SineOsc(sampleRate: sr)
    let out = (0..<48_000).map { _ in osc.next(frequency: 440) }
    #expect(abs(estimatedFrequency(out, sampleRate: sr) - 440) < 2)
    #expect(peak(out) <= 1.0001)
}

@Test func lowpassAttenuates() {
    var filter = SVFilter(sampleRate: sr)
    var out: [Float] = []
    var input: [Float] = []
    for n in 0..<24_000 {
        let x = Float(sin(2 * Double.pi * 5000 * Double(n) / sr))
        input.append(x)
        out.append(filter.process(x, cutoff: 500, resonance: 0.2, mode: .lowpass))
    }
    let ratio = rms(out[2000...]) / rms(input[2000...])
    let db = 20 * log10(ratio)
    #expect(db <= -20)
}

@Test func highpassPassesHighAndBlocksLow() {
    var hp = SVFilter(sampleRate: sr)
    var low: [Float] = []
    for n in 0..<24_000 {
        let x = Float(sin(2 * Double.pi * 100 * Double(n) / sr))
        low.append(hp.process(x, cutoff: 3000, resonance: 0.2, mode: .highpass))
    }
    #expect(rms(low[2000...]) < 0.05)
    var high: [Float] = []
    for n in 0..<24_000 {
        let x = Float(sin(2 * Double.pi * 10_000 * Double(n) / sr))
        high.append(hp.process(x, cutoff: 3000, resonance: 0.2, mode: .highpass))
    }
    #expect(rms(high[2000...]) > 0.5)
}

@Test func driveZeroIsIdentity() {
    for x: Float in [-3, -1, -0.3, 0, 0.5, 2.5] {
        #expect(Drive.process(x, amount: 0) == x)
    }
}

@Test func driveBounded() {
    for a: Float in [0.01, 0.25, 0.5, 1] {
        var x: Float = -4
        while x <= 4 {
            #expect(abs(Drive.process(x, amount: a)) <= 1)
            x += 0.05
        }
    }
    #expect(abs(Drive.process(1, amount: 0.5) - 1) < 1e-6)
}

@Test func delayEchoArrives() {
    var delay = TempoDelay(maxSeconds: 2, sampleRate: sr)
    var out: [Float] = []
    for n in 0..<10_000 {
        out.append(delay.process(n == 0 ? 1 : 0, delaySamples: 4800, feedback: 0, mix: 1))
    }
    var best = 0
    for i in out.indices where abs(out[i]) > abs(out[best]) { best = i }
    #expect(best == 4800)
    #expect(abs(out[4800] - 1) < 1e-6)
}

@Test func delayClampsLength() {
    var delay = TempoDelay(maxSeconds: 0.1, sampleRate: 1000)
    var out: [Float] = []
    for n in 0..<500 {
        out.append(delay.process(n == 0 ? 1 : 0, delaySamples: 1_000_000, feedback: 0, mix: 1))
    }
    #expect(allFinite(out))
    #expect(peak(out) > 0.99)
    var tiny = TempoDelay(maxSeconds: 0.1, sampleRate: 1000)
    _ = tiny.process(1, delaySamples: -5, feedback: 0.5, mix: 0.5)
}

@Test func reverbTailDecays() {
    var rev = Reverb(sampleRate: sr)
    var l: [Float] = []
    var r: [Float] = []
    let total = Int(5.2 * sr)
    l.reserveCapacity(total)
    r.reserveCapacity(total)
    for n in 0..<total {
        let o = rev.process(l: n == 0 ? 1 : 0, r: n == 0 ? 1 : 0, mix: 1)
        l.append(o.0)
        r.append(o.1)
    }
    let first = Int(0.1 * sr)
    let start = Int(5.0 * sr)
    #expect(rms(l[0..<first]) > 1e-4)
    #expect(rms(l[start..<(start + first)]) < rms(l[0..<first]) * 0.001)
    #expect(rms(r[start..<(start + first)]) < rms(r[0..<first]) * 0.001)
    #expect(allFinite(l) && allFinite(r))
}

@Test func noiseDeterministic() {
    var a = NoiseGen(seed: 42)
    var b = NoiseGen(seed: 42)
    var c = NoiseGen(seed: 43)
    let xa = (0..<64).map { _ in a.next() }
    let xb = (0..<64).map { _ in b.next() }
    let xc = (0..<64).map { _ in c.next() }
    #expect(xa == xb)
    #expect(xa != xc)
    #expect(xa.allSatisfy { $0 >= -1 && $0 <= 1 })
    var z = NoiseGen(seed: 0)
    #expect((0..<16).map { _ in z.next() }.contains { $0 != 0 })
}

@Test func allOutputsFinite() {
    var env = ADSR(attack: 0, decay: 0, sustain: 1, release: 0, sampleRate: sr)
    var sine = SineOsc(sampleRate: sr)
    var saw = SawOsc(sampleRate: sr)
    var noise = NoiseGen(seed: 7)
    var filter = SVFilter(sampleRate: sr)
    var delay = TempoDelay(maxSeconds: 2, sampleRate: sr)
    var rev = Reverb(sampleRate: sr)
    var out: [Float] = []
    env.gate(on: true)
    for n in 0..<20_000 {
        if n == 10_000 { env.gate(on: false) }
        let f = Float(20 + n % 20_000)
        let x = env.next() * (sine.next(frequency: f) + saw.next(frequency: f) + noise.next())
        let cutoff: Float = n % 2 == 0 ? 1 : 1_000_000
        let y = filter.process(x, cutoff: cutoff, resonance: 1, mode: .bandpass)
        let d = Drive.process(y, amount: 1)
        let e = delay.process(d, delaySamples: 3000, feedback: 0.9, mix: 0.5)
        let (a, b) = rev.process(l: e, r: e, mix: 0.5)
        out.append(a)
        out.append(b)
    }
    #expect(allFinite(out))
}
