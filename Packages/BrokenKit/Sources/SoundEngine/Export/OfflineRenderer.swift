import Foundation
import MusicCore

public struct StereoBuffer: Sendable {
    public var left: [Float]
    public var right: [Float]
    public var frameCount: Int

    public init(left: [Float], right: [Float], frameCount: Int) {
        self.left = left
        self.right = right
        self.frameCount = frameCount
    }
}

public enum OfflineRenderer {
    private static let block = 1024

    /// `round(bars x 4 x 60 / tempo x sampleRate)`.
    public static func frameCount(bars: Int, tempo: Double, sampleRate: Double) -> Int {
        Int((Double(bars) * 4 * 60 / tempo * sampleRate).rounded())
    }

    /// Renders the track from tick 0 with a fresh `Renderer`. `onlyPart` mutes every other part
    /// (channel indices are kept, so the solo part sounds exactly as it does in the full mix).
    /// `loopReady` renders two passes and keeps the second, so tails wrap into the start.
    public static func render(track: Track, onlyPart: UUID? = nil, loopReady: Bool,
                              sampleRate: Double = 48_000) -> StereoBuffer {
        var t = track
        if let only = onlyPart {
            for i in t.parts.indices where t.parts[i].id != only { t.parts[i].muted = true }
        }
        let n = frameCount(bars: t.bars, tempo: t.tempo, sampleRate: sampleRate)
        let total = loopReady ? 2 * n : n

        let r = Renderer(sampleRate: sampleRate)
        r.setSnapshot(PlaybackSnapshot(track: t))
        _ = r.send(.play(fromTick: 0))

        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { rr in
                var done = 0
                while done < total {
                    let k = min(block, total - done)
                    r.render(frames: k, left: l.baseAddress! + done, right: rr.baseAddress! + done)
                    done += k
                }
            }
        }
        if loopReady {
            left = Array(left[n...])
            right = Array(right[n...])
        }
        return StereoBuffer(left: left, right: right, frameCount: n)
    }
}
