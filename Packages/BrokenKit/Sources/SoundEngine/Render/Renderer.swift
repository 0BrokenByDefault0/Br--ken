import Foundation
import MusicCore
import Synchronization

/// Sample-accurate sequencer and mixer: plays a `PlaybackSnapshot` in a loop plus live notes.
///
/// Threading contract (this is why `@unchecked Sendable` is sound):
/// - `setSnapshot` and `send` are called from a single producer thread (the main thread).
///   `setSnapshot` touches only `exchange` (a `Mutex`); `send` touches only `commands` (an SPSC queue).
/// - `render` is called from a single consumer thread (the audio render thread). Every other stored
///   property (voice pool, effects, sequencer state, scratch buffers) belongs to that thread alone.
///   It takes the pending snapshot with `withLockIfAvailable`, so it never waits for the main thread.
/// - `playheadTick` and `isPlaying` are published through atomics and can be read from any thread.
/// - `render` never allocates: buffers are allocated in `init`, and a replaced snapshot is parked in
///   `exchange` so that its memory is freed on the main thread by the next `setSnapshot`.
public final class Renderer: @unchecked Sendable {
    public let sampleRate: Double

    static let maxBlock = 4096
    static let partChannels = PlaybackSnapshot.maxParts  // channels 0...7
    static let liveChannel = 8
    static let channelCount = 9
    /// Sounding sequenced notes tracked per part channel (for their note-offs).
    static let maxHeld = 64
    static let delayFeedback: Float = 0.35

    private struct Exchange {
        var pending: PlaybackSnapshot?
        var retired: PlaybackSnapshot?
    }

    /// Per-channel effect settings, clamped to 0...1 and mapped once per snapshot.
    private struct ChannelParams {
        var volume: Float
        var drive: Float
        var cutoffHz: Float
        var delayMix: Float
        var reverbSend: Float

        init(_ s: SoundSettings) {
            func unit(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0 }
            volume = Float(unit(s.volume))
            drive = Float(unit(s.drive))
            cutoffHz = Float(200 * pow(90, unit(s.cutoff)))  // 200 Hz ... 18 kHz, exponential
            delayMix = Float(unit(s.delay))
            reverbSend = Float(unit(s.reverb))
        }
    }

    private struct ChannelFX {
        var filter: SVFilter
        var delay: TempoDelay
    }

    // Shared with the main thread.
    private let exchange = Mutex(Exchange(pending: nil, retired: nil))
    private let commands = CommandQueue()
    private let publishedTick = Atomic<Int>(0)
    private let publishedPlaying = Atomic<Bool>(false)

    // Render-thread state.
    private let pool: VoicePool
    private var snapshot: PlaybackSnapshot?
    private var tempo = 120.0
    private var loopTicks = Ticks.perBar
    private var delaySamples = 1
    private var playing = false
    /// Sample position on the absolute-tick timeline: tick `t` sounds at `onsetSample(t)`.
    private var clock = 0
    /// Next absolute tick to dispatch; every earlier tick has been dispatched.
    private var nextTick = 0
    /// Per part channel: index of the first event not yet passed in the current loop pass.
    private let cursors: UnsafeMutablePointer<Int>
    private let heldPitch: UnsafeMutablePointer<Int>
    private let heldEnd: UnsafeMutablePointer<Int>
    private let heldCount: UnsafeMutablePointer<Int>
    private let params: UnsafeMutablePointer<ChannelParams>
    private let fx: UnsafeMutablePointer<ChannelFX>
    private let reverb: UnsafeMutablePointer<Reverb>
    private let scratch: UnsafeMutablePointer<Float>  // channelCount x maxBlock
    private let dryBus: UnsafeMutablePointer<Float>
    private let sendBus: UnsafeMutablePointer<Float>

