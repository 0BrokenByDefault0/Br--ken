import SwiftUI

/// Play/stop, tempo (60–180) and metronome (a rim click on every beat while playing).
struct TransportBar: View {
    static let tempoRange: ClosedRange<Double> = 60...180

    let isPlaying: Bool
    @Binding var tempo: Double
    @Binding var metronome: Bool
    let onPlay: () -> Void
    let onStop: () -> Void
    /// Called when a tempo drag ends.
    var onTempoCommit: (() -> Void)? = nil
    @State private var editing = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: isPlaying ? onStop : onPlay) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.night)
                    .frame(width: 52, height: Theme.minTarget + 8)
                    .background(isPlaying ? Color.amber : Color.haze, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(isPlaying ? "Stop" : "Play")

            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(tempo.rounded())) BPM")
                    .font(Theme.mono(15)).foregroundStyle(Color.ink)
                Slider(value: Binding(get: { tempo }, set: { tempo = $0; if !editing { onTempoCommit?() } }),
                       in: Self.tempoRange, step: 1,
                       onEditingChanged: { editing = $0; if !$0 { onTempoCommit?() } })
                    .tint(Color.haze)
                    .frame(minHeight: Theme.minTarget)
            }

            Button { metronome.toggle() } label: {
                Image(systemName: "metronome.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(metronome ? Color.night : Color.mute)
                    .frame(width: Theme.minTarget, height: Theme.minTarget)
                    .background(metronome ? Color.amber : Color.panel, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Metronome")
            .accessibilityValue(metronome ? "On" : "Off")
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}
