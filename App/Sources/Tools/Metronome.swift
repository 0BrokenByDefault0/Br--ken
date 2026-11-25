import MusicCore

/// The track as it is sent to audio while the metronome is on: a temporary trapKit part with a rim hit
/// on every beat. The saved track is never changed.
func withMetronome(_ track: Track) -> Track {
    let loopTicks = max(1, track.bars) * Ticks.perBar
    let hits = stride(from: 0, to: loopTicks, by: Ticks.perQuarter).map { DrumHit(tick: $0, velocity: 0.6) }
    var result = track
    result.parts.append(Part(role: .texture, instrument: .trapKit,
                             content: .drums(DrumPattern(lanes: [.rim: hits]))))
    return result
}
