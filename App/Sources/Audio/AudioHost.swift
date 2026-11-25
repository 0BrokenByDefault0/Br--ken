import AVFoundation
import Observation
import UIKit

/// Sets up the shared audio session.
protocol AudioSessionControlling {
    func configure() throws
}

/// Something that can be started and stopped, such as an `AVAudioEngine` wrapper.
protocol AudioEngineControlling: AnyObject {
    var isRunning: Bool { get }
    func start() throws
    func stop()
}

/// The real session: `.playback` (sounds with the silent switch on), mixing with other apps such as
/// Koala, with a 5 ms IO buffer for low keyboard latency.
struct SystemAudioSession: AudioSessionControlling {
    func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }
}

/// Owns the audio engine and keeps it running: after an interruption (a call, Siri), a route change,
/// a media-services reset, or returning to the foreground, audio comes back without a relaunch.
/// Failures never crash; the latest one is shown through `lastError`.
@Observable @MainActor
final class AudioHost {
    private(set) var lastError: String?

    private let session: AudioSessionControlling
    private let makeEngine: @MainActor () -> AudioEngineControlling
    @ObservationIgnored private var engine: AudioEngineControlling
    private let observers: NotificationObservers

    private enum Event: Sendable {
        case interruptionEnded
        case shouldBeRunning
        case mediaServicesReset
    }

    init(session: AudioSessionControlling, makeEngine: @escaping @MainActor () -> AudioEngineControlling,
         center: NotificationCenter = .default) {
        self.session = session
        self.makeEngine = makeEngine
        engine = makeEngine()
        observers = NotificationObservers(center: center)

        observe(AVAudioSession.interruptionNotification) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return nil }
            return .interruptionEnded
        }
        observe(AVAudioSession.routeChangeNotification) { _ in .shouldBeRunning }
        observe(UIApplication.willEnterForegroundNotification) { _ in .shouldBeRunning }
        observe(AVAudioSession.mediaServicesWereResetNotification) { _ in .mediaServicesReset }
    }

    /// The audio session's current category (for tests and diagnostics).
    var category: String { AVAudioSession.sharedInstance().category.rawValue }

    /// Configures the session and starts the engine. A failure is also recorded in `lastError`.
    func start() throws {
        try record {
            try session.configure()
            try engine.start()
        }
    }

    private func handle(_ event: Event) {
        switch event {
        case .interruptionEnded:
            // Restart even without `.shouldResume`: the owner wants sound back.
            try? start()
        case .shouldBeRunning:
            guard !engine.isRunning else { return }
            try? record { try engine.start() }
        case .mediaServicesReset:
            // Every audio object is invalid after a reset: build a fresh engine (and renderer).
            engine.stop()
            engine = makeEngine()
            try? start()
        }
    }

    private func record(_ body: () throws -> Void) throws {
        do {
            try body()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Notifications may arrive on any thread; they are handled on the main actor, synchronously when
    /// already on the main thread.
    private func observe(_ name: Notification.Name, _ event: @escaping @Sendable (Notification) -> Event?) {
        observers.add(name) { [weak self] note in
            guard let e = event(note) else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.handle(e) }
            } else {
                Task { @MainActor in self?.handle(e) }
            }
        }
    }
}

/// Closure-based observer tokens, removed when the owner goes away.
private final class NotificationObservers: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter) {
        self.center = center
    }

    /// Call only during the owner's setup, on one thread.
    func add(_ name: Notification.Name, _ block: @escaping @Sendable (Notification) -> Void) {
        tokens.append(center.addObserver(forName: name, object: nil, queue: nil, using: block))
    }

    deinit {
        for token in tokens { center.removeObserver(token) }
    }
}
