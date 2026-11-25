import Foundation
import MusicCore
import Observation

/// Grid of 16th steps by pitches (two octaves up from `lowestPitch`) over a looping melody.
@Observable
final class PianoRollModel {
    static let pitchCount = 24

    var sequence: NoteSequence
    let bars: Int
    let key: Key
    let lowestPitch: Int
    /// Called after every edit with the new sequence.
    @ObservationIgnored var onChange: ((NoteSequence) -> Void)?

    init(sequence: NoteSequence, bars: Int, key: Key, lowestPitch: Int) {
        self.sequence = sequence
        self.bars = bars
        self.key = key
        self.lowestPitch = lowestPitch
    }

    var steps: Int { bars * 16 }
    var loopTicks: Int { bars * Ticks.perBar }
    var highestPitch: Int { lowestPitch + Self.pitchCount - 1 }

    /// Index of the note that covers the cell, if any.
    func noteIndex(step: Int, pitch: Int) -> Int? {
        let tick = step * Ticks.perSixteenth
        return sequence.notes.firstIndex { $0.pitch == pitch && $0.start <= tick && tick < $0.start + $0.length }
    }

    /// Removes the note covering the cell, or adds a one-step note there.
    func toggle(step: Int, pitch: Int) {
        guard step >= 0, step < steps else { return }
        var notes = sequence.notes
        if let i = noteIndex(step: step, pitch: pitch) {
            notes.remove(at: i)
        } else {
            notes.append(NoteEvent(start: step * Ticks.perSixteenth, length: Ticks.perSixteenth, pitch: pitch, velocity: 0.8))
        }
        commit(notes)
    }

    /// Sets the length of the note covering the cell to `toSteps` steps (at least 1, clipped to the loop end).
    func resize(noteAt step: Int, pitch: Int, toSteps: Int) {
        guard let i = noteIndex(step: step, pitch: pitch) else { return }
        var notes = sequence.notes
        let length = max(1, toSteps) * Ticks.perSixteenth
        notes[i].length = min(length, loopTicks - notes[i].start)
        commit(notes)
    }

    func toggleGlide(step: Int, pitch: Int) {
        guard let i = noteIndex(step: step, pitch: pitch) else { return }
        var notes = sequence.notes
        notes[i].glide.toggle()
        commit(notes)
    }

    /// Adds recorded notes to the melody.
    func merge(_ recorded: NoteSequence) {
        commit(sequence.notes + recorded.notes)
    }

    private func commit(_ notes: [NoteEvent]) {
        sequence = NoteSequence(notes: notes)
        onChange?(sequence)
    }
}
