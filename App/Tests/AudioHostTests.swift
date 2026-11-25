import Testing
import Foundation
import AVFoundation
import UIKit
@testable import Broken

private final class FakeSession: AudioSessionControlling {
    var configureCount = 0
    func configure() throws { configureCount += 1 }
}

private final class FakeEngine: AudioEngineControlling {
    var isRunning = false
    var startCount = 0
    var stopCount = 0
    func start() throws {
        startCount += 1
        isRunning = true
    }
    func stop() {
        stopCount += 1
        isRunning = false
    }
}

private struct Boom: Error {}

/// Starts normally until `failing` is set, then every start throws.
private final class FlakyEngine: AudioEngineControlling {
    var isRunning = false
    var startCount = 0
    var failing = false
    func start() throws {
        startCount += 1
        if failing { throw Boom() }
        isRunning = true
    }
    func stop() { isRunning = false }
}

private func interruption(_ type: AVAudioSession.InterruptionType) -> [AnyHashable: Any] {
    [AVAudioSessionInterruptionTypeKey: type.rawValue]
}

@MainActor
@Test func interruptionEndedRestartsEngine() throws {
    let session = FakeSession()
    let engine = FakeEngine()
    let center = NotificationCenter()
    let host = AudioHost(session: session, makeEngine: { engine }, center: center)
    try host.start()
    #expect(engine.startCount == 1)
    #expect(session.configureCount == 1)

    center.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: interruption(.began))
    engine.isRunning = false  // the system stops the engine during the interruption
    center.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: interruption(.ended))

    #expect(engine.startCount == 2)
    #expect(session.configureCount == 2)
    #expect(host.lastError == nil)
    withExtendedLifetime(host) {}
}

/// Posts `name` with the engine running (left alone), then stopped (full restart: configure + start).
@MainActor
private func expectRestartWhenStopped(after name: Notification.Name) throws {
    let session = FakeSession()
    let engine = FakeEngine()
    let center = NotificationCenter()
    let host = AudioHost(session: session, makeEngine: { engine }, center: center)
    try host.start()

    center.post(name: name, object: nil)
    #expect(engine.startCount == 1, "a running engine is left alone")
    #expect(session.configureCount == 1)

    engine.isRunning = false
    center.post(name: name, object: nil)
    #expect(engine.startCount == 2)
    #expect(session.configureCount == 2, "the session is configured again, in case it was left inactive")
    #expect(engine.isRunning)
    withExtendedLifetime(host) {}
}

@MainActor
@Test func routeChangeRestartsStoppedEngine() throws {
    try expectRestartWhenStopped(after: AVAudioSession.routeChangeNotification)
}

@MainActor
@Test func foregroundRestartsStoppedEngine() throws {
    try expectRestartWhenStopped(after: UIApplication.willEnterForegroundNotification)
}

@MainActor
@Test func engineConfigurationChangeRestartsStoppedEngine() throws {
    try expectRestartWhenStopped(after: .AVAudioEngineConfigurationChange)
}

@MainActor
@Test func interruptionEndedOffMainThreadRestartsOnMainActor() async throws {
    let session = FakeSession()
    let engine = FakeEngine()
    let center = NotificationCenter()
    let host = AudioHost(session: session, makeEngine: { engine }, center: center)
    try host.start()
    engine.isRunning = false

    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async {  // off the main thread: the Task { @MainActor } branch
            center.post(name: AVAudioSession.interruptionNotification, object: nil,
                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
            done.resume()
        }
    }
    // The handler hops to the main actor asynchronously; give it up to 2 s.
    for _ in 0..<200 where engine.startCount < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(engine.startCount == 2)
    #expect(session.configureCount == 2)
    #expect(engine.isRunning)
    withExtendedLifetime(host) {}
}

@MainActor
@Test func mediaResetRebuildsEngine() throws {
    var made: [FakeEngine] = []
    let center = NotificationCenter()
    let host = AudioHost(session: FakeSession(), makeEngine: {
        let e = FakeEngine()
        made.append(e)
        return e
    }, center: center)
    try host.start()
    #expect(made.count == 1)

    center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    #expect(made.count == 2)
    #expect(made[1].isRunning, "the rebuilt engine is started")
    withExtendedLifetime(host) {}
}

@MainActor
@Test func engineIsBuiltAfterSessionIsConfigured() throws {
    let session = FakeSession()
    var configuresBeforeBuild: [Int] = []
    let host = AudioHost(session: session, makeEngine: {
        configuresBeforeBuild.append(session.configureCount)
        return FakeEngine()
    }, center: NotificationCenter())
    #expect(configuresBeforeBuild.isEmpty, "no engine before start: it reads the configured sample rate")
    try host.start()
    #expect(configuresBeforeBuild == [1])
}

@MainActor
@Test func startErrorIsRecordedNotThrownFromNotifications() throws {
    let engine = FlakyEngine()
    let center = NotificationCenter()
    let host = AudioHost(session: FakeSession(), makeEngine: { engine }, center: center)
    try host.start()
    #expect(host.lastError == nil)

    engine.isRunning = false
    engine.failing = true
    center.post(name: AVAudioSession.routeChangeNotification, object: nil)  // must not throw or crash
    #expect(engine.startCount == 2, "the handler attempted a restart")
    #expect(host.lastError != nil, "and recorded its failure")
    withExtendedLifetime(host) {}
}

@MainActor
@Test func audioErrorCanBeDismissed() throws {
    let engine = FlakyEngine()
    engine.failing = true
    let host = AudioHost(session: FakeSession(), makeEngine: { engine }, center: NotificationCenter())
    #expect(throws: Boom.self) { try host.start() }
    #expect(host.lastError != nil)
    host.dismissError()
    #expect(host.lastError == nil)
}

@MainActor
@Test func sessionIsPlaybackCategory() throws {
    let host = AudioHost(session: SystemAudioSession(), makeEngine: { FakeEngine() }, center: NotificationCenter())
    try host.start()
    #expect(host.category == AVAudioSession.Category.playback.rawValue)
    #expect(AVAudioSession.sharedInstance().category == .playback)
    #expect(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers))
}
