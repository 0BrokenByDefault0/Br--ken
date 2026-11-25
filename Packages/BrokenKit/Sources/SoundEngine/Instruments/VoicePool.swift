import Foundation
import MusicCore

/// Fixed-capacity polyphonic voice allocator. Everything is allocated in `init`; `noteOn`,
/// `noteOff` and `render` never allocate, so they are safe on the audio thread.
/// Not thread-safe: the owner serialises calls (the renderer drives it from one thread).
/// Channels are part indices 0-7 plus 8 for live play.
public final class VoicePool {
    public let maxVoices: Int
    public let sampleRate: Double

    private let voices: UnsafeMutablePointer<Voice>
    private let ksBuffers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let drums: DrumBank
    private var nextAge: UInt64 = 0

    /// Level of drum one-shots (buffers are normalised below 1).
    private static let drumGain: Float = 0.5

    public init(maxVoices: Int = 32, sampleRate: Double) {
        self.maxVoices = max(1, maxVoices)
        self.sampleRate = sampleRate
        let ksCapacity = max(4096, Int(sampleRate / 20) + 2)
        voices = .allocate(capacity: self.maxVoices)
        ksBuffers = .allocate(capacity: self.maxVoices)
        for i in 0..<self.maxVoices {
            let buf = UnsafeMutablePointer<Float>.allocate(capacity: ksCapacity)
            buf.initialize(repeating: 0, count: ksCapacity)
            ksBuffers[i] = buf
            (voices + i).initialize(to: Voice(sampleRate: sampleRate, ksBuffer: buf, ksCapacity: ksCapacity))
        }
        drums = DrumBank(sampleRate: sampleRate)
    }

    deinit {
        for i in 0..<maxVoices { ksBuffers[i].deallocate() }
        voices.deinitialize(count: maxVoices)
        voices.deallocate()
        ksBuffers.deallocate()
    }

    public var activeCount: Int {
        var n = 0
        for i in 0..<maxVoices where !voices[i].isFinished { n += 1 }
        return n
    }

    public func noteOn(channel: Int, instrument: InstrumentID, pitch: Int, velocity: Float, glide: Bool) {
        if instrument == .trapKit {
            guard let lane = drums.laneIndex(midiNote: pitch) else { return }
            if lane == drums.closedHatIndex {
                for i in 0..<maxVoices where !voices[i].isFinished
                    && voices[i].channel == channel && voices[i].drumLane == drums.openHatIndex {
                    voices[i].choke()
                }
            }
            let slot = freeSlot()
            nextAge &+= 1
            voices[slot].startDrum(lane: lane, data: drums.data[lane], count: drums.lengths[lane],
                                   channel: channel, pitch: pitch, velocity: velocity,
                                   gain: Self.drumGain, age: nextAge)
            return
        }

        let preset = InstrumentPreset.make(instrument)  // plain value, no allocation

        if glide && instrument == .eight08, let v = newestSounding(channel: channel, instrument: .eight08) {
            voices[v].retune(to: pitch, glideSeconds: preset.glideSeconds)
            return
        }

        let slot = freeSlot()
        nextAge &+= 1
        voices[slot].start(preset: preset, channel: channel, pitch: pitch, velocity: velocity, age: nextAge)
    }

    public func noteOff(channel: Int, pitch: Int) {
        for i in 0..<maxVoices where !voices[i].isFinished && !voices[i].isReleased
            && voices[i].channel == channel && voices[i].pitch == pitch && voices[i].instrument != .trapKit {
            voices[i].release()
        }
    }

    /// Releases pitched voices (drums are faded out quickly). `nil` = every channel.
    public func releaseAll(channel: Int?) {
        for i in 0..<maxVoices where !voices[i].isFinished && (channel == nil || voices[i].channel == channel!) {
            voices[i].release()
        }
    }

    /// Adds the channel's voices into `into` (the caller zeroes it).
    public func render(channel: Int, frames: Int, into: UnsafeMutablePointer<Float>) {
        for v in 0..<maxVoices where !voices[v].isFinished && voices[v].channel == channel {
            for i in 0..<frames {
                into[i] += voices[v].nextSample()
                if voices[v].isFinished { break }
            }
        }
    }

    // MARK: Allocation

    /// A finished slot, else the oldest released voice, else the oldest voice.
    private func freeSlot() -> Int {
        var oldestReleased = -1
        var oldest = 0
        for i in 0..<maxVoices {
            if voices[i].isFinished { return i }
            if voices[i].isReleased && (oldestReleased < 0 || voices[i].age < voices[oldestReleased].age) {
                oldestReleased = i
            }
            if voices[i].age < voices[oldest].age { oldest = i }
        }
        return oldestReleased >= 0 ? oldestReleased : oldest
    }

    private func newestSounding(channel: Int, instrument: InstrumentID) -> Int? {
        var best = -1
        for i in 0..<maxVoices where !voices[i].isFinished && !voices[i].isReleased
            && voices[i].channel == channel && voices[i].instrument == instrument {
            if best < 0 || voices[i].age > voices[best].age { best = i }
        }
        return best >= 0 ? best : nil
    }
}
