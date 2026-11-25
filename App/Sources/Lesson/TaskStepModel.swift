import Foundation
import MusicCore
import Observation

/// One lesson task: the working track the tool edits, the check results, and the hints shown so far.
/// Edits change only the working track (the saved track changes when a keep step saves it).
@Observable @MainActor
final class TaskStepModel {
    let lessonID: String
    let title: String
    let prompt: String
    let tool: ToolKind
    let targetRole: PartRole?
    let uses: [PartRole]
    let checks: [TaskCheck]
    let hints: [String]

    /// The track this task works on. Every part is unmuted: a mute on the Journey card is a listening
    /// preference and must not silence a lesson. The target role's part exists (empty at first).
    private(set) var working: Track
    /// The results of the last `runChecks()`; cleared by every edit, so they never describe a stale track.
    private(set) var results: [CheckResult] = []
    /// How many hints have been shown.
    private(set) var hintIndex = 0
    /// The target role's part this task's work grew from: the part as the task started (so a copy of Your
    /// Track's part, when it has one), moved on to what a keep saved from this task. When Your Track still
    /// holds it, the working part is the owner's own edit of their saved part.
    private(set) var basePart: Part? = nil

    private let app: AppModel
    // Tool models, built once for this task the first time the tool view asks for them.
    @ObservationIgnored private var melodyModel: MelodyToolModel?
    @ObservationIgnored private var drumModel: DrumGridModel?
    @ObservationIgnored private var finderModel: ChordFinderModel?

    init(step: LessonStep, lessonID: String, app: AppModel) {
        guard case .task(let title, let prompt, let tool, let targetRole, let uses, _, let checks, let hints) = step else {
            preconditionFailure("TaskStepModel needs a task step")
        }
        var working = app.workingTrack(for: step, lessonID: lessonID)
        for i in working.parts.indices { working.parts[i].muted = false }
        if let targetRole, working.part(targetRole) == nil {
            working.setPart(Self.emptyPart(targetRole, tool: tool))
        }
        if tool == .trackSetup, app.activeTrack == nil { working.name = app.defaultTrackName }
        self.app = app
        self.lessonID = lessonID
        self.title = title
        self.prompt = prompt
        self.tool = tool
        self.targetRole = targetRole
        self.uses = uses
        self.checks = checks
        self.hints = hints
        self.working = working
        basePart = targetRole.flatMap { working.part($0) }
    }

    /// A keep saved this task's target part to Your Track as `saved`: later edits grow from it.
    func rebase(onto saved: Part?) {
        basePart = saved
    }

    /// The default instrument and empty content for a role edited with `tool`.
    static func emptyPart(_ role: PartRole, tool: ToolKind) -> Part {
        let content: PartContent
        switch tool {
        case .chordPads, .chordFinder: content = .chords(ChordProgression(slots: []))
        case .drumGrid: content = .drums(DrumPattern(lanes: [:]))
        case .melodyEditor, .trackSetup: content = .notes(NoteSequence(notes: []))
        }
        let instrument: InstrumentID
        switch role {
        case .melody: instrument = .bell
        case .chords: instrument = .pad
        case .drums: instrument = .trapKit
        case .bass808: instrument = .eight08
        case .counter: instrument = .pluck
        case .texture: instrument = .keys
        }
        return Part(role: role, instrument: instrument, content: content)
    }

    // MARK: - Checks and hints

    @discardableResult
    func runChecks() -> [CheckResult] {
        results = CheckRunner.run(checks, on: working)
        return results
    }

    /// True when the last check ran at least one check and every one passed.
    var allPassed: Bool { !results.isEmpty && results.allSatisfy(\.passed) }

    /// The owner can always move on; nothing is locked.
    var canContinue: Bool { true }

    var continueLabel: String { allPassed ? "Continue" : "Continue anyway" }

    /// The next hint in order, or nil once all have been shown.
    func nextHint() -> String? {
        guard hintIndex < hints.count else { return nil }
        defer { hintIndex += 1 }
        return hints[hintIndex]
    }

    var shownHints: [String] { Array(hints.prefix(hintIndex)) }

    // MARK: - Editing and playback

    /// Changes the working track (never the saved one). A playing loop picks the change up at once.
    func edit(_ mutate: (inout Track) -> Void) {
        mutate(&working)
        results = []
        app.updateAudition(working)
    }

    /// Changes the target role's part. No-op for a task without a target role.
    func editTarget(_ mutate: (inout Part) -> Void) {
        guard let targetRole else { return }
        edit { track in
            var part = track.part(targetRole) ?? Self.emptyPart(targetRole, tool: tool)
            mutate(&part)
            track.setPart(part)
        }
    }

    var targetPart: Part? { targetRole.flatMap { working.part($0) } }

    // MARK: - Tool models

    /// The melody editor on the target part (melodyEditor tasks).
    var melodyTool: MelodyToolModel {
        if let melodyModel { return melodyModel }
        let app = app
        let model = MelodyToolModel(part: targetPart, bars: working.bars, key: working.key, audio: app.audio,
                                    isPlaying: { [weak app] in app?.isPlaying ?? false },
                                    play: { [weak self] in self?.play() },
                                    write: { [weak self] sequence in self?.editTarget { $0.content = .notes(sequence) } })
        melodyModel = model
        return model
    }

    /// The drum grid on the target part (drumGrid tasks).
    var drumGrid: DrumGridModel {
        if let drumModel { return drumModel }
        var pattern = DrumPattern(lanes: [:])
        if case .drums(let p)? = targetPart?.content { pattern = p }
        let model = DrumGridModel(pattern: pattern, bars: working.bars)
        model.onChange = { [weak self] pattern in self?.editTarget { $0.content = .drums(pattern) } }
        drumModel = model
        return model
    }

    /// The Chord Finder over the working track's melody, writing the target part (chordFinder tasks).
    var chordFinder: ChordFinderModel {
        if let finderModel { return finderModel }
        var melody = NoteSequence(notes: [])
        if case .notes(let s)? = working.part(.melody)?.content { melody = s }
        let model = ChordFinderModel(melody: melody, bars: working.bars, key: working.key)
        model.tempo = working.tempo
        if case .chords(let p)? = targetPart?.content { model.progression = p }
        finderModel = model
        return model
    }

    /// Ends a live take still being recorded, writing it into the working track (leaving the step).
    func finishRecording() { melodyModel?.stopped() }

    /// Loops the working track at its own tempo.
    func play() { app.audition(working, atTrackTempo: false) }

    func stop() { app.stop() }
}
