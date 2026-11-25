import MusicCore

/// The playhead runs ahead of what the owner hears by the output latency plus one IO buffer. Live-recorded
/// notes are stamped at the heard position, so a note played on the beat lands on the beat.
enum LatencyCompensation {
    /// `seconds` of latency as ticks at `tempo` BPM (96 ticks per beat), rounded; never negative.
    static func ticks(seconds: Double, tempo: Double) -> Int {
        guard seconds.isFinite, seconds > 0, tempo.isFinite, tempo > 0 else { return 0 }
        return Int((seconds * tempo / 60 * Double(Ticks.perQuarter)).rounded())
    }

    /// The loop position the owner hears when the playhead is at `playhead`: `latency` ticks earlier,
    /// wrapped within the loop.
    static func heardTick(playhead: Int, latency: Int, loopTicks: Int) -> Int {
        guard loopTicks > 0 else { return playhead }
        return ((playhead - latency) % loopTicks + loopTicks) % loopTicks
    }
}
