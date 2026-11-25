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

    private let app: AppModel

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

    /// Loops the working track at its own tempo.
    func play() { app.audition(working, atTrackTempo: false) }

    func stop() { app.stop() }
}
