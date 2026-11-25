import Foundation
import MusicCore

/// One sounding note. A plain value type with no reference-counted members, so a pool can mutate
/// it in place on the audio thread. Per-voice memory (Karplus-Strong line, drum data) is owned by
/// the pool and only pointed to here.
struct Voice {
    var channel = 0
    var pitch = 0
    var age: UInt64 = 0
    var isFinished = true
    var isReleased = false
    var instrument: InstrumentID = .eight08
    var drumLane = -1

    private let sampleRate: Double
    private let invSampleRate: Double
    private var env: ADSR
    private var gain: Float = 0
    private var samplesSinceStart = 0

    // Oscillators
    private var sine1: SineOsc
    private var sine2: SineOsc
    private var saw1: SawOsc
    private var saw2: SawOsc
    private var saw3: SawOsc
    private var phaseC = 0.0
    private var phaseM1 = 0.0
    private var phaseM2 = 0.0
    private var freq: Double = 440
    private var detune: Float = 1  // pad: ratio of the outer saws

    // 808 pitch (semitones): current, target, per-sample glide step, onset drop
    private var curMidi: Float = 0
    private var targetMidi: Float = 0
    private var glideStep: Float = 0
    private var glideRemaining = 0
    private var drop: Float = 0
    private var dropStep: Float = 0

    // FM
    private var index1: Float = 0
    private var index1Step: Float = 0  // bell: linear; keys: multiplicative decay
    private var index2: Float = 0
    private var index2Mul: Float = 1

    // Karplus-Strong (storage owned by the pool)
    private let ksBuffer: UnsafeMutablePointer<Float>?
    private let ksCapacity: Int
    private var ksLength = 2
    private var ksPos = 0
    private var noise: NoiseGen
    private var autoReleaseAt = Int.max

    // Drum one-shot (storage owned by the pool)
    private var drumData: UnsafeMutablePointer<Float>?
    private var drumCount = 0
    private var drumPos = 0
    private var chokeLeft = 0

    private static let chokeSamples = 240

    init(sampleRate: Double, ksBuffer: UnsafeMutablePointer<Float>?, ksCapacity: Int) {
        self.sampleRate = sampleRate
        invSampleRate = 1 / sampleRate
        self.ksBuffer = ksBuffer
        self.ksCapacity = ksCapacity
        env = ADSR(attack: 0.001, decay: 0, sustain: 1, release: 0.1, sampleRate: sampleRate)
        sine1 = SineOsc(sampleRate: sampleRate)
        sine2 = SineOsc(sampleRate: sampleRate)
        saw1 = SawOsc(sampleRate: sampleRate)
        saw2 = SawOsc(sampleRate: sampleRate)
        saw3 = SawOsc(sampleRate: sampleRate)
        noise = NoiseGen(seed: 1)
    }

    private static func hz(_ midi: Float) -> Double { 440 * exp2((Double(midi) - 69) / 12) }

    /// Starts a pitched note, fully resetting all state (also used when stealing).
    mutating func start(preset: InstrumentPreset, channel: Int, pitch: Int, velocity: Float, age: UInt64) {
        self.channel = channel
        self.pitch = pitch
        self.age = age
        instrument = preset.id
        drumLane = -1
        drumData = nil
        isReleased = false
        isFinished = false
        samplesSinceStart = 0
        autoReleaseAt = Int.max
        chokeLeft = 0
        gain = preset.gain * min(max(velocity, 0), 1)
        env = ADSR(attack: preset.attack, decay: preset.decay, sustain: preset.sustain,
                   release: preset.release, sampleRate: sampleRate)
        env.gate(on: true)
        sine1 = SineOsc(sampleRate: sampleRate)
        sine2 = SineOsc(sampleRate: sampleRate)
        saw1 = SawOsc(sampleRate: sampleRate)
        saw2 = SawOsc(sampleRate: sampleRate)
        saw3 = SawOsc(sampleRate: sampleRate)
        phaseC = 0
        phaseM1 = 0
        phaseM2 = 0
        curMidi = Float(pitch)
        targetMidi = curMidi
        glideRemaining = 0
        glideStep = 0
        drop = preset.dropSemitones
        dropStep = preset.dropSemitones > 0
            ? preset.dropSemitones / Float(max(1, preset.dropSeconds * sampleRate)) : 0
        freq = Self.hz(curMidi + drop)

        detune = Float(exp2(7.0 / 1200))

        switch preset.id {
        case .bell:
            autoReleaseAt = Int(2.6 * sampleRate)  // sustain 0: let it ring out, then free the voice
            index1 = 4
            index1Step = 4 / Float(sampleRate)  // 4 -> 0 over 1 s
        case .keys:
            index1 = 1.2
            index1Step = Float(exp(-1.5 * invSampleRate))  // body index: slow decay
            index2 = 2.5
            index2Mul = Float(exp(-25 * invSampleRate))  // tine index: ~40 ms
        case .pluck:
            startKarplusStrong()
            autoReleaseAt = Int(4 * sampleRate)
        default:
            break
        }
    }

