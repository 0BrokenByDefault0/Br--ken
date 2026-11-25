import SwiftUI
import MusicCore
import Observation

/// Where the owner is in a lesson, the task models (one per task step, built when first needed), and
/// what the keep steps saved. Leaving a step stops whatever it was playing.
@Observable @MainActor
final class LessonPlayerModel {
    let lesson: Lesson
    private(set) var index = 0
    private(set) var finished = false
    /// What each keep step (by index) saved to Your Track.
    private(set) var saved: [Int: [PartRole]] = [:]
    /// Per keep step, the Replace (true) / Keep mine (false) choices the owner made for roles Your Track
    /// already has. A role without a choice uses `defaultReplaces`.
    private(set) var replaceChoices: [Int: [PartRole: Bool]] = [:]
    // Built lazily from view bodies, so not observed.
    @ObservationIgnored private var taskModels: [Int: TaskStepModel] = [:]
    private let app: AppModel

    init(lesson: Lesson, app: AppModel) {
        self.lesson = lesson
        self.app = app
    }

    var steps: [LessonStep] { lesson.steps }
    var isLast: Bool { index >= steps.count - 1 }

    /// The task model for the task step at `i`, built from the working track the first time it is asked for.
    func taskModel(at i: Int) -> TaskStepModel {
        if let model = taskModels[i] { return model }
        let model = TaskStepModel(step: steps[i], lessonID: lesson.id, app: app)
        taskModels[i] = model
        return model
    }

    func go(to i: Int) {
        guard steps.indices.contains(i), i != index else { return }
        stopPlayback()
        index = i
    }

    /// The next step, or finishing the lesson on the last one.
    func next() {
        if isLast { finish() } else { go(to: index + 1) }
    }

    func back() { go(to: index - 1) }

    /// Marks the lesson complete (also done by a keep step; doing it twice is harmless).
    func finish() {
        stopPlayback()
        app.markLessonComplete(lesson.id)
        finished = true
    }

    /// Back to the first step with fresh task models (work, results, and hints) and nothing saved, for
    /// going through the lesson again.
    func restart() {
        stopPlayback()
        finished = false
        index = 0
        taskModels = [:]
        saved = [:]
        replaceChoices = [:]
    }

    // MARK: - Keep

    /// The task step whose working track the keep step at `keepIndex` saves: the most recent earlier task
    /// whose target role is one of `roles`, else the most recent earlier task, else none.
    static func keepSourceIndex(in steps: [LessonStep], before keepIndex: Int, roles: [PartRole]) -> Int? {
        var latestTask: Int?
        for i in stride(from: min(keepIndex, steps.count) - 1, through: 0, by: -1) {
            guard case .task(_, _, _, let target, _, _, _, _) = steps[i] else { continue }
            if let target, roles.contains(target) { return i }
            if latestTask == nil { latestTask = i }
        }
        return latestTask
    }

    /// The track the Koala step exports: Your Track (the lesson's parts have been kept by now), else the
    /// most recent earlier task's working track.
    func exportTrack(at i: Int) -> Track? {
        if let active = app.activeTrack { return active }
        let latest = stride(from: min(i, steps.count) - 1, through: 0, by: -1).first {
            if case .task = steps[$0] { return true }
            return false
        }
        return latest.map { taskModel(at: $0).working }
    }

    func keepRoles(at i: Int) -> [PartRole] {
        if case .keep(_, let roles) = steps[i] { return roles }
        return []
    }

    func keepSource(forKeepAt i: Int) -> TaskStepModel? {
        Self.keepSourceIndex(in: steps, before: i, roles: keepRoles(at: i)).map { taskModel(at: $0) }
    }

    /// True when the keep step at `i` saves a track setup (name, tempo, key) rather than parts.
    func keepsSetup(at i: Int) -> Bool { keepSource(forKeepAt: i)?.tool == .trackSetup }

    /// Indexes of keep steps that have saved.
    var kept: Set<Int> { Set(saved.keys) }

    /// The track the keep step at `i` saves from: its source task's working track, or (with no earlier
    /// task) the working track for the keep step itself.
    func keepWorking(at i: Int) -> Track {
        keepSource(forKeepAt: i)?.working ?? app.workingTrack(for: steps[i], lessonID: lesson.id)
    }

