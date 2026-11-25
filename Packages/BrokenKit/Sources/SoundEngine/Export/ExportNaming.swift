import Foundation
import MusicCore

public enum ExportNaming {
    /// Key spelling: spaces are dropped and `#` becomes `sharp` ("F# minor" -> "Fsharpminor").
    /// `<name>-<tempo>bpm-<Key no spaces>[-<role>].wav`
    public static func fileName(track: Track, part: Part?) -> String {
        var s = "\(sanitize(track.name))-\(Int(Renderer.clampedTempo(track.tempo).rounded()))bpm-\(sanitize(track.key.name.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "#", with: "sharp")))"
        if let part { s += "-\(part.role.rawValue)" }
        return s + ".wav"
    }

    static func sanitize(_ name: String) -> String {
        var out = ""
        var lastDash = false
        for ch in name.unicodeScalars {
            let ok = ch.isASCII && (CharacterSet.alphanumerics.contains(ch) || ch == "_")
            if ok { out.unicodeScalars.append(ch); lastDash = false }
            else if !lastDash { out.append("-"); lastDash = true }
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        out = String(out.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return out.isEmpty ? "track" : out
    }
}