    mutating func startDrum(lane: Int, data: UnsafeMutablePointer<Float>, count: Int,
                            channel: Int, pitch: Int, velocity: Float, gain: Float, age: UInt64) {
        self.channel = channel
        self.pitch = pitch
        self.age = age
        instrument = .trapKit
        drumLane = lane
        drumData = data
        drumCount = count
        drumPos = 0
        chokeLeft = 0
        isReleased = false
        isFinished = false
        samplesSinceStart = 0
        self.gain = gain * min(max(velocity, 0), 1)
    }

    private mutating func startKarplusStrong() {
        guard let buf = ksBuffer else { return }
        let period = sampleRate / Self.hz(Float(pitch))
        ksLength = min(max(2, Int((period - 0.5).rounded())), ksCapacity)  // averaging adds half a sample
        ksPos = 0
        noise = NoiseGen(seed: UInt64(truncatingIfNeeded: pitch) &* 0x9E37 &+ 0x1234_5678)
        for i in 0..<ksLength { buf[i] = noise.next() }
    }

    mutating func release() {
        guard !isFinished, !isReleased else { return }
        isReleased = true
        if drumData != nil {
            if chokeLeft == 0 { chokeLeft = Self.chokeSamples }
        } else {
            env.gate(on: false)
        }
    }

    /// Fast fade-out for a drum voice (choke / stop).
    mutating func choke() {
        guard !isFinished, drumData != nil else { return }
        isReleased = true
        if chokeLeft == 0 { chokeLeft = Self.chokeSamples }
    }

    /// 808 glide: slide the current pitch to `newPitch` over the glide time.
    mutating func retune(to newPitch: Int, glideSeconds: Double) {
        pitch = newPitch
        targetMidi = Float(newPitch)
        glideRemaining = max(1, Int(glideSeconds * sampleRate))
        glideStep = (targetMidi - curMidi) / Float(glideRemaining)
    }

    mutating func nextSample() -> Float {
        if isFinished { return 0 }
        samplesSinceStart += 1

        if let data = drumData {
            var g = gain
            if chokeLeft > 0 {
                g *= Float(chokeLeft) / Float(Self.chokeSamples)
                chokeLeft -= 1
                if chokeLeft == 0 { isFinished = true }
            }
            let out = data[drumPos] * g
            drumPos += 1
            if drumPos >= drumCount { isFinished = true }
            return out
        }

        if samplesSinceStart == autoReleaseAt { release() }
        let e = env.next()
        var s: Float = 0
        switch instrument {
        case .eight08: s = nextEight08()
        case .bell: s = nextBell()
        case .pluck: s = nextPluck()
        case .pad: s = nextPad()
        case .keys: s = nextKeys()
        case .trapKit: break
        }
        if env.isIdle { isFinished = true }
        return s * e * gain
    }

    private mutating func nextEight08() -> Float {
        var changed = false
        if glideRemaining > 0 {
            glideRemaining -= 1
            curMidi = glideRemaining == 0 ? targetMidi : curMidi + glideStep
            changed = true
        }
        if drop > 0 {
            drop = max(0, drop - dropStep)
            changed = true
        }
        if changed { freq = Self.hz(curMidi + drop) }
        let f = Float(freq)
        return (sine1.next(frequency: f) + 0.1 * sine2.next(frequency: 2 * f)) / 1.1
    }

    private mutating func nextBell() -> Float {
        let tau = 2 * Double.pi
        let out = sin(tau * phaseC + Double(index1) * sin(tau * phaseM1))
        phaseC += freq * invSampleRate
        phaseM1 += freq * 3.5 * invSampleRate
        phaseC -= phaseC.rounded(.down)
        phaseM1 -= phaseM1.rounded(.down)
        index1 = max(0, index1 - index1Step)
        return Float(out)
    }

    private mutating func nextKeys() -> Float {
        let tau = 2 * Double.pi
        let mod = Double(index1) * sin(tau * phaseM1) + Double(index2) * sin(tau * phaseM2)
        let out = sin(tau * phaseC + mod)
        phaseC += freq * invSampleRate
        phaseM1 += freq * invSampleRate
        phaseM2 += freq * 14 * invSampleRate
        phaseC -= phaseC.rounded(.down)
        phaseM1 -= phaseM1.rounded(.down)
        phaseM2 -= phaseM2.rounded(.down)
        index1 *= index1Step
        index2 *= index2Mul
        return Float(out)
    }

    private mutating func nextPad() -> Float {
        let f = Float(freq)
        let up = detune
        let down = 1 / up
        return (saw1.next(frequency: f * down) + saw2.next(frequency: f) + saw3.next(frequency: f * up)) / 3
    }

    private mutating func nextPluck() -> Float {
        guard let buf = ksBuffer else { return 0 }
        let next = ksPos + 1 == ksLength ? 0 : ksPos + 1
        let out = buf[ksPos]
        buf[ksPos] = 0.5 * (out + buf[next]) * 0.997
        ksPos = next
        return out
    }
}
