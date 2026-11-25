public enum CheckRunner {
    public static func run(_ checks: [TaskCheck], on track: Track) -> [CheckResult] {
        checks.map { check in
            let (passed, message) = evaluate(check, on: track)
            return CheckResult(check: check, passed: passed, message: message)
        }
    }

    // MARK: - Dispatch

    private static func evaluate(_ check: TaskCheck, on track: Track) -> (Bool, String) {
        switch check {
        case .tempoInRange(let lo, let hi):
            let t = Int(track.tempo.rounded())
            let range = "\(Int(lo))–\(Int(hi))"
            return track.tempo >= lo && track.tempo <= hi
                ? (true, "Tempo \(t) BPM is in the \(range) range.")
                : (false, "Tempo is \(t) BPM; aim for \(range).")
        case .inKey(let role):
            return inKey(role, track)
        case .noteCount(let role, let lo, let hi):
            guard let notes = notes(role, track) else { return missing(role, "notes") }
            return count(notes.notes.count, lo, hi, noun: "note")
        case .barRhythmRepeats(let role):
            return barRhythmRepeats(role, track)
        case .endsOnDegree(let role, let degrees):
            return endsOnDegree(role, degrees, track)
        case .chordCount(let role, let lo, let hi):
            guard let prog = progression(role, track) else { return missing(role, "chords") }
            return count(prog.slots.count, lo, hi, noun: "chord")
        case .chordsInKey(let role):
            return chordsInKey(role, track)
        case .chordDegrees(let role, let required):
            return chordDegrees(role, required, track)
        case .chordsFitMelody(let chords, let melody, let ratio):
            return chordsFitMelody(chords, melody, ratio, track)
        case .extendedChordCount(let role, let lo):
            guard let prog = progression(role, track) else { return missing(role, "chords") }
            let n = prog.slots.filter { $0.chord.quality.isExtended }.count
            return n >= lo
                ? (true, "\(plural(n, "extended chord")) add\(n == 1 ? "s" : "") colour.")
                : (false, "Only \(plural(n, "extended chord")); use at least \(lo) (like 7ths or 9ths).")
        case .drumHitOnBeats(let lane, let beats, let everyBar):
            return drumHitOnBeats(lane, beats, everyBar, track)
        case .laneHitCount(let lane, let lo):
            guard let hits = hits(lane, track) else { return missing(.drums, "drums") }
            return hits.count >= lo
                ? (true, "\(plural(hits.count, "\(name(lane)) hit")) keep\(hits.count == 1 ? "s" : "") it moving.")
                : (false, "\(plural(hits.count, "\(name(lane)) hit")); add more to reach \(lo).")
        case .hatRollPresent:
            return hatRollPresent(track)
        case .syncopatedKicks(let lo):
            guard let kicks = hits(.kick, track) else { return missing(.drums, "drums") }
            let n = kicks.filter { $0.tick % Ticks.perQuarter != 0 }.count
            return n >= lo
                ? (true, "\(plural(n, "off-beat kick")) give\(n == 1 ? "s" : "") it bounce.")
                : (false, "\(plural(n, "off-beat kick")); move some kicks off the beat to reach \(lo).")
        case .barsDiffer(let role):
            return barsDiffer(role, track)
        }
    }

    // MARK: - Content access

    private static func notes(_ role: PartRole, _ track: Track) -> NoteSequence? {
        switch track.part(role)?.content {
        case .notes(let seq): return seq
        case .chords(let prog): return prog.renderedNotes()
        default: return nil
        }
    }

    private static func progression(_ role: PartRole, _ track: Track) -> ChordProgression? {
        if case .chords(let prog) = track.part(role)?.content { return prog }
        return nil
    }

    private static func pattern(_ track: Track) -> DrumPattern? {
        if case .drums(let p) = track.part(.drums)?.content { return p }
        return nil
    }

    /// Hits for a lane, or nil when there is no drum part at all.
    private static func hits(_ lane: DrumLane, _ track: Track) -> [DrumHit]? {
        guard let p = pattern(track) else { return nil }
        return p.lanes[lane] ?? []
    }

    private static func missing(_ role: PartRole, _ what: String) -> (Bool, String) {
        (false, "There's no \(role.rawValue) \(what == "drums" ? "pattern" : what) yet; add one first.")
    }

    private static func name(_ lane: DrumLane) -> String {
        switch lane {
        case .closedHat: "closed hat"
        case .openHat: "open hat"
        default: lane.rawValue
        }
    }

    private static func bar(of tick: Int) -> Int { tick / Ticks.perBar }

    private static func plural(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    private static func count(_ n: Int, _ lo: Int, _ hi: Int?, noun: String) -> (Bool, String) {
        if n < lo { return (false, "\(plural(n, noun)); use at least \(lo).") }
        if let hi, n > hi { return (false, "\(plural(n, noun)) is a lot; keep it to \(hi) or fewer.") }
        return (true, "\(plural(n, noun)), a good amount.")
    }

    // MARK: - Melody checks

    private static func inKey(_ role: PartRole, _ track: Track) -> (Bool, String) {
        guard let seq = notes(role, track) else { return missing(role, "notes") }
        let key = track.key
        var seen = Set<String>()
        var offenders: [String] = []
        for n in seq.notes where !key.contains(PitchClass(n.pitch)) {
            let note = key.spell(PitchClass(n.pitch))
            let b = bar(of: n.start) + 1
            if seen.insert("\(b)-\(note)").inserted { offenders.append("Bar \(b): \(note) isn't in \(key.name).") }
        }
        guard let first = offenders.first else { return (true, "Every note stays in \(key.name).") }
        return (false, offenders.count > 1 ? "\(first) (+\(offenders.count - 1) more)" : first)
    }

    private static func barRhythmRepeats(_ role: PartRole, _ track: Track) -> (Bool, String) {
        guard let seq = notes(role, track) else { return missing(role, "notes") }
        var bars: [Int: Set<Int>] = [:]
        for n in seq.notes { bars[bar(of: n.start), default: []].insert(n.start % Ticks.perBar) }
        let sets = bars.keys.sorted().map { bars[$0]! }
        for i in 0..<sets.count {
            for j in (i + 1)..<max(sets.count, i + 1) where sets[i] == sets[j] {
                return (true, "The rhythm repeats, which makes the phrase memorable.")
            }
        }
        return (false, "No two bars share a rhythm; repeat one bar's rhythm somewhere.")
    }

    private static func endsOnDegree(_ role: PartRole, _ degrees: [Int], _ track: Track) -> (Bool, String) {
        guard let seq = notes(role, track) else { return missing(role, "notes") }
        guard let last = seq.notes.max(by: { $0.start < $1.start }) else {
            return (false, "The \(role.rawValue) has no notes, so it can't end anywhere yet.")
        }
        let key = track.key
        let pc = PitchClass(last.pitch)
        let note = key.spell(pc)
        if let d = key.degree(of: pc), degrees.contains(d) {
            return (true, "Ending on \(note) feels settled.")
        }
        return (false, "It ends on \(note); finish on \(degreeNames(degrees, key)).")
    }

    private static func degreeNames(_ degrees: [Int], _ key: Key) -> String {
        let scale = key.scalePitchClasses
        let names = degrees.filter { (1...7).contains($0) }.map { key.spell(scale[$0 - 1]) }
        return names.isEmpty ? "a target note" : names.joined(separator: " or ")
    }

    // MARK: - Chord checks

    private static func chordsInKey(_ role: PartRole, _ track: Track) -> (Bool, String) {
        guard let prog = progression(role, track) else { return missing(role, "chords") }
        let key = track.key
        let borrowed = key.borrowedChords().map(\.chord)
        for slot in prog.slots {
            let chord = slot.chord
            if borrowed.contains(chord) { continue }
            if let out = chord.pitchClasses.sorted(by: { $0.rawValue < $1.rawValue }).first(where: { !key.contains($0) }) {
                return (false, "Bar \(bar(of: slot.start) + 1): \(chord.symbol(in: key)) has \(key.spell(out)), which isn't in \(key.name).")
            }
        }
        return (true, "All chords belong to \(key.name).")
    }

    private static func chordDegrees(_ role: PartRole, _ required: [Int], _ track: Track) -> (Bool, String) {
        guard let prog = progression(role, track) else { return missing(role, "chords") }
        let key = track.key
        let triads = key.diatonicTriads()
        let roots = Set(prog.slots.map(\.chord.root))
        var absent: [String] = []
        for d in required {
            guard let triad = triads.first(where: { $0.degree == d }) else { continue }
            if !roots.contains(triad.chord.root) { absent.append(triad.chord.symbol(in: key)) }
        }
        return absent.isEmpty
            ? (true, "You've used all the chords this one needs.")
            : (false, "Missing \(absent.joined(separator: ", ")); add \(absent.count == 1 ? "it" : "them") to the progression.")
    }

    private static func chordsFitMelody(_ chordsRole: PartRole, _ melodyRole: PartRole,
                                        _ ratio: Double, _ track: Track) -> (Bool, String) {
        guard let prog = progression(chordsRole, track) else { return missing(chordsRole, "chords") }
        guard case .notes(let melody)? = track.part(melodyRole)?.content else { return missing(melodyRole, "notes") }
        let key = track.key
        for b in 0..<max(track.bars, 0) {
            let window = (b * Ticks.perBar)..<((b + 1) * Ticks.perBar)
            guard !melody.notes(overlapping: window).isEmpty else { continue }
            guard let chord = prog.chord(at: window.lowerBound) else {
                return (false, "Bar \(b + 1): there's no chord under the melody.")
            }
            let fits = ChordFinder.fits(melody: melody, window: window, key: key)
            guard let best = fits.first else { continue }
            let score = fits.first { $0.chord == chord }?.score
                ?? ChordFinder.score(of: chord, melody: melody, window: window)
            let ok = scorePasses(score, best: best.score, ratio: ratio)
            if !ok {
                return (false, "Bar \(b + 1): \(chord.symbol(in: key)) clashes with the melody; try \(best.chord.symbol(in: key)).")
            }
        }
        return (true, "The chords support the melody in every bar.")
    }

    /// When the best score is not positive, only a chord matching the best passes.
    static func scorePasses(_ score: Double, best: Double, ratio: Double) -> Bool {
        best <= 0 ? score == best : score >= ratio * best
    }

    // MARK: - Drum checks

    private static func drumHitOnBeats(_ lane: DrumLane, _ beats: [Int], _ everyBar: Bool,
                                       _ track: Track) -> (Bool, String) {
        guard let laneHits = hits(lane, track) else { return missing(.drums, "drums") }
        let ticks = Set(laneHits.map(\.tick))
        let bars = max(track.bars, 1)
        let sortedBeats = beats.sorted()
        let missingPerBar: [[Int]] = (0..<bars).map { b in
            sortedBeats.filter { !ticks.contains(b * Ticks.perBar + ($0 - 1) * Ticks.perQuarter) }
        }
        let beatsText = { (bs: [Int]) in "beat" + (bs.count == 1 ? " " : "s ") + bs.map(String.init).joined(separator: " and ") }
        if everyBar {
            if let bad = missingPerBar.firstIndex(where: { !$0.isEmpty }) {
                return (false, "Bar \(bad + 1): the \(name(lane)) is missing on \(beatsText(missingPerBar[bad])).")
            }
            return (true, "The \(name(lane)) lands on \(beatsText(sortedBeats)) in every bar.")
        }
        if missingPerBar.contains(where: \.isEmpty) {
            return (true, "The \(name(lane)) lands on \(beatsText(sortedBeats)).")
        }
        let closest = missingPerBar.enumerated().min { $0.element.count < $1.element.count }!
        return (false, "Bar \(closest.offset + 1): the \(name(lane)) is missing on \(beatsText(closest.element)).")
    }

    private static func hatRollPresent(_ track: Track) -> (Bool, String) {
        guard pattern(track) != nil else { return missing(.drums, "drums") }
        for lane in [DrumLane.closedHat, .openHat] {
            let ticks = (hits(lane, track) ?? []).map(\.tick).sorted()
            for (a, b) in zip(ticks, ticks.dropFirst()) where b - a < 24 {
                return (true, "That hat roll adds trap energy.")
            }
        }
        return (false, "No hat roll yet; fill a quick run of hats.")
    }

    // MARK: - Bars

    private static func barsDiffer(_ role: PartRole, _ track: Track) -> (Bool, String) {
        guard let part = track.part(role) else { return missing(role, role == .drums ? "drums" : "notes") }
        guard track.bars > 1 else { return (false, "There's only one bar, so there's nothing to compare.") }
        let first = barContent(part.content, bar: 0)
        for b in 1..<track.bars where barContent(part.content, bar: b) != first {
            return (true, "Bar \(b + 1) differs from bar 1, which adds variety.")
        }
        return (false, "Every bar is identical to bar 1; change something in a later bar.")
    }

    private static func barContent(_ content: PartContent, bar: Int) -> Set<String> {
        let range = (bar * Ticks.perBar)..<((bar + 1) * Ticks.perBar)
        var out = Set<String>()
        switch content {
        case .notes(let seq):
            for n in seq.notes where range.contains(n.start) {
                out.insert("n\(n.start - range.lowerBound):\(n.length):\(n.pitch)")
            }
        case .chords(let prog):
            for s in prog.slots where range.contains(s.start) {
                out.insert("c\(s.start - range.lowerBound):\(s.length):\(s.chord.root.rawValue):\(s.chord.quality.rawValue)")
            }
        case .drums(let p):
            for (lane, laneHits) in p.lanes {
                for h in laneHits where range.contains(h.tick) { out.insert("d\(lane.rawValue):\(h.tick - range.lowerBound)") }
            }
        }
        return out
    }
}
