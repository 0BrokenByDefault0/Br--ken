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

private final class FailingEngine: AudioEngineControlling {
    var isRunning = false
    func start() throws { throw Boom() }
    func stop() {}
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

@MainActor
@Test func routeChangeRestartsStoppedEngine() throws {
    let engine = FakeEngine()
    let center = NotificationCenter()
    let host = AudioHost(session: FakeSession(), makeEngine: { engine }, center: center)
    try host.start()

    center.post(name: AVAudioSession.routeChangeNotification, object: nil)
    #expect(engine.startCount == 1, "a running engine is left alone")

    engine.isRunning = false
    center.post(name: AVAudioSession.routeChangeNotification, object: nil)
    #expect(engine.startCount == 2)
    #expect(engine.isRunning)
    withExtendedLifetime(host) {}
}

@MainActor
@Test func foregroundRestartsStoppedEngine() throws {
    let engine = FakeEngine()
    let center = NotificationCenter()
    let host = AudioHost(session: FakeSession(), makeEngine: { engine }, center: center)
    try host.start()
    engine.isRunning = false
    center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    #expect(engine.startCount == 2)
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
@Test func startErrorIsRecordedNotThrownFromNotifications() throws {
    let center = NotificationCenter()
    let host = AudioHost(session: FakeSession(), makeEngine: { FailingEngine() }, center: center)
    #expect(throws: Boom.self) { try host.start() }
    center.post(name: AVAudioSession.routeChangeNotification, object: nil)
    #expect(host.lastError != nil)
    withExtendedLifetime(host) {}
}

@MainActor
@Test func sessionIsPlaybackCategory() throws {
    let host = AudioHost(session: SystemAudioSession(), makeEngine: { FakeEngine() }, center: NotificationCenter())
    try host.start()
    #expect(host.category == AVAudioSession.Category.playback.rawValue)
    #expect(AVAudioSession.sharedInstance().category == .playback)
    #expect(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers))
}
