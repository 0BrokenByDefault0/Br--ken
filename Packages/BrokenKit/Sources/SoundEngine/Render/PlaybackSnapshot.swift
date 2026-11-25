import Foundation
import MusicCore

/// One note-on/note-off pair in loop ticks. `end > start` always.
public struct ScheduledNote: Hashable, Sendable {
    public var start: Int
    public var end: Int
    public var pitch: Int
    public var velocity: Float
    public var glide: Bool

    public init(start: Int, end: Int, pitch: Int, velocity: Float, glide: Bool) {
        self.start = start
        self.end = end
        self.pitch = pitch
        self.velocity = velocity
        self.glide = glide
    }
}

/// What the renderer plays on one part channel.
public struct PartPlayback: Hashable, Sendable {
    public let instrument: InstrumentID
    public let sound: SoundSettings
    public let muted: Bool
    /// Sorted by start (then pitch, then end).
    public let events: [ScheduledNote]

    init(part: Part) {
        instrument = part.instrument
        sound = part.sound
        muted = part.muted
        var events: [ScheduledNote] = []
        switch part.content {
        case .notes(let seq):
            events = seq.notes.map(Self.scheduled)
        case .chords(let progression):
            events = progression.renderedNotes(velocity: 0.7).notes.map(Self.scheduled)
        case .drums(let pattern):
            for (lane, hits) in pattern.lanes {
                for hit in hits {
                    let start = pattern.swungTick(hit.tick)
                    events.append(ScheduledNote(start: start, end: start + 1, pitch: lane.midiNote,
                                                velocity: hit.velocity, glide: false))
                }
            }
        }
        self.events = events.sorted { ($0.start, $0.pitch, $0.end) < ($1.start, $1.pitch, $1.end) }
    }

    /// Zero or negative lengths still get their note-off one tick after the note-on.
    private static func scheduled(_ n: NoteEvent) -> ScheduledNote {
        ScheduledNote(start: n.start, end: n.start + max(1, n.length), pitch: n.pitch,
                      velocity: n.velocity, glide: n.glide)
    }
}

/// Immutable, render-ready copy of a track, built on the UI thread and handed to `Renderer.setSnapshot`.
public struct PlaybackSnapshot: Sendable {
    /// Number of part channels (0...7); channel 8 is live play.
    public static let maxParts = 8

    public let tempo: Double
    public let loopTicks: Int
    /// Part `i` plays on channel `i`; parts beyond the eighth are ignored.
    public let parts: [PartPlayback]

    public init(track: Track) {
        tempo = track.tempo
        loopTicks = max(1, track.bars) * Ticks.perBar
        parts = track.parts.prefix(Self.maxParts).map(PartPlayback.init(part:))
    }
}
