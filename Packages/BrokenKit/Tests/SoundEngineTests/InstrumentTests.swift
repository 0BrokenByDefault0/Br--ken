import Testing
import Foundation
import MusicCore
@testable import SoundEngine

private let sr = 48_000.0

private func frames(_ seconds: Double) -> Int { Int(seconds * sr) }

/// Renders `count` frames of `channel` into a fresh zeroed array.
private func render(_ pool: VoicePool, channel: Int = 0, count: Int) -> [Float] {
    var out = [Float](repeating: 0, count: count)
    out.withUnsafeMutableBufferPointer { pool.render(channel: channel, frames: count, into: $0.baseAddress!) }
    return out
}

private func window(_ x: [Float], from a: Double, to b: Double) -> [Float] {
    Array(x[frames(a)..<min(x.count, frames(b))])
}

@Test func eight08Pitch() {
    let pool = VoicePool(sampleRate: sr)
    pool.noteOn(channel: 0, instrument: .eight08, pitch: 33, velocity: 1, glide: false)
    let out = render(pool, count: frames(0.25))
    let f = estimatedFrequency(window(out, from: 0.05, to: 0.25), sampleRate: sr)
    #expect(abs(f - 55) / 55 < 0.03)
}

@Test func glideMovesPitch() {
    let pool = VoicePool(sampleRate: sr)
    pool.noteOn(channel: 0, instrument: .eight08, pitch: 33, velocity: 1, glide: false)
    _ = render(pool, count: frames(0.1))
    pool.noteOn(channel: 0, instrument: .eight08, pitch: 45, velocity: 1, glide: true)
    let out = render(pool, count: frames(0.1))
    let f = estimatedFrequency(window(out, from: 0.005, to: 0.055), sampleRate: sr)
    #expect(f > 55 && f < 110)
    #expect(pool.activeCount == 1)
}

@Test func glideUpdatesPitchKey() {
    let pool = VoicePool(sampleRate: sr)
    pool.noteOn(channel: 0, instrument: .eight08, pitch: 33, velocity: 1, glide: false)
    _ = render(pool, count: frames(0.1))
    pool.noteOn(channel: 0, instrument: .eight08, pitch: 45, velocity: 1, glide: true)
    _ = render(pool, count: frames(0.1))
    pool.noteOff(channel: 0, pitch: 45)
    _ = render(pool, count: frames(0.3))
    #expect(pool.activeCount == 0)
}

@Test func voiceCapAndStealing() {
    let pool = VoicePool(sampleRate: sr)
    let melodic: [InstrumentID] = [.eight08, .bell, .pluck, .pad, .keys]
    var all: [Float] = []
    for i in 0..<200 {
        pool.noteOn(channel: i % 3, instrument: melodic[i % melodic.count], pitch: 40 + i % 30,
                    velocity: 1, glide: false)
        #expect(pool.activeCount <= 32)
        for ch in 0..<3 { all += render(pool, channel: ch, count: 64) }
    }
    #expect(pool.activeCount <= 32)
    #expect(allFinite(all))
}

@Test func releaseAllSilences() {
    let pool = VoicePool(sampleRate: sr)
    for (i, inst) in InstrumentID.allCases.enumerated() {
        let pitch = inst == .trapKit ? DrumLane.kick.midiNote : 55 + i
        pool.noteOn(channel: 0, instrument: inst, pitch: pitch, velocity: 1, glide: false)
    }
    _ = render(pool, count: frames(0.3))
    pool.releaseAll(channel: nil)
    _ = render(pool, count: frames(2))
    let tail = render(pool, count: 4800)
    #expect(peak(tail) < 1e-4)
    #expect(pool.activeCount == 0)
}

@Test func kickIsLow() {
    let kick = DrumSynth.render(.kick, sampleRate: sr)
    let f = estimatedFrequency(Array(kick[frames(0.05)..<frames(0.25)]), sampleRate: sr)
    #expect(f > 0 && f < 120)
}

@Test func everyPresetProducesSound() {
    for inst in InstrumentID.allCases {
        let pool = VoicePool(sampleRate: sr)
        // trapKit only responds to drum-lane notes; 60 is not one.
        let pitch = inst == .trapKit ? DrumLane.kick.midiNote : 60
        pool.noteOn(channel: 0, instrument: inst, pitch: pitch, velocity: 1, glide: false)
        let out = render(pool, count: frames(0.1))
        #expect(peak(out) > 0.05, "\(inst)")
        #expect(peak(out) <= 0.6, "\(inst)")
        #expect(allFinite(out))
    }
}

@Test func trapKitIgnoresNonLanePitch() {
    let pool = VoicePool(sampleRate: sr)
    pool.noteOn(channel: 0, instrument: .trapKit, pitch: 60, velocity: 1, glide: false)
    #expect(pool.activeCount == 0)
}

@Test func closedHatChokesOpenHat() {
    let pool = VoicePool(sampleRate: sr)
    pool.noteOn(channel: 0, instrument: .trapKit, pitch: DrumLane.openHat.midiNote, velocity: 1, glide: false)
    _ = render(pool, count: 480)
    pool.noteOn(channel: 0, instrument: .trapKit, pitch: DrumLane.closedHat.midiNote, velocity: 1, glide: false)
    #expect(pool.activeCount == 2)
    _ = render(pool, count: 960)
    #expect(pool.activeCount == 1)
}

@Test func velocityScalesLinearly() {
    func peakAt(_ v: Float) -> Float {
        let pool = VoicePool(sampleRate: sr)
        pool.noteOn(channel: 0, instrument: .trapKit, pitch: DrumLane.snare.midiNote, velocity: v, glide: false)
        return peak(render(pool, count: frames(0.1)))
    }
    #expect(abs(peakAt(0.5) / peakAt(1) - 0.5) < 0.01)
}

@Test func renderIsPerChannel() {
    let pool = VoicePool(sampleRate: sr)
    pool.noteOn(channel: 2, instrument: .bell, pitch: 72, velocity: 1, glide: false)
    #expect(peak(render(pool, channel: 0, count: 2400)) == 0)
    #expect(peak(render(pool, channel: 2, count: 2400)) > 0.05)
}
