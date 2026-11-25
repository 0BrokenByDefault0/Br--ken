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
    @State private var showSevenths = false
    @State private var scaleLock = false
    @State private var octave = 4

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
            if task.tool == .melodyEditor {
                let melody = task.melodyTool
                KeyboardView(key: task.working.key, scale: task.working.key.mode == .major ? .major : .naturalMinor,
                             scaleLock: $scaleLock, octave: $octave, instrument: melody.instrument,
                             onNote: { pitch, on in melody.keyEvent(pitch: pitch, on: on) })
                    .padding(.horizontal, 8).padding(.top, 8)
                    .background(Color.night)
            }
        }
        .onChange(of: app.isPlaying) { _, playing in if !playing { task.finishRecording() } }
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
            // Your Track keeps its name; a name is only asked for when the lesson creates the track.
            TrackSetupView(tempo: task.working.tempo, key: task.working.key, name: task.working.name,
                           live: true, showsName: app.activeTrack == nil) { name, tempo, key in
                task.edit { $0.name = name; $0.tempo = tempo; $0.key = key }
            }
        case .melodyEditor:
            let melody = task.melodyTool
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
            let finder = task.chordFinder
            ChordFinderView(model: finder, isPlaying: app.isPlaying,
                            onPlay: { app.audition($0, atTrackTempo: false) }, onStop: { app.stop() })
                .onChange(of: finder.progression) { _, p in
                    if task.targetPart?.content != .chords(p) { task.editTarget { $0.content = .chords(p) } }
                }
        case .drumGrid:
            let grid = task.drumGrid
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

// MARK: - Keep

/// Shows the message and saves the lesson's result to Your Track. Roles the owner hasn't built are named
/// and skipped; for each role Your Track already has (with a different part) the owner picks Replace or
/// Keep mine (the default) before one "Save to Your Track" tap.
struct KeepStepView: View {
    let player: LessonPlayerModel
    let app: AppModel
    let index: Int
    let message: String

    private var isSetup: Bool { player.keepsSetup(at: index) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keep it").font(Theme.title(26)).foregroundStyle(Color.ink)
                Text(LessonText.markdown(message)).font(Theme.body(17)).foregroundStyle(Color.ink)
                if let saved = player.saved[index] {
                    savedPanel(saved)
                } else {
                    plan
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder
    private var plan: some View {
        let toSave = player.rolesToSave(atKeep: index)
        ForEach(player.emptyRoles(forKeepAt: index), id: \.self) { role in
            notBuilt(role)
        }
        ForEach(player.conflictingRoles(forKeepAt: index), id: \.self) { role in
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Track already has \(LessonText.roleName(role))")
                    .font(Theme.title(15)).foregroundStyle(Color.ink)
                Picker("Your Track already has \(LessonText.roleName(role))",
                       selection: Binding(get: { player.replaces(role, atKeep: index) },
                                          set: { player.setReplace($0, role: role, atKeep: index) })) {
                    Text("Keep mine").tag(false)
                    Text("Replace").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: Theme.minTarget)
            }
            .padding(12)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
        }
        Text(isSetup ? "Saves the tempo and key to Your Track."
             : toSave.isEmpty ? "Nothing new to save; this marks the lesson done."
             : "Saves your \(LessonText.list(toSave)) to Your Track.")
            .font(Theme.body(15)).foregroundStyle(Color.mute)
        Button { player.saveKeep(at: index) } label: {
            Text("Save to Your Track").font(Theme.title(17)).foregroundStyle(Color.night)
                .frame(maxWidth: .infinity, minHeight: Theme.minTarget + 6)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func notBuilt(_ role: PartRole) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Color.amber)
            Text("You haven't made a \(LessonText.roleName(role)) part yet — go back to the task, or continue without it.")
                .font(Theme.body(15)).foregroundStyle(Color.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func savedPanel(_ saved: [PartRole]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Saved to Your Track", systemImage: "checkmark.circle.fill")
                .font(Theme.title(18)).foregroundStyle(Color.tone)
            if !isSetup {
                let skipped = player.keepRoles(at: index).filter { !saved.contains($0) }
                if !saved.isEmpty {
                    Text("Saved: \(LessonText.list(saved))").font(Theme.body(15)).foregroundStyle(Color.ink)
                }
                if !skipped.isEmpty {
                    Text("Not saved: \(LessonText.list(skipped))").font(Theme.body(15)).foregroundStyle(Color.mute)
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
            Button("Save again") { player.saveKeep(at: index) }
                .font(Theme.body(15)).foregroundStyle(Color.haze)
                .frame(minHeight: Theme.minTarget)
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
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
