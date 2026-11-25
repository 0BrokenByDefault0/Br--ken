import SwiftUI
import MusicCore
import Observation

/// Lesson text: inline Markdown (bold, italics, code) that keeps the author's line breaks.
enum LessonText {
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    static func roleName(_ role: PartRole) -> String {
        role == .bass808 ? "808 bass" : role.rawValue
    }

    static func list(_ roles: [PartRole]) -> String {
        roles.map(roleName).joined(separator: ", ")
    }
}

// MARK: - Idea

struct IdeaStepView: View {
    let title: String
    let text: String
    let deeper: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(Theme.title(26)).foregroundStyle(Color.ink)
                Text(LessonText.markdown(text)).font(Theme.body(17)).foregroundStyle(Color.ink)
                if let deeper {
                    DisclosureGroup {
                        Text(LessonText.markdown(deeper)).font(Theme.body(15)).foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } label: {
                        Text("Go deeper").font(Theme.title(16)).foregroundStyle(Color.haze)
                            .frame(minHeight: Theme.minTarget)
                    }
                    .tint(Color.haze)
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

// MARK: - Listen

/// The track an example card plays: every part audible except the ones the owner muted on the card.
enum ListenPlayback {
    static func track(for clip: Clip, muted: Set<PartRole>) throws -> Track {
        var track = try clip.makeTrack(name: "Example")
        for i in track.parts.indices { track.parts[i].muted = muted.contains(track.parts[i].role) }
        return track
    }

    /// The example's chords as symbols ("Dm – B♭"), if it has a chords part.
    static func progressionText(_ track: Track) -> String? {
        for part in track.parts {
            guard case .chords(let prog) = part.content, !prog.slots.isEmpty else { continue }
            return prog.slots.map { $0.chord.symbol(in: track.key) }.joined(separator: " – ")
        }
        return nil
    }
}

/// Example cards; each plays its clip, one at a time, with a mute toggle per part. Leaving the step stops it.
struct ListenStepView: View {
    let app: AppModel
    let title: String
    let caption: String
    let examples: [Example]
    @State private var playing: Int?
    @State private var muted: [Int: Set<PartRole>] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(Theme.title(26)).foregroundStyle(Color.ink)
                Text(LessonText.markdown(caption)).font(Theme.body(16)).foregroundStyle(Color.mute)
                ForEach(examples.indices, id: \.self) { i in card(i) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .onChange(of: app.isPlaying) { _, isPlaying in if !isPlaying { playing = nil } }
        .onDisappear { if playing != nil { app.stop() } }
    }

    private func exampleTrack(_ i: Int) -> Track? {
        try? ListenPlayback.track(for: examples[i].clip, muted: muted[i] ?? [])
    }

    private func toggle(_ i: Int) {
        if playing == i {
            app.stop()
            playing = nil
        } else if let track = exampleTrack(i) {
            app.audition(track, atTrackTempo: false)
            playing = i
        }
    }

    private func toggleMute(_ role: PartRole, in i: Int) {
        var set = muted[i] ?? []
        if set.contains(role) { set.remove(role) } else { set.insert(role) }
        muted[i] = set
        if playing == i, let track = exampleTrack(i) { app.updateAudition(track) }
    }

    private func card(_ i: Int) -> some View {
        let example = examples[i]
        let track = exampleTrack(i)
        let isPlaying = playing == i
        let letter = String(UnicodeScalar(UInt8(65 + i % 26)))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(letter).font(Theme.title(34)).foregroundStyle(Color.haze).frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.label).font(Theme.title(15)).foregroundStyle(Color.night)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.haze, in: Capsule())
                    if let track, let progression = ListenPlayback.progressionText(track) {
                        Text(progression).font(Theme.mono(14)).foregroundStyle(Color.ink)
                    }
                }
                Spacer(minLength: 0)
                Button { toggle(i) } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.night)
                        .frame(width: 52, height: Theme.minTarget + 4)
                        .background(isPlaying ? Color.amber : Color.haze, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(track == nil)
                .accessibilityLabel(isPlaying ? "Stop example \(letter)" : "Play example \(letter)")
            }
            Text(LessonText.markdown(example.explanation)).font(Theme.body(15)).foregroundStyle(Color.ink)
            if let track {
                if track.parts.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(track.parts) { part in
                                let on = !part.muted
                                Button { toggleMute(part.role, in: i) } label: {
                                    Label(LessonText.roleName(part.role), systemImage: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                        .font(Theme.body(14)).foregroundStyle(on ? Color.ink : Color.mute)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: Theme.minTarget)
                                        .background(Color.night, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(PressableButtonStyle())
                                .accessibilityValue(on ? "On" : "Muted")
                            }
                        }
                    }
                }
            } else {
                Text("This example can't be played.").font(Theme.body(14)).foregroundStyle(Color.clash)
            }
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) {
            if isPlaying, let track { PlayheadBar(app: app, loopTicks: max(track.bars, 1) * Ticks.perBar) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A thin bar along a card's bottom edge showing where the loop is.
private struct PlayheadBar: View {
    let app: AppModel
    let loopTicks: Int

    var body: some View {
        TimelineView(.animation) { _ in
            GeometryReader { geo in
                let fraction = Double(app.audio.playheadTick % loopTicks) / Double(loopTicks)
                Rectangle().fill(Color.amber).frame(width: geo.size.width * fraction, height: 3)
            }
            .frame(height: 3)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Task

/// The prompt, the tool for the task's `ToolKind` on the working track, Check with ✓/✕ results, and hints.
struct TaskStepView: View {
    let task: TaskStepModel
    let app: AppModel
    @State private var melody: LessonMelodyTool?
    @State private var grid: DrumGridModel?
    @State private var finder: ChordFinderModel?
    @State private var showSevenths = false
    @State private var scaleLock = false
    @State private var octave = 4

    init(task: TaskStepModel, app: AppModel) {
        self.task = task
        self.app = app
        let working = task.working
        switch task.tool {
        case .melodyEditor:
            _melody = State(initialValue: LessonMelodyTool(task: task, app: app))
        case .drumGrid:
            var pattern = DrumPattern(lanes: [:])
            if case .drums(let p)? = task.targetPart?.content { pattern = p }
            let grid = DrumGridModel(pattern: pattern, bars: working.bars)
            grid.onChange = { [weak task] pattern in task?.editTarget { $0.content = .drums(pattern) } }
            _grid = State(initialValue: grid)
        case .chordFinder:
            let finder = ChordFinderModel(melody: Self.melody(of: working), bars: working.bars, key: working.key)
            finder.tempo = working.tempo
            if case .chords(let p)? = task.targetPart?.content { finder.progression = p }
            _finder = State(initialValue: finder)
        case .chordPads, .trackSetup:
            break
        }
    }

    private static func melody(of track: Track) -> NoteSequence {
        if case .notes(let s)? = track.part(.melody)?.content { return s }
        return NoteSequence(notes: [])
    }

    private var progression: ChordProgression {
        if case .chords(let p)? = task.targetPart?.content { return p }
        return ChordProgression(slots: [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(task.title).font(Theme.title(24)).foregroundStyle(Color.ink)
                Text(LessonText.markdown(task.prompt)).font(Theme.body(16)).foregroundStyle(Color.ink)
                if task.tool != .trackSetup { playRow }
                tool
                if !task.checks.isEmpty { checkSection }
                hintSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let melody {
                KeyboardView(key: task.working.key, scale: task.working.key.mode == .major ? .major : .naturalMinor,
                             scaleLock: $scaleLock, octave: $octave, instrument: melody.instrument,
                             onNote: { pitch, on in melody.keyEvent(pitch: pitch, on: on) })
                    .padding(.horizontal, 8).padding(.top, 8)
                    .background(Color.night)
            }
        }
        .onChange(of: app.isPlaying) { _, playing in if !playing { melody?.stopped() } }
    }

    private var playRow: some View {
        HStack(spacing: 12) {
            Button { app.isPlaying ? task.stop() : task.play() } label: {
                Label(app.isPlaying ? "Stop" : "Play loop", systemImage: app.isPlaying ? "stop.fill" : "play.fill")
                    .font(Theme.title(16)).foregroundStyle(Color.night)
                    .padding(.horizontal, 18)
                    .frame(minHeight: Theme.minTarget + 4)
                    .background(app.isPlaying ? Color.amber : Color.haze, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressableButtonStyle())
            Text("\(task.working.key.name) · \(Int(task.working.tempo.rounded())) BPM · \(task.working.bars) bars")
                .font(Theme.mono(12)).foregroundStyle(Color.mute)
        }
    }

    @ViewBuilder
    private var tool: some View {
        switch task.tool {
        case .trackSetup:
            TrackSetupView(tempo: task.working.tempo, key: task.working.key, name: task.working.name, live: true) { name, tempo, key in
                task.edit { $0.name = name; $0.tempo = tempo; $0.key = key }
            }
        case .melodyEditor:
            if let melody {
                Button { melody.toggleRecording() } label: {
                    Label(melody.isRecording ? "Recording… tap to finish" : "Record from keyboard", systemImage: "record.circle")
                        .font(Theme.title(16))
                        .foregroundStyle(melody.isRecording ? Color.night : Color.clash)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                        .background(melody.isRecording ? Color.clash : Color.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableButtonStyle())
                PianoRollView(model: melody.roll, playheadTick: { app.audio.playheadTick }, isPlaying: app.isPlaying,
                              onAudition: { melody.audition($0) })
            }
        case .chordPads:
            let instrument = task.targetPart?.instrument ?? .pad
            ChordPadsView(key: task.working.key,
                          showSevenths: $showSevenths,
                          onChord: { _ in },
                          progression: Binding(get: { progression },
                                               set: { p in task.editTarget { $0.content = .chords(p) } }),
                          bars: task.working.bars,
                          onNote: { pitch, on in
                              if on { app.audio.noteOn(instrument, pitch, 0.8) } else { app.audio.noteOff(instrument, pitch) }
                          })
        case .chordFinder:
            if let finder {
                ChordFinderView(model: finder, isPlaying: app.isPlaying,
                                onPlay: { app.audition($0, atTrackTempo: false) }, onStop: { app.stop() })
                    .onChange(of: finder.progression) { _, p in
                        if task.targetPart?.content != .chords(p) { task.editTarget { $0.content = .chords(p) } }
                    }
            }
        case .drumGrid:
            if let grid {
                HStack(spacing: 12) {
                    Text("Swing").font(Theme.body(14)).foregroundStyle(Color.ink)
                    Slider(value: Binding(get: { grid.swing }, set: { grid.swing = $0 }), in: DrumGridModel.swingRange)
                        .tint(Color.haze)
                        .frame(minHeight: Theme.minTarget)
                        .accessibilityLabel("Swing")
                    Text("\(Int((grid.swing * 100).rounded()))%")
                        .font(Theme.mono(13)).foregroundStyle(Color.mute).frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 14))
                DrumGridView(model: grid, playheadTick: { app.audio.playheadTick }, isPlaying: app.isPlaying,
                             onPad: { lane, v in app.audio.noteOn(.trapKit, lane.midiNote, v) })
            }
        }
    }

    private var checkLabel: String {
        switch task.tool {
        case .trackSetup: "Check my setup"
        case .melodyEditor: "Check my melody"
        case .chordPads, .chordFinder: "Check my chords"
        case .drumGrid: "Check my beat"
        }
    }

    private var checkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { task.runChecks() } label: {
                Text(checkLabel).font(Theme.title(17)).foregroundStyle(Color.night)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTarget + 6)
                    .background(Color.tone, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
            ForEach(Array(task.results.enumerated()), id: \.offset) { _, result in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: result.passed ? "checkmark" : "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(result.passed ? Color.tone : Color.clash)
                        .accessibilityLabel(result.passed ? "Passed" : "Not yet")
                    Text(result.message).font(Theme.body(15)).foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
            }
            if task.allPassed {
                Text("All checks pass.").font(Theme.body(14)).foregroundStyle(Color.tone)
            }
        }
    }

    @ViewBuilder
    private var hintSection: some View {
        if !task.hints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(task.shownHints.enumerated()), id: \.offset) { _, hint in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "lightbulb.fill").foregroundStyle(Color.amber)
                        Text(LessonText.markdown(hint)).font(Theme.body(15)).foregroundStyle(Color.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                if task.hintIndex < task.hints.count {
                    Button { _ = task.nextHint() } label: {
                        Label(task.hintIndex == 0 ? "Show a hint" : "Another hint", systemImage: "lightbulb")
                            .font(Theme.body(15)).foregroundStyle(Color.amber)
                            .frame(minHeight: Theme.minTarget)
                    }
                }
            }
        }
    }
}

/// Melody editing inside a task: the piano roll and live recording write the working track's target part.
@Observable @MainActor
final class LessonMelodyTool {
    let roll: PianoRollModel
    let instrument: InstrumentID
    private(set) var isRecording = false
    private let task: TaskStepModel
    private let app: AppModel
    private var recorder = LiveRecorder()

    init(task: TaskStepModel, app: AppModel) {
        self.task = task
        self.app = app
        let working = task.working
        instrument = task.targetPart?.instrument ?? MelodyToolModel.defaultInstrument
        var sequence = NoteSequence(notes: [])
        if case .notes(let s)? = task.targetPart?.content { sequence = s }
        roll = PianoRollModel(sequence: sequence, bars: working.bars, key: working.key,
                              lowestPitch: 48 + working.key.tonic.rawValue)
        roll.onChange = { [weak task] sequence in task?.editTarget { $0.content = .notes(sequence) } }
    }

    func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            recorder = LiveRecorder()
            isRecording = true
            if !app.isPlaying { task.play() }
        }
    }

    func stopped() { if isRecording { finishRecording() } }

    private func finishRecording() {
        isRecording = false
        roll.merge(recorder.result(loopTicks: roll.loopTicks))
    }

    func keyEvent(pitch: Int, on: Bool) {
        if on {
            app.audio.noteOn(instrument, pitch, 0.8)
            if isRecording { recorder.noteOn(pitch: pitch, atTick: app.audio.playheadTick) }
        } else {
            app.audio.noteOff(instrument, pitch)
            if isRecording { recorder.noteOff(pitch: pitch, atTick: app.audio.playheadTick) }
        }
    }

    func audition(_ pitch: Int) {
        let audio = app.audio, instrument = instrument
        audio.noteOn(instrument, pitch, 0.8)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            audio.noteOff(instrument, pitch)
        }
    }
}

// MARK: - Keep

/// Shows the message and saves the lesson's result to Your Track. For each role Your Track already has
/// (with a different part), it asks first: replace it, or keep the owner's.
struct KeepStepView: View {
    let player: LessonPlayerModel
    let app: AppModel
    let index: Int
    let message: String
    let roles: [PartRole]
    @State private var asking: PartRole?
    @State private var queue: [PartRole] = []
    @State private var chosen: [PartRole] = []
    @State private var saved: [PartRole]?

    private var isSetup: Bool { player.keepsSetup(at: index) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keep it").font(Theme.title(26)).foregroundStyle(Color.ink)
                Text(LessonText.markdown(message)).font(Theme.body(17)).foregroundStyle(Color.ink)
                if player.kept.contains(index) {
                    savedPanel
                } else {
                    Text(isSetup ? "Saves the name, tempo, and key to Your Track."
                         : roles.isEmpty ? "Marks this lesson done on Your Track."
                         : "Saves your \(LessonText.list(roles)) to Your Track.")
                        .font(Theme.body(15)).foregroundStyle(Color.mute)
                    saveButton("Save to Your Track")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .confirmationDialog(asking.map { "Your Track already has \(LessonText.roleName($0))" } ?? "",
                            isPresented: Binding(get: { asking != nil }, set: { dialogPresented($0) }),
                            titleVisibility: .visible) {
            Button("Replace", role: .destructive) { answer(replace: true) }
            Button("Keep mine", role: .cancel) { answer(replace: false) }
        } message: {
            Text("Replace it with the one from this lesson, or keep yours?")
        }
    }

    private var savedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Saved to Your Track", systemImage: "checkmark.circle.fill")
                .font(Theme.title(18)).foregroundStyle(Color.tone)
            if let saved, !isSetup {
                let skipped = roles.filter { !saved.contains($0) }
                if !saved.isEmpty {
                    Text("Saved: \(LessonText.list(saved))").font(Theme.body(15)).foregroundStyle(Color.ink)
                }
                if !skipped.isEmpty {
                    Text("Kept yours: \(LessonText.list(skipped))").font(Theme.body(15)).foregroundStyle(Color.mute)
                }
            }
            if let track = app.activeTrack {
                HStack(spacing: 12) {
                    Button { app.isPlaying ? app.stop() : app.play() } label: {
                        Image(systemName: app.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.night)
                            .frame(width: 48, height: Theme.minTarget)
                            .background(app.isPlaying ? Color.amber : Color.haze, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(app.isPlaying ? "Stop Your Track" : "Play Your Track")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name).font(Theme.title(16)).foregroundStyle(Color.ink)
                        Text("\(track.key.name) · \(Int(track.tempo.rounded())) BPM · "
                             + (track.parts.isEmpty ? "no parts yet" : LessonText.list(track.parts.map(\.role))))
                            .font(Theme.mono(12)).foregroundStyle(Color.mute)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.night, in: RoundedRectangle(cornerRadius: 12))
            }
            Button("Save again") { save() }
                .font(Theme.body(15)).foregroundStyle(Color.haze)
                .frame(minHeight: Theme.minTarget)
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private func saveButton(_ title: String) -> some View {
        Button { save() } label: {
            Text(title).font(Theme.title(17)).foregroundStyle(Color.night)
                .frame(maxWidth: .infinity, minHeight: Theme.minTarget + 6)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func save() {
        let conflicts = player.conflictingRoles(forKeepAt: index)
        chosen = roles.filter { !conflicts.contains($0) }
        queue = conflicts
        askNext()
    }

    private func askNext() {
        if queue.isEmpty {
            player.keep(at: index, roles: chosen)
            saved = chosen
        } else {
            asking = queue.removeFirst()
        }
    }

    private func answer(replace: Bool) {
        guard let role = asking else { return }
        if replace { chosen.append(role) }
        asking = nil
        if queue.isEmpty {
            askNext()
        } else {
            // Let this dialog finish dismissing before the next one is presented.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                askNext()
            }
        }
    }

    /// A dismissal without a button (tapping outside) counts as "Keep mine".
    private func dialogPresented(_ presented: Bool) {
        guard !presented, let role = asking else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            if asking == role { answer(replace: false) }
        }
    }
}

// MARK: - Koala

/// The mission text and the button that opens the Export sheet.
struct KoalaStepView: View {
    let text: String
    @State private var exporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Koala").font(Theme.title(26)).foregroundStyle(Color.ink)
                Text(LessonText.markdown(text)).font(Theme.body(17)).foregroundStyle(Color.ink)
                Button { exporting = true } label: {
                    Label("Export loop to Koala", systemImage: "square.and.arrow.up")
                        .font(Theme.title(17)).foregroundStyle(Color.night)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTarget + 6)
                        .background(Color.amber, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressableButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .sheet(isPresented: $exporting) { exportSheet }
    }

    /// The Export sheet hook (Task 19 replaces the placeholder here).
    private var exportSheet: some View { ExportPlaceholderSheet() }
}

private struct ExportPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Export is coming in the next step of the build")
                .font(Theme.title(18)).foregroundStyle(Color.ink)
                .multilineTextAlignment(.center).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.night.ignoresSafeArea())
                .navigationTitle("Export")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}
