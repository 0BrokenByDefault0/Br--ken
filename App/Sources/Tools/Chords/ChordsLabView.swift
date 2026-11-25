import SwiftUI
import MusicCore
import Observation

/// Temporary screen for chord pads and the Chord Finder on a scratch melody (replaced when the real
/// navigation lands).
@Observable @MainActor
final class ChordsLabModel {
    static let key = Key(tonic: PitchClass(9), mode: .minor)
    static let melody = NoteSequence(notes: [
        NoteEvent(start: 0, length: 96, pitch: 69), NoteEvent(start: 96, length: 96, pitch: 72),
        NoteEvent(start: 192, length: 96, pitch: 76), NoteEvent(start: 288, length: 96, pitch: 74),
        NoteEvent(start: 384, length: 96, pitch: 77), NoteEvent(start: 480, length: 96, pitch: 76),
        NoteEvent(start: 576, length: 96, pitch: 72), NoteEvent(start: 672, length: 96, pitch: 69),
    ])

    let finder = ChordFinderModel(melody: melody, bars: 2, key: key)
    var showSevenths = false
    var isPlaying = false
    private let audio: any AudioPlaying

    init(audio: any AudioPlaying) { self.audio = audio }

    func play(_ track: Track) {
        audio.setTrack(track)
        audio.play()
        isPlaying = true
    }

    func stop() {
        audio.stop()
        isPlaying = false
    }

    func note(_ pitch: Int, on: Bool) {
        if on { audio.noteOn(.pad, pitch, 0.8) } else { audio.noteOff(.pad, pitch) }
    }
}

struct ChordsLabView: View {
    @State private var model: ChordsLabModel
    private let isActive: Bool

    init(audio: any AudioPlaying, isActive: Bool = true) {
        _model = State(initialValue: ChordsLabModel(audio: audio))
        self.isActive = isActive
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Chord lab").font(Theme.title(24)).foregroundStyle(Color.ink)
                    Spacer()
                    Text("A minor · 2 bars").font(Theme.mono(12)).foregroundStyle(Color.mute)
                }
                ChordPadsView(key: ChordsLabModel.key,
                              showSevenths: Binding(get: { model.showSevenths }, set: { model.showSevenths = $0 }),
                              onChord: { _ in },
                              progression: Binding(get: { model.finder.progression }, set: { model.finder.progression = $0 }),
                              bars: model.finder.bars,
                              onNote: { pitch, on in model.note(pitch, on: on) })
                ChordFinderView(model: model.finder, isPlaying: model.isPlaying,
                                onPlay: { model.play($0) }, onStop: { model.stop() })
            }
            .padding(16)
        }
        .background(Color.night.ignoresSafeArea())
        .onChange(of: isActive) { _, active in
            if !active, model.isPlaying { model.stop() }
        }
    }
}
