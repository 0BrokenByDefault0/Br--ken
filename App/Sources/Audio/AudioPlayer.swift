import AVFoundation
import MusicCore
import SoundEngine

/// Plays tracks and live notes. Everything runs on the main thread; nothing here waits on audio.
@MainActor
protocol AudioPlaying: AnyObject {
    func setTrack(_ t: Track)
    func play()
    func stop()
    func noteOn(_ i: InstrumentID, _ pitch: Int, _ vel: Float)
    func noteOff(_ i: InstrumentID, _ pitch: Int)
    var playheadTick: Int { get }
    var isPlaying: Bool { get }
    /// How far the playhead runs ahead of what is heard, in ticks at the current track's tempo.
    var latencyTicks: Int { get }
}

/// `AudioPlaying` over a `Renderer`. The renderer comes from the current audio engine; when the engine
/// is rebuilt, `attach` hands over the new renderer, the current track is sent to it again, and a loop
/// that was playing resumes, so the app's play state stays true.
@MainActor
final class AudioPlayer: AudioPlaying {
    private var renderer: Renderer?
    private var snapshot: PlaybackSnapshot?
    /// True between `play()` and `stop()`.
    private var shouldPlay = false
    private var tempo = 0.0
    private let latencySeconds: () -> Double

    /// `latencySeconds`: the output latency plus the IO buffer duration (the audio session's by default).
    init(renderer: Renderer? = nil, latencySeconds: @escaping () -> Double = AudioPlayer.sessionLatency) {
        self.renderer = renderer
        self.latencySeconds = latencySeconds
    }

    nonisolated static func sessionLatency() -> Double {
        let session = AVAudioSession.sharedInstance()
        return session.outputLatency + session.ioBufferDuration
    }

    func attach(_ renderer: Renderer) {
        self.renderer = renderer
        if let snapshot { renderer.setSnapshot(snapshot) }
        // A rebuilt engine starts stopped: resume the loop that was playing.
        if shouldPlay { renderer.send(.play(fromTick: 0)) }
    }

    func setTrack(_ t: Track) {
        let s = PlaybackSnapshot(track: t)
        snapshot = s
        tempo = Renderer.clampedTempo(t.tempo)
        renderer?.setSnapshot(s)
    }

    func play() {
        shouldPlay = true
        renderer?.send(.play(fromTick: 0))
    }

    func stop() {
        shouldPlay = false
        renderer?.send(.stop)
    }

    /// Sent synchronously (no async hop) to keep keyboard latency low.
    func noteOn(_ i: InstrumentID, _ pitch: Int, _ vel: Float) {
        renderer?.send(.noteOn(i, pitch, vel))
    }

    func noteOff(_ i: InstrumentID, _ pitch: Int) {
        renderer?.send(.noteOff(i, pitch))
    }

    var playheadTick: Int { renderer?.playheadTick ?? 0 }

    var isPlaying: Bool { renderer?.isPlaying ?? false }

    var latencyTicks: Int { LatencyCompensation.ticks(seconds: latencySeconds(), tempo: tempo) }
}
