import Foundation
import MusicCore

/// Static recipe for an instrument: envelope times, per-voice gain and pitch behaviour.
/// The signal path itself lives in `Voice`.
public struct InstrumentPreset: Sendable {
    public let id: InstrumentID
    let attack: Double
    let decay: Double
    let sustain: Float
    let release: Double
    /// Peak level of one full-velocity note, before the master stage.
    let gain: Float
    /// 808 onset: starts this many semitones up and falls to pitch.
    let dropSemitones: Float
    let dropSeconds: Double
    let glideSeconds: Double

    public static let eight08Glide = 0.06

    public static func make(_ id: InstrumentID) -> InstrumentPreset {
        func p(_ a: Double, _ d: Double, _ s: Float, _ r: Double, gain: Float,
               drop: Float = 0, dropSeconds: Double = 0, glide: Double = 0) -> InstrumentPreset {
            InstrumentPreset(id: id, attack: a, decay: d, sustain: s, release: r, gain: gain,
                             dropSemitones: drop, dropSeconds: dropSeconds, glideSeconds: glide)
        }
        switch id {
        case .eight08: return p(0.001, 0.001, 1, 0.15, gain: 0.5, drop: 12, dropSeconds: 0.03, glide: eight08Glide)
        case .bell: return p(0.001, 2.5, 0, 0.3, gain: 0.4)
        case .pluck: return p(0.0005, 0.01, 1, 0.12, gain: 0.5)
        case .pad: return p(0.4, 0.01, 1, 1.2, gain: 0.45)
        case .keys: return p(0.002, 1.5, 0.2, 0.25, gain: 0.4)
        case .trapKit: return p(0, 0, 1, 0, gain: 0.5)
        }
    }
}
