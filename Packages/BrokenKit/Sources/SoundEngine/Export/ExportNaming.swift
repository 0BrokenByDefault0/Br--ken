import Foundation
import MusicCore

public enum ExportNaming {
    /// `<name>-<tempo>bpm-<Key no spaces>[-<role>].wav`
    public static func fileName(track: Track, part: Part?) -> String {
        var s = "\(sanitize(track.name))-\(Int(track.tempo.rounded()))bpm-\(track.key.name.replacingOccurrences(of: " ", with: ""))"
        if let part { s += "-\(part.role.rawValue)" }
        return s + ".wav"
    }

    static func sanitize(_ name: String) -> String {
        var out = ""
        var lastDash = false
        for ch in name.unicodeScalars {
            let ok = ch.isASCII && (CharacterSet.alphanumerics.contains(ch) || ch == "-" || ch == "_")
            if ok { out.unicodeScalars.append(ch); lastDash = false }
            else if !lastDash { out.append("-"); lastDash = true }
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        out = String(out.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return out.isEmpty ? "track" : out
    }
}
