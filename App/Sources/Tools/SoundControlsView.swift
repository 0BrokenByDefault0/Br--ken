import SwiftUI
import MusicCore

/// Sliders for a part's `SoundSettings`.
struct SoundControlsView: View {
    @Binding var settings: SoundSettings
    /// Called when a slider drag ends.
    var onCommit: (() -> Void)? = nil
    @State private var editing = false

    var body: some View {
        VStack(spacing: 2) {
            slider("Volume", $settings.volume)
            slider("Drive", $settings.drive)
            slider("Tone", $settings.cutoff)
            slider("Reverb", $settings.reverb)
            slider("Delay", $settings.delay)
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func slider(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label).font(Theme.body(15)).foregroundStyle(Color.ink)
                .frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; if !editing { onCommit?() } }),
                   in: 0...1, onEditingChanged: { editing = $0; if !$0 { onCommit?() } }).tint(Color.haze)
            Text("\(Int((value.wrappedValue * 100).rounded()))")
                .font(Theme.mono(13)).foregroundStyle(Color.mute)
                .frame(width: 30, alignment: .trailing)
        }
        .frame(minHeight: Theme.minTarget)
    }
}
