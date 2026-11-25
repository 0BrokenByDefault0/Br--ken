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
}

/// `AudioPlaying` over a `Renderer`. The renderer comes from the current audio engine; when the engine
/// is rebuilt, `attach` hands over the new renderer and the current track is sent to it again.
@MainActor
final class AudioPlayer: AudioPlaying {
    private var renderer: Renderer?
    private var snapshot: PlaybackSnapshot?

    init(renderer: Renderer? = nil) {
        self.renderer = renderer
    }

    func attach(_ renderer: Renderer) {
        self.renderer = renderer
        if let snapshot { renderer.setSnapshot(snapshot) }
    }

    func setTrack(_ t: Track) {
        let s = PlaybackSnapshot(track: t)
        snapshot = s
        renderer?.setSnapshot(s)
    }

    func play() {
        renderer?.send(.play(fromTick: 0))
    }

    func stop() {
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
}
