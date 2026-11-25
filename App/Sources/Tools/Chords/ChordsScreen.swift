import SwiftUI
import MusicCore

/// Chords tab: chord pads and the Chord Finder on the active track's melody. Chosen chords are written
/// to the active track's chords part (created empty on the first edit).
struct ChordsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let track = model.activeTrack {
            ChordsBody(app: model, track: track).id(track.id)
        } else {
            NoTrackView(tool: "The chord finder")
        }
    }
}

private struct ChordsBody: View {
    let app: AppModel
    @State private var finder: ChordFinderModel
    @State private var showSevenths = false
    private let key: Key

    init(app: AppModel, track: Track) {
        self.app = app
        key = track.key
        var melody = NoteSequence(notes: [])
        if case .notes(let s)? = track.part(.melody)?.content { melody = s }
        let finder = ChordFinderModel(melody: melody, bars: track.bars, key: track.key)
        finder.tempo = track.tempo
        if case .chords(let p)? = track.part(.chords)?.content { finder.progression = p }
        _finder = State(initialValue: finder)
    }

    private var melody: NoteSequence {
        if case .notes(let s)? = app.activeTrack?.part(.melody)?.content { return s }
        return NoteSequence(notes: [])
    }

    private var chordsContent: PartContent? { app.activeTrack?.part(.chords)?.content }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Chords").font(Theme.title(24)).foregroundStyle(Color.ink)
                    Spacer()
                    Text("\(key.name) · \(finder.bars) bars").font(Theme.mono(12)).foregroundStyle(Color.mute)
                }
                TrackTransport()
                ChordPadsView(key: key,
                              showSevenths: $showSevenths,
                              onChord: { _ in },
                              progression: Binding(get: { finder.progression }, set: { finder.progression = $0 }),
                              bars: finder.bars,
                              onNote: { pitch, on in
                                  if on { app.audio.noteOn(.pad, pitch, 0.8) } else { app.audio.noteOff(.pad, pitch) }
                              })
                ChordFinderView(model: finder, isPlaying: app.isPlaying,
                                onPlay: { app.audition($0) }, onStop: { app.stop() })
            }
            .padding(16)
        }
        .background(Color.night.ignoresSafeArea())
        .onChange(of: finder.progression) { _, progression in
            if chordsContent == .chords(progression) { return }
            app.editActivePart(.chords, instrument: .pad, empty: .chords(ChordProgression(slots: []))) {
                $0.content = .chords(progression)
            }
        }
        .onChange(of: melody) { _, melody in finder.update(melody: melody) }
        .onChange(of: chordsContent) { _, content in
            if case .chords(let p)? = content, p != finder.progression { finder.progression = p }
        }
    }
}
