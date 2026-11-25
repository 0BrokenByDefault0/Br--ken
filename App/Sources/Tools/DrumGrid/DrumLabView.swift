import SwiftUI
import MusicCore
import Observation

/// Temporary screen for the drum grid on a scratch track (replaced when the real navigation lands).
@Observable @MainActor
final class DrumLabModel {
    static let bars = 2
    private(set) var track: Track
    let grid: DrumGridModel
    var isPlaying = false
    var metronome = false { didSet { pushTrack() } }
    var tempo: Double {
        get { track.tempo }
        set { track.tempo = newValue; pushTrack() }
    }

    private let audio: any AudioPlaying

    init(audio: any AudioPlaying) {
        self.audio = audio
        let pattern = DrumPattern(lanes: [:])
        let part = Part(role: .drums, instrument: .trapKit, content: .drums(pattern))
        track = Track(name: "Scratch", createdAt: Date(), tempo: 140, key: Key(tonic: PitchClass(9), mode: .minor),
                      bars: Self.bars, parts: [part])
        grid = DrumGridModel(pattern: pattern, bars: Self.bars)
        grid.onChange = { [weak self] pattern in self?.patternChanged(pattern) }
    }

    var playheadTick: Int { audio.playheadTick }

    func play() {
        pushTrack()
        audio.play()
        isPlaying = true
    }

    func stop() {
        audio.stop()
        isPlaying = false
    }

    func pad(_ lane: DrumLane, _ velocity: Float) {
        audio.noteOn(.trapKit, lane.midiNote, velocity)  // drum voices ignore note-off
    }

    private func patternChanged(_ pattern: DrumPattern) {
        guard var part = track.part(.drums) else { return }
        part.content = .drums(pattern)
        track.setPart(part)
        pushTrack()
    }

    private func pushTrack() {
        audio.setTrack(metronome ? withMetronome(track) : track)
    }
}

struct DrumLabView: View {
    @State private var model: DrumLabModel

    /// False while another screen is shown: playback then stops.
    private let isActive: Bool

    init(audio: any AudioPlaying, isActive: Bool = true) {
        _model = State(initialValue: DrumLabModel(audio: audio))
        self.isActive = isActive
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Drum lab").font(Theme.title(24)).foregroundStyle(Color.ink)
                    Spacer()
                    Text("trap kit · 2 bars").font(Theme.mono(12)).foregroundStyle(Color.mute)
                }
                TransportBar(isPlaying: model.isPlaying,
                             tempo: Binding(get: { model.tempo }, set: { model.tempo = $0 }),
                             metronome: Binding(get: { model.metronome }, set: { model.metronome = $0 }),
                             onPlay: { model.play() }, onStop: { model.stop() })
                HStack(spacing: 12) {
                    Text("Swing").font(Theme.body(14)).foregroundStyle(Color.ink)
                    Slider(value: Binding(get: { model.grid.swing }, set: { model.grid.swing = $0 }),
                           in: DrumGridModel.swingRange)
                        .tint(Color.haze)
                        .frame(minHeight: Theme.minTarget)
                        .accessibilityLabel("Swing")
                    Text("\(Int((model.grid.swing * 100).rounded()))%")
                        .font(Theme.mono(13)).foregroundStyle(Color.mute).frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 14))
                DrumGridView(model: model.grid, playheadTick: { model.playheadTick }, isPlaying: model.isPlaying,
                             onPad: { lane, v in model.pad(lane, v) })
            }
            .padding(16)
        }
        .background(Color.night.ignoresSafeArea())
        .onChange(of: isActive) { _, active in
            if !active, model.isPlaying { model.stop() }
        }
    }
}

/// Temporary root: switch between the melody, chord and drum labs. All stay alive so edits survive switching.
struct LabRootView: View {
    private enum Lab: String, CaseIterable { case melody = "Melody", chords = "Chords", drums = "Drums" }

    let audio: any AudioPlaying
    @State private var lab = Lab.melody

    var body: some View {
        VStack(spacing: 0) {
            Picker("Lab", selection: $lab) {
                ForEach(Lab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            ZStack {
                MelodyLabView(audio: audio, isActive: lab == .melody)
                    .opacity(lab == .melody ? 1 : 0).allowsHitTesting(lab == .melody)
                    .accessibilityHidden(lab != .melody)
                ChordsLabView(audio: audio, isActive: lab == .chords)
                    .opacity(lab == .chords ? 1 : 0).allowsHitTesting(lab == .chords)
                    .accessibilityHidden(lab != .chords)
                DrumLabView(audio: audio, isActive: lab == .drums)
                    .opacity(lab == .drums ? 1 : 0).allowsHitTesting(lab == .drums)
                    .accessibilityHidden(lab != .drums)
            }
        }
        .background(Color.night.ignoresSafeArea())
    }
}
