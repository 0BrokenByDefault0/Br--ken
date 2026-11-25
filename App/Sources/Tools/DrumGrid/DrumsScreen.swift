import SwiftUI
import MusicCore

/// Drums tab: the drum grid on the active track's drums part (created empty on the first edit).
struct DrumsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let track = model.activeTrack {
            DrumsBody(app: model, track: track).id(track.id)
        } else {
            NoTrackView(tool: "The drum grid")
        }
    }
}

private struct DrumsBody: View {
    let app: AppModel
    @State private var grid: DrumGridModel
    @State private var drag: SwingDrag
    private let key: Key

    init(app: AppModel, track: Track) {
        self.app = app
        key = track.key
        var pattern = DrumPattern(lanes: [:])
        if case .drums(let p)? = track.part(.drums)?.content { pattern = p }
        let grid = DrumGridModel(pattern: pattern, bars: track.bars)
        let drag = SwingDrag()
        _drag = State(initialValue: drag)
        grid.onChange = { [weak app, drag] pattern in
            // Pad edits always save; only a swing slider change (flagged for the duration of that call) previews.
            app?.editActivePart(.drums, instrument: .trapKit, empty: .drums(DrumPattern(lanes: [:])), persist: !drag.swinging) {
                $0.content = .drums(pattern)
            }
        }
        _grid = State(initialValue: grid)
    }

    private var drumsContent: PartContent? { app.activeTrack?.part(.drums)?.content }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Drums").font(Theme.title(24)).foregroundStyle(Color.ink)
                    Spacer()
                    Text("trap kit · \(grid.bars) bars").font(Theme.mono(12)).foregroundStyle(Color.mute)
                }
                TrackTransport()
                HStack(spacing: 12) {
                    Text("Swing").font(Theme.body(14)).foregroundStyle(Color.ink)
                    Slider(value: Binding(get: { grid.swing }, set: { value in
                               drag.swinging = true
                               grid.swing = value
                               drag.swinging = false
                               if !drag.editing { app.commitActiveTrack() }  // VoiceOver / keyboard adjustments
                           }), in: DrumGridModel.swingRange,
                           onEditingChanged: { editing in
                               drag.editing = editing
                               if !editing { app.commitActiveTrack() }
                           })
                        .tint(Color.haze)
                        .frame(minHeight: Theme.minTarget)
                        .accessibilityLabel("Swing")
                    Text("\(Int((grid.swing * 100).rounded()))%")
                        .font(Theme.mono(13)).foregroundStyle(Color.mute).frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 14))
                DrumGridView(model: grid, playheadTick: { app.audio.playheadTick }, isPlaying: app.isPlaying,
                             onPad: { lane, v in app.audio.noteOn(.trapKit, lane.midiNote, v) })  // drum voices ignore note-off
            }
            .padding(16)
        }
        .background(Color.night.ignoresSafeArea())
        .onDisappear {
            drag.editing = false
            app.flushPendingPreview()
        }
        .onChange(of: drumsContent) { _, content in
            if case .drums(let p)? = content, p != grid.pattern { grid.pattern = p }
        }
    }
}

/// Swing slider state. `swinging` is true only while a slider value is being applied to the grid (so the
/// grid's change callback previews instead of saving); `editing` is whether a drag is in progress.
private final class SwingDrag {
    var swinging = false
    var editing = false
}
