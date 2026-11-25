import MusicCore

/// Collects live-played notes while the loop runs and turns them into a quantized `NoteSequence`.
struct LiveRecorder {
    private struct Take { var pitch: Int; var on: Int; var off: Int? }
    private var takes: [Take] = []

    mutating func noteOn(pitch: Int, atTick: Int) {
        takes.append(Take(pitch: pitch, on: atTick, off: nil))
    }

    mutating func noteOff(pitch: Int, atTick: Int) {
        guard let i = takes.lastIndex(where: { $0.pitch == pitch && $0.off == nil }) else { return }
        takes[i].off = atTick
    }

    /// Start and end snap to the nearest 16th; length is at least one step. A note released after the loop
    /// wrapped, or still held now, ends at the loop end.
    func result(loopTicks: Int) -> NoteSequence {
        let step = Ticks.perSixteenth
        func snap(_ tick: Int) -> Int { (max(0, tick) + step / 2) / step * step }
        let notes = takes.compactMap { take -> NoteEvent? in
            guard loopTicks >= step else { return nil }
            let rawStart = snap(take.on)
            let rawEnd = take.off.map { off in snap(off < take.on ? off + loopTicks : off) } ?? loopTicks
            let start = rawStart % loopTicks
            let length = max(step, rawEnd - rawStart)
            return NoteEvent(start: start, length: min(length, loopTicks - start), pitch: take.pitch)
        }
        return NoteSequence(notes: notes)
    }
}