    /// A `sampleRate` that is not positive and finite falls back to 48 000 Hz, so timing stays well-defined
    /// (the dispatch loop could otherwise never reach the end of a block).
    public init(sampleRate requested: Double) {
        let sampleRate = requested.isFinite && requested > 0 ? requested : 48_000
        self.sampleRate = sampleRate
        pool = VoicePool(maxVoices: 32, sampleRate: sampleRate)
        let channels = Self.channelCount
        cursors = .allocate(capacity: Self.partChannels)
        cursors.initialize(repeating: 0, count: Self.partChannels)
        heldPitch = .allocate(capacity: Self.partChannels * Self.maxHeld)
        heldPitch.initialize(repeating: 0, count: Self.partChannels * Self.maxHeld)
        heldEnd = .allocate(capacity: Self.partChannels * Self.maxHeld)
        heldEnd.initialize(repeating: 0, count: Self.partChannels * Self.maxHeld)
        heldCount = .allocate(capacity: Self.partChannels)
        heldCount.initialize(repeating: 0, count: Self.partChannels)
        params = .allocate(capacity: channels)
        params.initialize(repeating: ChannelParams(SoundSettings()), count: channels)
        fx = .allocate(capacity: channels)
        for ch in 0..<channels {
            (fx + ch).initialize(to: ChannelFX(filter: SVFilter(sampleRate: sampleRate),
                                               delay: TempoDelay(maxSeconds: 2.5, sampleRate: sampleRate)))
        }
        reverb = .allocate(capacity: 1)
        reverb.initialize(to: Reverb(sampleRate: sampleRate))
        scratch = .allocate(capacity: channels * Self.maxBlock)
        scratch.initialize(repeating: 0, count: channels * Self.maxBlock)
        dryBus = .allocate(capacity: Self.maxBlock)
        dryBus.initialize(repeating: 0, count: Self.maxBlock)
        sendBus = .allocate(capacity: Self.maxBlock)
        sendBus.initialize(repeating: 0, count: Self.maxBlock)
        delaySamples = dottedEighthSamples()
    }

    deinit {
        cursors.deallocate()
        heldPitch.deallocate()
        heldEnd.deallocate()
        heldCount.deallocate()
        params.deallocate()
        fx.deinitialize(count: Self.channelCount)
        fx.deallocate()
        reverb.deinitialize(count: 1)
        reverb.deallocate()
        scratch.deallocate()
        dryBus.deallocate()
        sendBus.deallocate()
    }

    // MARK: Main thread

    /// Queues `s`; the render thread picks it up at the start of its next block.
    public func setSnapshot(_ s: PlaybackSnapshot) {
        let replaced = exchange.withLock { x -> (PlaybackSnapshot?, PlaybackSnapshot?) in
            let garbage = (x.pending, x.retired)
            x.pending = s
            x.retired = nil
            return garbage
        }
        _ = replaced  // released here, outside the lock, on this thread
    }

    /// Queues a command for the next render block. Returns false (command dropped) if 256 are already waiting.
    @discardableResult
    public func send(_ c: EngineCommand) -> Bool {
        commands.push(c)
    }

    /// Playhead position within the loop (0..<loopTicks), as of the last rendered block.
    public var playheadTick: Int { publishedTick.load(ordering: .relaxed) }

    public var isPlaying: Bool { publishedPlaying.load(ordering: .relaxed) }

    /// Tests only: reads render-thread state, so call it only while nothing is rendering.
    var activeVoiceCount: Int { pool.activeCount }

    // MARK: Render thread

