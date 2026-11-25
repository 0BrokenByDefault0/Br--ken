import SwiftUI
import MusicCore
import Observation

/// Temporary root screen (owner checkpoint for instrument feel): keyboard, piano roll and transport on a
/// scratch track. Replaced when the real navigation lands.
@Observable @MainActor
final class MelodyLabModel {
    static let instrument = InstrumentID.bell
    static let key = Key(tonic: PitchClass(9), mode: .minor)

    private(set) var track: Track
    let roll: PianoRollModel
    var isPlaying = false
    var isRecording = false
    var metronome = false { didSet { pushTrack() } }
    var tempo: Double {
        get { track.tempo }
        set { track.tempo = newValue; pushTrack() }
    }
    var sound: SoundSettings {
        get { track.part(.melody)?.sound ?? SoundSettings() }
        set {
            guard var part = track.part(.melody) else { return }
            part.sound = newValue
            track.setPart(part)
            pushTrack()
        }
    }

    private let audio: any AudioPlaying
    private var recorder = LiveRecorder()

    init(audio: any AudioPlaying) {
        self.audio = audio
        let part = Part(role: .melody, instrument: Self.instrument, content: .notes(NoteSequence(notes: [])))
        track = Track(name: "Scratch", createdAt: Date(), tempo: 140, key: Self.key, bars: 2, parts: [part])
        roll = PianoRollModel(sequence: NoteSequence(notes: []), bars: 2, key: Self.key, lowestPitch: 57)
        roll.onChange = { [weak self] sequence in self?.melodyChanged(sequence) }
        pushTrack()
    }

    var playheadTick: Int { audio.playheadTick }

    func play() {
        pushTrack()
        audio.play()
        isPlaying = true
    }

    func stop() {
        if isRecording { finishRecording() }
        audio.stop()
        isPlaying = false
    }

    func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            recorder = LiveRecorder()
            isRecording = true
            if !isPlaying { play() }
        }
    }

    func keyEvent(pitch: Int, on: Bool) {
        if on {
            audio.noteOn(Self.instrument, pitch, 0.8)
            if isRecording { recorder.noteOn(pitch: pitch, atTick: audio.playheadTick) }
        } else {
            audio.noteOff(Self.instrument, pitch)
            if isRecording { recorder.noteOff(pitch: pitch, atTick: audio.playheadTick) }
        }
    }

    func audition(_ pitch: Int) {
        audio.noteOn(Self.instrument, pitch, 0.8)
        let audio = self.audio
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            audio.noteOff(Self.instrument, pitch)
        }
    }

    private func finishRecording() {
        isRecording = false
        roll.merge(recorder.result(loopTicks: track.bars * Ticks.perBar))
    }

    private func melodyChanged(_ sequence: NoteSequence) {
        guard var part = track.part(.melody) else { return }
        part.content = .notes(sequence)
        track.setPart(part)
        pushTrack()
    }

    private func pushTrack() {
        audio.setTrack(metronome ? withMetronome(track) : track)
    }
}

struct MelodyLabView: View {
    @State private var model: MelodyLabModel
    @State private var scaleLock = false
    @State private var octave = 4

    init(audio: any AudioPlaying) {
        _model = State(initialValue: MelodyLabModel(audio: audio))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Melody lab").font(Theme.title(24)).foregroundStyle(Color.ink)
                    Spacer()
                    Text("A minor · bell · 2 bars").font(Theme.mono(12)).foregroundStyle(Color.mute)
                }
                TransportBar(isPlaying: model.isPlaying,
                             tempo: Binding(get: { model.tempo }, set: { model.tempo = $0 }),
                             metronome: Binding(get: { model.metronome }, set: { model.metronome = $0 }),
                             onPlay: { model.play() }, onStop: { model.stop() })
                Button { model.toggleRecording() } label: {
                    Label(model.isRecording ? "Recording… tap to finish" : "Record from keyboard",
                          systemImage: "record.circle")
                        .font(Theme.title(16))
                        .foregroundStyle(model.isRecording ? Color.night : Color.clash)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                        .background(model.isRecording ? Color.clash : Color.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableButtonStyle())
                PianoRollView(model: model.roll, playheadTick: { model.playheadTick }, isPlaying: model.isPlaying,
                              onAudition: { model.audition($0) })
                SoundControlsView(settings: Binding(get: { model.sound }, set: { model.sound = $0 }))
            }
            .padding(16)
        }
        // The keyboard stays put at the bottom; only the rest scrolls.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            KeyboardView(key: MelodyLabModel.key, scale: .naturalMinor, scaleLock: $scaleLock, octave: $octave,
                         instrument: MelodyLabModel.instrument,
                         onNote: { pitch, on in model.keyEvent(pitch: pitch, on: on) })
                .padding(.horizontal, 8).padding(.top, 8)
                .background(Color.night)
        }
        .background(Color.night.ignoresSafeArea())
    }
}
