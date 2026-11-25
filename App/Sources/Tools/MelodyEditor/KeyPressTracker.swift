/// Which keys are held. Every note-on has exactly one matching note-off: `release` reports a pitch only
/// if it was held, and `releaseAll` hands back everything still held (octave change, disappear, cancel).
struct KeyPressTracker {
    private(set) var held: Set<Int> = []

    /// True if the pitch was not already held (so the caller should send note-on).
    mutating func press(_ pitch: Int) -> Bool { held.insert(pitch).inserted }

    /// True if the pitch was held (so the caller should send note-off).
    mutating func release(_ pitch: Int) -> Bool { held.remove(pitch) != nil }

    /// The pitches that need a note-off now.
    mutating func releaseAll() -> [Int] {
        defer { held.removeAll() }
        return held.sorted()
    }

    func isHeld(_ pitch: Int) -> Bool { held.contains(pitch) }
}
