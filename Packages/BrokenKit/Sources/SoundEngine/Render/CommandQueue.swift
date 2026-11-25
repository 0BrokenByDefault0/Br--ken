import Foundation
import MusicCore
import Synchronization

public enum EngineCommand: Equatable, Sendable {
    case play(fromTick: Int)
    case stop
    /// Live play: instrument, MIDI pitch, velocity 0...1.
    case noteOn(InstrumentID, Int, Float)
    case noteOff(InstrumentID, Int)
}

/// Lock-free single-producer / single-consumer ring buffer. The producer (main thread) only calls
/// `push`, the consumer (render thread) only calls `pop`; neither ever blocks or allocates.
/// `head` and `tail` are monotonically increasing counters; a slot is written before `tail` is
/// published (release) and read after `tail` is observed (acquire), and vice versa for `head`.
public final class CommandQueue: @unchecked Sendable {
    public static let capacity = 256

    private let slots: UnsafeMutablePointer<EngineCommand>
    private let head = Atomic<Int>(0)  // next slot to read; written by the consumer
    private let tail = Atomic<Int>(0)  // next slot to write; written by the producer

    public init() {
        slots = .allocate(capacity: Self.capacity)
        slots.initialize(repeating: .stop, count: Self.capacity)
    }

    deinit {
        slots.deinitialize(count: Self.capacity)
        slots.deallocate()
    }

    /// Returns false (and drops the command) when the queue is full.
    @discardableResult
    public func push(_ command: EngineCommand) -> Bool {
        let t = tail.load(ordering: .relaxed)
        if t - head.load(ordering: .acquiring) >= Self.capacity { return false }
        slots[t % Self.capacity] = command
        tail.store(t + 1, ordering: .releasing)
        return true
    }

    public func pop() -> EngineCommand? {
        let h = head.load(ordering: .relaxed)
        if h == tail.load(ordering: .acquiring) { return nil }
        let command = slots[h % Self.capacity]
        head.store(h + 1, ordering: .releasing)
        return command
    }
}