    /// The keep step's roles the owner hasn't built yet (no part, or an empty one): they are not saved.
    func emptyRoles(forKeepAt i: Int) -> [PartRole] {
        guard !keepsSetup(at: i) else { return [] }
        let working = keepWorking(at: i)
        return keepRoles(at: i).filter { !(working.part($0)?.hasContent ?? false) }
    }

    /// The keep step's roles that saving would replace: Your Track already has a different part for them
    /// (a mute alone doesn't count; it is a listening preference).
    func conflictingRoles(forKeepAt i: Int) -> [PartRole] {
        guard !keepsSetup(at: i), let active = app.activeTrack else { return [] }
        let working = keepWorking(at: i)
        return keepRoles(at: i).filter { role in
            guard let mine = active.part(role), let theirs = working.part(role), theirs.hasContent else { return false }
            return !Self.samePart(mine, theirs)
        }
    }

    private static func samePart(_ a: Part, _ b: Part) -> Bool {
        a.role == b.role && a.instrument == b.instrument && a.content == b.content && a.sound == b.sound
    }

    func replaces(_ role: PartRole, atKeep i: Int) -> Bool {
        replaceChoices[i]?[role] ?? defaultReplaces(role, atKeep: i)
    }

    /// Replace when Your Track's part is still the part the source task's work grew from (the owner edited
    /// their own saved part in this lesson); otherwise Keep mine, so nothing of theirs is lost by default.
    func defaultReplaces(_ role: PartRole, atKeep i: Int) -> Bool {
        guard let source = keepSource(forKeepAt: i), source.targetRole == role,
              let base = source.basePart, let saved = app.activeTrack?.part(role) else { return false }
        return Self.samePart(base, saved)
    }

    func setReplace(_ replace: Bool, role: PartRole, atKeep i: Int) {
        replaceChoices[i, default: [:]][role] = replace
    }

    /// What "Save to Your Track" saves: the roles with content, minus conflicts the owner keeps.
    func rolesToSave(atKeep i: Int) -> [PartRole] {
        let empty = emptyRoles(forKeepAt: i), conflicts = conflictingRoles(forKeepAt: i)
        return keepRoles(at: i).filter { !empty.contains($0) && (!conflicts.contains($0) || replaces($0, atKeep: i)) }
    }

    /// "Save to Your Track": saves the chosen roles and completes the lesson.
    func saveKeep(at i: Int) {
        keep(at: i, roles: rolesToSave(atKeep: i))
    }

    /// Saves `roles` (empty parts are skipped) to Your Track and completes the lesson. After a track-setup
    /// task it saves the tempo and key instead.
    func keep(at i: Int, roles: [PartRole]) {
        stopPlayback()
        let source = keepSource(forKeepAt: i)
        if let source, source.tool == .trackSetup {
            app.keepSetup(from: source.working, lessonID: lesson.id)
            saved[i] = []
        } else {
            let working = keepWorking(at: i)
            app.keep(roles: roles, from: working, lessonID: lesson.id)
            let savedRoles = roles.filter { working.part($0)?.hasContent ?? false }
            saved[i] = savedRoles
            if let source, let target = source.targetRole, savedRoles.contains(target) {
                source.rebase(onto: app.activeTrack?.part(target))
            }
        }
    }

    /// Leaving a step: a live take still recording is written into the working track first.
    private func stopPlayback() {
        taskModels[index]?.finishRecording()
        if app.isPlaying { app.stop() }
    }

    static func stepName(_ step: LessonStep) -> String {
        switch step {
        case .idea: "Idea"
        case .listen: "Hear it"
        case .task: "Do it"
        case .keep: "Keep it"
        case .koala: "Koala"
        }
    }
}

/// A lesson, one step per page: a progress dots header, the step, and a sticky Back / Next bar.
struct LessonPlayerView: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    /// Called by "Back to Journey" once the lesson is done.
    var onBackToJourney: () -> Void = {}

    var body: some View {
        LessonPlayerBody(app: model, lesson: lesson, onBackToJourney: onBackToJourney)
    }
}

