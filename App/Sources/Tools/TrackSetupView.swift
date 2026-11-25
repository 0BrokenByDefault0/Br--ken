import SwiftUI
import MusicCore

/// Name, tempo (60–180) and key for a track. `onDone` gets the choices.
struct TrackSetupView: View {
    static let tempoRange: ClosedRange<Double> = 60...180
    static let hintText = "Trap 130–170 · Cloud 60–80 or 130–160"

    @State private var name: String
    @State private var tempo: Double
    @State private var mode: Mode
    @State private var tonic: Int
    private let confirmTitle: String
    private let onDone: (String, Double, Key) -> Void

    init(tempo: Double = AppModel.defaultTempo, key: Key = AppModel.defaultKey, name: String = "My first beat",
         confirmTitle: String = "Create track", onDone: @escaping (String, Double, Key) -> Void) {
        _name = State(initialValue: name)
        _tempo = State(initialValue: min(max(tempo, Self.tempoRange.lowerBound), Self.tempoRange.upperBound).rounded())
        _mode = State(initialValue: key.mode)
        _tonic = State(initialValue: key.tonic.rawValue)
        self.confirmTitle = confirmTitle
        self.onDone = onDone
    }

    /// Which genres the tempo suits (trap 130–170, cloud 60–80 and 130–160).
    static func genreFit(tempo: Double) -> String {
        var fits: [String] = []
        if (130...170).contains(tempo) { fits.append("trap") }
        if (60...80).contains(tempo) || (130...160).contains(tempo) { fits.append("cloud") }
        return fits.isEmpty ? "Between the usual trap and cloud tempos" : "Fits: " + fits.joined(separator: ", ")
    }

    private var key: Key { Key(tonic: PitchClass(tonic), mode: mode) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Name") {
                    TextField("Track name", text: $name)
                        .font(Theme.body(17)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: Theme.minTarget)
                        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                section("Tempo") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(tempo)) BPM").font(Theme.mono(20)).foregroundStyle(Color.ink)
                        Slider(value: $tempo, in: Self.tempoRange, step: 1).tint(Color.haze)
                            .frame(minHeight: Theme.minTarget)
                            .accessibilityLabel("Tempo")
                        Text(Self.genreFit(tempo: tempo)).font(Theme.body(14)).foregroundStyle(Color.amber)
                        Text(Self.hintText).font(Theme.body(13)).foregroundStyle(Color.mute)
                    }
                    .padding(12)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 14))
                }
                section("Key") {
                    VStack(spacing: 10) {
                        Picker("Mode", selection: $mode) {
                            Text("Major").tag(Mode.major)
                            Text("Minor").tag(Mode.minor)
                        }
                        .pickerStyle(.segmented)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(0..<12, id: \.self) { i in
                                let selected = tonic == i
                                Button { tonic = i } label: {
                                    Text(Key(tonic: PitchClass(i), mode: mode).spell(PitchClass(i)))
                                        .font(Theme.mono(16, weight: .semibold))
                                        .foregroundStyle(selected ? Color.night : Color.ink)
                                        .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                                        .background(selected ? Color.haze : Color.panel, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(PressableButtonStyle())
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        Text(key.name).font(Theme.mono(14)).foregroundStyle(Color.mute)
                    }
                }
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onDone(trimmed.isEmpty ? "My first beat" : trimmed, tempo, key)
                } label: {
                    Text(confirmTitle).font(Theme.title(17)).foregroundStyle(Color.night)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTarget + 6)
                        .background(Color.amber, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(16)
        }
        .background(Color.night.ignoresSafeArea())
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.title(15)).foregroundStyle(Color.mute)
            content()
        }
    }
}

/// A sheet that creates a track, makes it active, and closes.
struct NewTrackSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TrackSetupView { name, tempo, key in
                model.startTrack(name: name, tempo: tempo, key: key)
                dismiss()
            }
            .navigationTitle("New track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Shown on a tool screen when there is no active track.
struct NoTrackView: View {
    let tool: String
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 14) {
            Text("No track yet").font(Theme.title(22)).foregroundStyle(Color.ink)
            Text("\(tool) edits Your Track. Start one to begin.")
                .font(Theme.body(15)).foregroundStyle(Color.mute).multilineTextAlignment(.center)
            Button { showSetup = true } label: {
                Text("Start a track").font(Theme.title(17)).foregroundStyle(Color.night)
                    .padding(.horizontal, 24)
                    .frame(minHeight: Theme.minTarget + 6)
                    .background(Color.amber, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.night.ignoresSafeArea())
        .sheet(isPresented: $showSetup) { NewTrackSheet() }
    }
}

/// Play/stop for the whole active track, tempo, and metronome.
struct TrackTransport: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TransportBar(isPlaying: model.isPlaying,
                     tempo: Binding(get: { model.activeTrack?.tempo ?? AppModel.defaultTempo },
                                    set: { t in model.updateActiveTrack { $0.tempo = t } }),
                     metronome: Binding(get: { model.metronome }, set: { model.metronome = $0 }),
                     onPlay: { model.play() }, onStop: { model.stop() })
    }
}
