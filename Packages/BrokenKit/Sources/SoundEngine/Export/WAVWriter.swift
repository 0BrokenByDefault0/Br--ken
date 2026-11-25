import Foundation

public enum WAVWriter {
    /// 16-bit PCM, interleaved stereo, little-endian.
    public static func write(_ b: StereoBuffer, sampleRate: Int = 48_000, to url: URL) throws {
        let frames = min(b.frameCount, b.left.count, b.right.count)
        let dataSize = frames * 4
        var d = Data(capacity: 44 + dataSize)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(2); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(dataSize))
        func s(_ x: Float) -> UInt16 {
            let c = x.isFinite ? min(max(x, -1), 1) : 0
            return UInt16(bitPattern: Int16((c * 32767).rounded()))
        }
        for i in 0..<frames { u16(s(b.left[i])); u16(s(b.right[i])) }
        try d.write(to: url, options: .atomic)
    }
}