private struct LessonPlayerBody: View {
    let app: AppModel
    let onBackToJourney: () -> Void
    @State private var player: LessonPlayerModel

    init(app: AppModel, lesson: Lesson, onBackToJourney: @escaping () -> Void) {
        self.app = app
        self.onBackToJourney = onBackToJourney
        _player = State(initialValue: LessonPlayerModel(lesson: lesson, app: app))
    }

    var body: some View {
        Group {
            if player.steps.isEmpty {
                message("This lesson has no steps yet.")
            } else if player.finished {
                doneView
            } else {
                VStack(spacing: 0) {
                    header
                    ErrorBanner().padding(.horizontal, 16)
                    stepView(player.index)
                        .id(player.index)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            }
        }
        .background(Color.night.ignoresSafeArea())
        // Leaving a finished lesson: opening it again starts at step 1, not on "Lesson done".
        .onDisappear { if player.finished { player.restart() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(player.lesson.title).font(Theme.title(15)).foregroundStyle(Color.mute)
                .padding(.horizontal, 16)
            ProgressDots(steps: player.steps, current: player.index) { player.go(to: $0) }
                .padding(.horizontal, 8)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func stepView(_ i: Int) -> some View {
        switch player.steps[i] {
        case .idea(let title, let body, let deeper):
            IdeaStepView(title: title, text: body, deeper: deeper)
        case .listen(let title, let caption, let examples):
            ListenStepView(app: app, title: title, caption: caption, examples: examples)
        case .task:
            TaskStepView(task: player.taskModel(at: i), app: app)
        case .keep(let message, _):
            KeepStepView(player: player, app: app, index: i, message: message)
        case .koala(let body):
            KoalaStepView(text: body, track: player.exportTrack(at: i))
        }
    }

    private var primaryLabel: String {
        if player.isLast { return "Finish lesson" }
        if case .task = player.steps[player.index] { return player.taskModel(at: player.index).continueLabel }
        return "Next: \(LessonPlayerModel.stepName(player.steps[player.index + 1]))"
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { player.back() } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(Theme.title(16)).foregroundStyle(player.index == 0 ? Color.mute : Color.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: Theme.minTarget + 6)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(player.index == 0)
            Button { player.next() } label: {
                Text(primaryLabel).font(Theme.title(16)).foregroundStyle(Color.night)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTarget + 6)
                    .background(player.isLast ? Color.amber : Color.haze, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.night)
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Color.tone)
            Text("Lesson done").font(Theme.title(26)).foregroundStyle(Color.ink)
            Text(player.lesson.title).font(Theme.body(16)).foregroundStyle(Color.mute)
            Button {
                player.restart()
                onBackToJourney()
            } label: {
                Text("Back to Journey").font(Theme.title(17)).foregroundStyle(Color.night)
                    .padding(.horizontal, 28)
                    .frame(minHeight: Theme.minTarget + 6)
                    .background(Color.amber, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
            Button("Go through it again") { player.restart() }
                .font(Theme.body(15)).foregroundStyle(Color.haze)
                .frame(minHeight: Theme.minTarget)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String) -> some View {
        Text(text).font(Theme.title(20)).foregroundStyle(Color.ink)
            .multilineTextAlignment(.center).padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One labeled dot per step (Idea · Hear it · Do it · Keep it · Koala); tap a dot to jump to that step.
private struct ProgressDots: View {
    let steps: [LessonStep]
    let current: Int
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(steps.indices, id: \.self) { i in
                let name = LessonPlayerModel.stepName(steps[i])
                Button { onTap(i) } label: {
                    VStack(spacing: 5) {
                        Circle()
                            .fill(i == current ? Color.amber : (i < current ? Color.haze : Color.panel))
                            .overlay(Circle().stroke(Color.mute.opacity(i > current ? 0.6 : 0), lineWidth: 1))
                            .frame(width: 12, height: 12)
                        Text(name).font(Theme.body(11))
                            .foregroundStyle(i == current ? Color.ink : Color.mute)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(i + 1) of \(steps.count): \(name)")
                .accessibilityAddTraits(i == current ? .isSelected : [])
            }
        }
    }
}
