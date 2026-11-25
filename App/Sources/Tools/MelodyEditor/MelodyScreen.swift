import SwiftUI
import MusicCore
import Observation

/// Melody tool state: the piano roll over a melody part, and live recording from the keyboard.
/// Where edits go and which loop plays are injected, so the Melody tab (the active track) and a lesson
/// task (its working track) share it.
@Observable @MainActor
final class MelodyToolModel {
    static let defaultInstrument = InstrumentID.bell

    let roll: PianoRollModel
    private(set) var isRecording = false
    let instrument: InstrumentID
    private let audio: any AudioPlaying
    private let isPlaying: () -> Bool
    private let startPlayback: () -> Void
    private var recorder = LiveRecorder()

    /// `part`: the melody part being edited (nil when there is none yet). `write` gets the sequence after
    /// every edit; recording starts the loop with `play` when `isPlaying` says it is stopped.
    init(part: Part?, bars: Int, key: Key, audio: any AudioPlaying, isPlaying: @escaping () -> Bool,
         play: @escaping () -> Void, write: @escaping (NoteSequence) -> Void) {
        self.audio = audio
        self.isPlaying = isPlaying
        startPlayback = play
        instrument = part?.instrument ?? Self.defaultInstrument
        var sequence = NoteSequence(notes: [])
        if case .notes(let s)? = part?.content { sequence = s }
        roll = PianoRollModel(sequence: sequence, bars: bars, key: key, lowestPitch: 48 + key.tonic.rawValue)
        roll.onChange = write
    }

    /// On the active track's melody part (created empty on the first edit), looping the active track.
    convenience init(app: AppModel, track: Track) {
        self.init(part: track.part(.melody), bars: track.bars, key: track.key, audio: app.audio,
                  isPlaying: { [weak app] in app?.isPlaying ?? false },
                  play: { [weak app] in app?.play() },
                  write: { [weak app] sequence in
                      app?.editActivePart(.melody, instrument: MelodyToolModel.defaultInstrument,
                                          empty: .notes(NoteSequence(notes: []))) { $0.content = .notes(sequence) }
                  })
    }

    func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            recorder = LiveRecorder()
            isRecording = true
            if !isPlaying() { startPlayback() }
        }
    }

    func stopped() { if isRecording { finishRecording() } }

    private func finishRecording() {
        isRecording = false
        roll.merge(recorder.result(loopTicks: roll.loopTicks))
    }

    func keyEvent(pitch: Int, on: Bool) {
        if on {
            audio.noteOn(instrument, pitch, 0.8)
            if isRecording { recorder.noteOn(pitch: pitch, atTick: audio.playheadTick) }
        } else {
            audio.noteOff(instrument, pitch)
            if isRecording { recorder.noteOff(pitch: pitch, atTick: audio.playheadTick) }
        }
    }

    func audition(_ pitch: Int) {
        let audio = audio, instrument = instrument
        audio.noteOn(instrument, pitch, 0.8)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            audio.noteOff(instrument, pitch)
        }
    }
}

/// Melody tab: keyboard, piano roll, record, sound controls, and the loop of the whole active track.
struct MelodyScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let track = model.activeTrack {
            MelodyEditorBody(app: model, track: track).id(track.id)
        } else {
            NoTrackView(tool: "The melody editor")
        }
    }
}

private struct MelodyEditorBody: View {
    let app: AppModel
    @State private var tool: MelodyToolModel
    @State private var scaleLock = false
    @State private var octave = 4
    private let key: Key

    init(app: AppModel, track: Track) {
        self.app = app
        key = track.key
        _tool = State(initialValue: MelodyToolModel(app: app, track: track))
    }

    private var melodyContent: PartContent? { app.activeTrack?.part(.melody)?.content }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Melody").font(Theme.title(24)).foregroundStyle(Color.ink)
                    Spacer()
                    Text("\(key.name) · \(tool.instrument.rawValue) · \(tool.roll.bars) bars")
                        .font(Theme.mono(12)).foregroundStyle(Color.mute)
                }
                TrackTransport()
                Button { tool.toggleRecording() } label: {
                    Label(tool.isRecording ? "Recording… tap to finish" : "Record from keyboard",
                          systemImage: "record.circle")
                        .font(Theme.title(16))
                        .foregroundStyle(tool.isRecording ? Color.night : Color.clash)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                        .background(tool.isRecording ? Color.clash : Color.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableButtonStyle())
                PianoRollView(model: tool.roll, playheadTick: { app.audio.playheadTick }, isPlaying: app.isPlaying,
                              onAudition: { tool.audition($0) })
                SoundControlsView(settings: Binding(
                    get: { app.activeTrack?.part(.melody)?.sound ?? SoundSettings() },
                    set: { value in
                        app.editActivePart(.melody, instrument: MelodyToolModel.defaultInstrument,
                                           empty: .notes(NoteSequence(notes: [])), persist: false) { $0.sound = value }
                    }),
                    onCommit: { app.commitActiveTrack() })
            }
            .padding(16)
        }
        // The keyboard stays put at the bottom; only the rest scrolls.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            KeyboardView(key: key, scale: key.mode == .major ? .major : .naturalMinor,
                         scaleLock: $scaleLock, octave: $octave, instrument: tool.instrument,
                         onNote: { pitch, on in tool.keyEvent(pitch: pitch, on: on) })
                .padding(.horizontal, 8).padding(.top, 8)
                .background(Color.night)
        }
        .background(Color.night.ignoresSafeArea())
        .onChange(of: app.isPlaying) { _, playing in if !playing { tool.stopped() } }
        // The melody changed elsewhere (a lesson kept one): show it.
        .onChange(of: melodyContent) { _, content in
            if case .notes(let s)? = content, s != tool.roll.sequence { tool.roll.sequence = s }
        }
    }
}
