public enum NotationError: Error, Equatable {
    case invalidMelodyToken(String)
    case invalidChordToken(String)
    case invalidDrumLane(String)
}

public enum Notation {
    /// Tokens `<Pitch><Octave>:<16ths>[~]` or `r:<16ths>`, space separated. `C4` = 60; `~` sets glide.
    public static func melody(_ s: String) throws -> NoteSequence {
        var notes: [NoteEvent] = []
        var time = 0
        for token in s.split(whereSeparator: \.isWhitespace).map(String.init) {
            var body = token
            var glide = false
            if body.hasSuffix("~") { glide = true; body.removeLast() }
            let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let steps = Int(parts[1]), steps > 0 else {
                throw NotationError.invalidMelodyToken(token)
            }
            let length = steps * Ticks.perSixteenth
            if parts[0] == "r" {
                guard !glide else { throw NotationError.invalidMelodyToken(token) }
                time += length
                continue
            }
            let pitch = try parsePitch(parts[0], token: token)
            notes.append(NoteEvent(start: time, length: length, pitch: pitch, glide: glide))
            time += length
        }
        return NoteSequence(notes: notes)
    }

    /// Tokens `<Symbol>:<16ths>`, laid out back to back from tick 0.
    public static func chords(_ s: String) throws -> ChordProgression {
        var slots: [ChordSlot] = []
        var time = 0
        for token in s.split(whereSeparator: \.isWhitespace).map(String.init) {
            let parts = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let steps = Int(parts[1]), steps > 0 else {
                throw NotationError.invalidChordToken(token)
            }
            let length = steps * Ticks.perSixteenth
            slots.append(ChordSlot(start: time, length: length, chord: try Chord(parsing: parts[0])))
            time += length
        }
        return ChordProgression(slots: slots)
    }

    /// One character per 16th step; length must be a multiple of 16.
    public static func drumLane(_ s: String) throws -> [DrumHit] {
        let chars = Array(s)
        guard chars.count % 16 == 0 else { throw NotationError.invalidDrumLane(s) }
        var hits: [DrumHit] = []
        var step = 0
        var i = 0
        while i < chars.count {
            let base = step * Ticks.perSixteenth
            switch chars[i] {
            case ".": break
            case "x": hits.append(DrumHit(tick: base, velocity: 0.8))
            case "X": hits.append(DrumHit(tick: base, velocity: 1.0))
            case "g": hits.append(DrumHit(tick: base, velocity: 0.4))
            case "2", "3", "4":
                let n = Int(String(chars[i]))!
                for k in 0..<n {
                    hits.append(DrumHit(tick: base + k * Ticks.perSixteenth / n, velocity: 0.8))
                }
            case "T":
                guard i + 1 < chars.count, chars[i + 1] == "T" else { throw NotationError.invalidDrumLane(s) }
                for k in 0..<3 {
                    hits.append(DrumHit(tick: base + k * 16, velocity: 0.8))
                }
                i += 1
                step += 1
            default:
                throw NotationError.invalidDrumLane(s)
            }
            i += 1
            step += 1
        }
        return hits
    }

    private static func parsePitch(_ s: String, token: String) throws -> Int {
        let chars = Array(s)
        let naturals: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let first = chars.first, var pc = naturals[first] else {
            throw NotationError.invalidMelodyToken(token)
        }
        var index = 1
        if index < chars.count, chars[index] == "#" { pc += 1; index += 1 }
        else if index < chars.count, chars[index] == "b" { pc -= 1; index += 1 }
        guard let octave = Int(String(chars[index...])) else { throw NotationError.invalidMelodyToken(token) }
        return 12 * (octave + 1) + pc
    }
}