    /// Writes `frames` stereo samples (always within -1...1).
    public func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        takePendingSnapshot()
        while let c = commands.pop() { apply(c) }
        var done = 0
        while done < frames {
            let n = min(Self.maxBlock, frames - done)
            renderChunk(frames: n, left: left + done, right: right + done)
            done += n
        }
        publishedPlaying.store(playing, ordering: .relaxed)
        if playing { publishedTick.store(loopPosition(), ordering: .relaxed) }
    }

    private func takePendingSnapshot() {
        let old = snapshot
        let taken = exchange.withLockIfAvailable { x -> PlaybackSnapshot? in
            guard x.retired == nil, let s = x.pending else { return nil }
            x.pending = nil
            x.retired = old  // freed later by setSnapshot, off the render thread
            return s
        }
        if let s = taken ?? nil { apply(s) }
    }

    private func apply(_ new: PlaybackSnapshot) {
        for ch in 0..<Self.partChannels {
            let newPart: PartPlayback? = ch < new.parts.count ? new.parts[ch] : nil
            if let old = snapshot, ch < old.parts.count {
                let oldPart = old.parts[ch]
                let changed = newPart.map {
                    $0.instrument != oldPart.instrument || $0.events != oldPart.events || ($0.muted && !oldPart.muted)
                } ?? true
                if changed { releaseChannel(ch) }
            }
            params[ch] = ChannelParams(newPart?.sound ?? SoundSettings())
            cursors[ch] = 0  // re-found from the playhead at the next tick
        }
        let newTempo = new.tempo.isFinite ? min(max(new.tempo, 20), 999) : 120
        if playing && newTempo != tempo {
            // Keep the playhead's tick position; re-express it in samples at the new tempo.
            let tick = Double(clock) * tempo * Double(Ticks.perQuarter) / (sampleRate * 60)
            clock = Int((tick * sampleRate * 60 / (newTempo * Double(Ticks.perQuarter))).rounded())
        }
        tempo = newTempo
        let newLoop = max(1, new.loopTicks)
        if playing {
            // Rebase onto the new loop so the playhead keeps its loop position (or restarts at 0 if that
            // position is past the new loop end), keeping the sub-tick offset to the next tick.
            let p = nextTick % loopTicks
            let rebased = p < newLoop ? p : 0
            let offset = clock - onsetSample(nextTick)
            let shift = rebased - nextTick
            for ch in 0..<Self.partChannels {
                for j in 0..<heldCount[ch] { heldEnd[ch * Self.maxHeld + j] += shift }
            }
            nextTick = rebased
            clock = onsetSample(rebased) + offset
        }
        loopTicks = newLoop
        delaySamples = dottedEighthSamples()
        snapshot = new
    }

    private func apply(_ c: EngineCommand) {
        switch c {
        case .play(let fromTick):
            for ch in 0..<Self.partChannels {
                releaseChannel(ch)
                cursors[ch] = 0
            }
            nextTick = max(0, fromTick) % loopTicks
            clock = onsetSample(nextTick)
            playing = true
        case .stop:
            playing = false
            pool.releaseAll(channel: nil)
            for ch in 0..<Self.partChannels { heldCount[ch] = 0 }
        case .noteOn(let instrument, let pitch, let velocity):
            pool.noteOn(channel: Self.liveChannel, instrument: instrument, pitch: pitch, velocity: velocity, glide: false)
        case .noteOff(_, let pitch):
            pool.noteOff(channel: Self.liveChannel, pitch: pitch)
        }
    }

    private func releaseChannel(_ ch: Int) {
        pool.releaseAll(channel: ch)
        heldCount[ch] = 0
    }

    /// `round(tick × sampleRate × 60 / (tempo × 96))`, from the absolute tick every time.
    private func onsetSample(_ tick: Int) -> Int {
        Int((Double(tick) * sampleRate * 60 / (tempo * Double(Ticks.perQuarter))).rounded())
    }

    private func loopPosition() -> Int {
        let tick = Int((Double(clock) * tempo * Double(Ticks.perQuarter) / (sampleRate * 60)).rounded(.down))
        return ((tick % loopTicks) + loopTicks) % loopTicks
    }

    /// Dotted 1/8 = 0.75 beat at the current tempo.
    private func dottedEighthSamples() -> Int {
        max(1, Int((0.75 * 60 / tempo * sampleRate).rounded()))
    }

    private func renderChunk(frames n: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        for ch in 0..<Self.channelCount { (scratch + ch * Self.maxBlock).update(repeating: 0, count: n) }
        var pos = 0
        if playing {
            let end = clock + n
            while true {
                let onset = onsetSample(nextTick)
                if onset >= end { break }
                let at = max(0, onset - clock)
                if at > pos {
                    renderVoices(from: pos, to: at)
                    pos = at
                }
                dispatch(tick: nextTick)
                nextTick += 1
            }
            clock = end
        }
        renderVoices(from: pos, to: n)
        mix(frames: n, left: left, right: right)
    }

    /// Every channel renders every block, so voices always advance and free their slots.
    private func renderVoices(from: Int, to: Int) {
        let count = to - from
        guard count > 0 else { return }
        for ch in 0..<Self.channelCount {
            pool.render(channel: ch, frames: count, into: scratch + ch * Self.maxBlock + from)
        }
    }

    /// Fires the events at absolute tick `a`. Per channel, in this order: (a) 808 glide note-ons, so a glide
    /// retunes the previous note before that note's note-off can release it; (b) note-offs due now, and at
    /// the loop wrap every note still sounding; (c) the other note-ons, after the note-offs, so a repeated
    /// pitch is not cut by the previous note's note-off.
    private func dispatch(tick a: Int) {
        let p = a % loopTicks
        for ch in 0..<Self.partChannels {
            var part: PartPlayback?
            if let s = snapshot, ch < s.parts.count { part = s.parts[ch] }
            let events = part?.events ?? []
            var first = 0
            var last = 0
            if part != nil {
                var c = p == 0 ? 0 : cursors[ch]
                while c < events.count && events[c].start < p { c += 1 }
                first = c
                while c < events.count && events[c].start == p { c += 1 }
                last = c
                cursors[ch] = c
            }
            let plays = part.map { !$0.muted } ?? false
            let glides = plays && part?.instrument == .eight08

            if glides {  // (a)
                for i in first..<last where events[i].glide {
                    pool.noteOn(channel: ch, instrument: .eight08, pitch: events[i].pitch,
                                velocity: events[i].velocity, glide: true)
                }
            }

            var j = 0  // (b)
            while j < heldCount[ch] {
                let k = ch * Self.maxHeld + j
                guard p == 0 || heldEnd[k] <= a else {
                    j += 1
                    continue
                }
                let pitch = heldPitch[k]
                var glidedInto = false  // a glide to the same pitch carries this voice on
                if glides {
                    for i in first..<last where events[i].glide && events[i].pitch == pitch { glidedInto = true }
                }
                if !glidedInto { pool.noteOff(channel: ch, pitch: pitch) }
                removeHeld(ch, j)
            }

            guard plays else { continue }
            for i in first..<last {  // (c)
                let e = events[i]
                if !(glides && e.glide) {
                    pool.noteOn(channel: ch, instrument: part!.instrument, pitch: e.pitch,
                                velocity: e.velocity, glide: false)
                }
                hold(ch, pitch: e.pitch, end: a + max(1, e.end - e.start))
            }
        }
    }

    private func hold(_ ch: Int, pitch: Int, end: Int) {
        if heldCount[ch] == Self.maxHeld {  // full: end the first tracked note early rather than lose it
            pool.noteOff(channel: ch, pitch: heldPitch[ch * Self.maxHeld])
            removeHeld(ch, 0)
        }
        let k = ch * Self.maxHeld + heldCount[ch]
        heldPitch[k] = pitch
        heldEnd[k] = end
        heldCount[ch] += 1
    }

    private func removeHeld(_ ch: Int, _ j: Int) {
        let base = ch * Self.maxHeld
        let lastIndex = heldCount[ch] - 1
        heldPitch[base + j] = heldPitch[base + lastIndex]
        heldEnd[base + j] = heldEnd[base + lastIndex]
        heldCount[ch] = lastIndex
    }

    /// Per channel: volume → drive → lowpass → tempo delay → dry (centre) + reverb send.
    /// Then the shared reverb and a tanh soft clip per output channel.
    private func mix(frames n: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        dryBus.update(repeating: 0, count: n)
        sendBus.update(repeating: 0, count: n)
        let delay = delaySamples
        for ch in 0..<Self.channelCount {
            let p = params[ch]
            let buf = scratch + ch * Self.maxBlock
            let chain = fx + ch
            for i in 0..<n {
                var x = buf[i] * p.volume
                x = Drive.process(x, amount: p.drive)
                x = chain.pointee.filter.process(x, cutoff: p.cutoffHz, resonance: 0, mode: .lowpass)
                x = chain.pointee.delay.process(x, delaySamples: delay, feedback: Self.delayFeedback, mix: p.delayMix)
                dryBus[i] += x
                sendBus[i] += x * p.reverbSend
            }
        }
        for i in 0..<n {
            let (wetL, wetR) = reverb.pointee.process(l: sendBus[i], r: sendBus[i], mix: 1)
            left[i] = Self.softClip(dryBus[i] + wetL)
            right[i] = Self.softClip(dryBus[i] + wetR)
        }
    }

    private static func softClip(_ x: Float) -> Float {
        let y = tanh(x)
        return y.isFinite ? min(max(y, -1), 1) : 0
    }
}
