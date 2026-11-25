import Foundation
import MusicCore
import Observation

/// Drum pattern editing over a looping grid of `bars` bars of 16 steps. Steps passed to the edit
/// methods are 0...15 within `selectedBar`.
@Observable
final class DrumGridModel {
    static let stepsPerBar = 16
    static let swingRange: ClosedRange<Double> = 0...0.6

    var pattern: DrumPattern
    var selectedBar = 0
    let bars: Int
    /// Called after every edit with the new pattern.
    @ObservationIgnored var onChange: ((DrumPattern) -> Void)?

    init(pattern: DrumPattern, bars: Int) {
        self.pattern = pattern
        self.bars = max(1, bars)
    }

    var swing: Double {
        get { pattern.swing }
        set {
            pattern.swing = min(Self.swingRange.upperBound, max(Self.swingRange.lowerBound, newValue))
            changed()
        }
    }

    var loopTicks: Int { bars * Ticks.perBar }

    private func absoluteStep(_ step: Int) -> Int { selectedBar * Self.stepsPerBar + step }
    private func tickRange(step: Int) -> Range<Int> {
        let start = absoluteStep(step) * Ticks.perSixteenth
        return start..<(start + Ticks.perSixteenth)
    }

    private func validStep(_ step: Int) -> Bool { step >= 0 && step < Self.stepsPerBar && selectedBar >= 0 && selectedBar < bars }

    /// Hits inside the step, in tick order.
    func hits(lane: DrumLane, step: Int) -> [DrumHit] {
        let range = tickRange(step: step)
        return (pattern.lanes[lane] ?? []).filter { range.contains($0.tick) }
    }

    /// More than one hit in a step (or a single hit off the step start) means a roll.
    func isRoll(lane: DrumLane, step: Int) -> Bool {
        let h = hits(lane: lane, step: step)
        return h.count > 1 || (h.first.map { $0.tick != tickRange(step: step).lowerBound } ?? false)
    }

    func toggle(lane: DrumLane, step: Int) {
        guard validStep(step) else { return }
        pattern.toggle(lane: lane, step: absoluteStep(step))
        changed()
    }

    /// Sets the velocity of the hit exactly on the step (no-op if there is none).
    func setVelocity(lane: DrumLane, step: Int, _ v: Float) {
        guard validStep(step) else { return }
        let tick = tickRange(step: step).lowerBound
        guard var hits = pattern.lanes[lane], let i = hits.firstIndex(where: { $0.tick == tick }) else { return }
        hits[i].velocity = min(1, max(0.05, v))
        pattern.lanes[lane] = hits
        changed()
    }

    /// Fills `fromStep...toStep` (inclusive, either order) with a roll whose velocities ramp across `ramp`
    /// (reversed when `descending`).
    func roll(lane: DrumLane, fromStep: Int, toStep: Int, rate: RollRate, ramp: ClosedRange<Float>,
              descending: Bool = false) {
        let lo = max(0, min(fromStep, toStep)), hi = min(Self.stepsPerBar - 1, max(fromStep, toStep))
        guard validStep(lo), validStep(hi) else { return }
        pattern.fillRoll(lane: lane, from: tickRange(step: lo).lowerBound, to: tickRange(step: hi).upperBound,
                         rate: rate, velocities: ramp, descending: descending)
        changed()
    }

    /// Removes every hit inside the step, leaving it empty.
    func clearRolls(lane: DrumLane, step: Int) {
        guard validStep(step) else { return }
        let range = tickRange(step: step)
        pattern.lanes[lane] = (pattern.lanes[lane] ?? []).filter { !range.contains($0.tick) }
        changed()
    }

    /// Replaces bar `to` on every lane with bar `from`'s hits.
    func copyBar(_ from: Int, to: Int) {
        guard from != to, (0..<bars).contains(from), (0..<bars).contains(to) else { return }
        let source = from * Ticks.perBar..<(from + 1) * Ticks.perBar
        let target = to * Ticks.perBar..<(to + 1) * Ticks.perBar
        let offset = (to - from) * Ticks.perBar
        for lane in DrumLane.allCases {
            let hits = pattern.lanes[lane] ?? []
            guard !hits.isEmpty else { continue }
            var result = hits.filter { !target.contains($0.tick) }
            for var hit in hits where source.contains(hit.tick) {
                hit.tick += offset
                result.append(hit)
            }
            result.sort { $0.tick < $1.tick }
            pattern.lanes[lane] = result
        }
        changed()
    }

    private func changed() { onChange?(pattern) }
}
