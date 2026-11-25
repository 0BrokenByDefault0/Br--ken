import SwiftUI
import MusicCore
import Observation

/// Melody tool state on the active track's melody part (created empty on the first edit).
@Observable @MainActor
final class MelodyToolModel {
    static let defaultInstrument = InstrumentID.bell

    let roll: PianoRollModel
    private(set) var isRecording = false
    let instrument: InstrumentID
    private let app: AppModel
    private var recorder = LiveRecorder()

    init(app: AppModel, track: Track) {
        self.app = app
        instrument = track.part(.melody)?.instrument ?? Self.defaultInstrument
        var sequence = NoteSequence(notes: [])
        if case .notes(let s)? = track.part(.melody)?.content { sequence = s }
        roll = PianoRollModel(sequence: sequence, bars: track.bars, key: track.key,
                              lowestPitch: 48 + track.key.tonic.rawValue)
        roll.onChange = { [weak self] sequence in self?.write(sequence) }
    }

    private func write(_ sequence: NoteSequence) {
        app.editActivePart(.melody, instrument: Self.defaultInstrument, empty: .notes(NoteSequence(notes: []))) {
            $0.content = .notes(sequence)
        }
    }

    func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            recorder = LiveRecorder()
            isRecording = true
            if !app.isPlaying { app.play() }
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
