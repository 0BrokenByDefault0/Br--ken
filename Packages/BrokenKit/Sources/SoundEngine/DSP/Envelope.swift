import Foundation

/// Linear ADSR. Release runs from the current level to 0 over the release time.
public struct ADSR: Sendable {
    private enum Stage { case idle, attack, decay, sustain, release }

    private var stage: Stage = .idle
    private var level: Float = 0
    private let attackRate: Float
    private let decayRate: Float
    private let sustain: Float
    private let releaseSamples: Int
    private var releaseRemaining = 0
    private var releaseStart: Float = 0

    public init(attack: Double, decay: Double, sustain: Float, release: Double, sampleRate: Double) {
        attackRate = 1 / Float(max(1, attack * sampleRate))
        let s = min(max(sustain, 0), 1)
        self.sustain = s
        decayRate = (1 - s) / Float(max(1, decay * sampleRate))
        releaseSamples = max(1, Int((release * sampleRate).rounded()))
    }

    public var isIdle: Bool { stage == .idle }

    public mutating func gate(on: Bool) {
        if on {
            stage = .attack
        } else if stage != .idle && stage != .release {
            stage = .release
            releaseStart = level
            releaseRemaining = releaseSamples
        }
    }

    public mutating func next() -> Float {
        switch stage {
        case .idle:
            level = 0
        case .attack:
            level += attackRate
            if level >= 1 {
                level = 1
                stage = .decay
            }
        case .decay:
            level -= decayRate
            if level <= sustain {
                level = sustain
                stage = .sustain
            }
        case .sustain:
            level = sustain
        case .release:
            releaseRemaining -= 1
            if releaseRemaining <= 0 {
                level = 0
                stage = .idle
            } else {
                level = releaseStart * Float(releaseRemaining) / Float(releaseSamples)
            }
        }
        return level
    }
}
