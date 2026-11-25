import SwiftUI
import MusicCore

/// The card at the top of the Journey: play/stop of the whole active-track loop, a 3-row mini timeline
/// with a playhead, part chips that mute on tap, and the key · BPM · bars line.
struct YourTrackBar: View {
    @Environment(AppModel.self) private var model
    @State private var showSetup = false
    @State private var showExport = false

    private static let roles: [PartRole] = [.melody, .chords, .drums]

    var body: some View {
        Group {
            if let track = model.activeTrack {
                trackCard(track)
            } else {
                emptyCard
            }
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showSetup) { NewTrackSheet() }
        .sheet(isPresented: $showExport) { if let track = model.activeTrack { ExportSheet(track: track) } }
    }

    private var emptyCard: some View {
        HStack {
            Text("No track yet —").font(Theme.body(16)).foregroundStyle(Color.mute)
            Button { showSetup = true } label: {
                Text("Start a track").font(Theme.title(16)).foregroundStyle(Color.amber)
                    .frame(minHeight: Theme.minTarget)
            }
            .buttonStyle(PressableButtonStyle())
            Spacer()
        }
    }

    private func trackCard(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: model.isPlaying ? model.stop : model.play) {
                    Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.night)
                        .frame(width: 52, height: Theme.minTarget + 8)
                        .background(model.isPlaying ? Color.amber : Color.haze, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(model.isPlaying ? "Stop Your Track" : "Play Your Track")

                NavigationLink {
                    TrackListView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(track.name).font(Theme.title(18)).foregroundStyle(Color.ink).lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.mute)
                        }
                        Text("\(track.key.name) · \(Int(track.tempo.rounded())) BPM · \(track.bars) bars")
                            .font(Theme.mono(12)).foregroundStyle(Color.mute)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Opens your tracks")

                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 20))
                        .foregroundStyle(Color.haze)
                        .frame(width: Theme.minTarget, height: Theme.minTarget)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Export Your Track")
            }
            MiniTimeline(track: track, isPlaying: model.isPlaying, playheadTick: { model.audio.playheadTick })
                .frame(height: 54)
            HStack(spacing: 8) {
                ForEach(Self.roles, id: \.self) { role in chip(role, track: track) }
            }
        }
    }

    @ViewBuilder
    private func chip(_ role: PartRole, track: Track) -> some View {
        let part = track.part(role)
        let name = Self.name(role)
        if let part {
            Button { model.setMuted(role: role, !part.muted) } label: {
                Text(name).font(Theme.body(14).weight(.medium))
                    .foregroundStyle(part.muted ? Color.mute : Color.night)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTarget)
                    .background(part.muted ? Color.night : Self.color(role), in: Capsule())
                    .overlay(Capsule().stroke(part.muted ? Color.mute.opacity(0.5) : .clear, lineWidth: 1))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("\(name) part")
            .accessibilityValue(part.muted ? "Muted" : "On")
            .accessibilityHint("Tap to \(part.muted ? "unmute" : "mute")")
        } else {
            Text(name).font(Theme.body(14)).foregroundStyle(Color.mute)
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTarget)
                .overlay(Capsule().strokeBorder(Color.mute.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .accessibilityLabel("\(name) part, not built yet")
        }
    }

    static func name(_ role: PartRole) -> String {
        switch role {
        case .melody: "Melody"
        case .chords: "Chords"
        case .drums: "Drums"
        default: role.rawValue.capitalized
        }
    }

    static func color(_ role: PartRole) -> Color {
        switch role {
        case .melody: Color.haze
        case .chords: Color.color
        default: Color.tone
        }
    }
}

/// Melody notes, chord blocks and drum hits over the loop, with an amber playhead.
private struct MiniTimeline: View {
    let track: Track
    let isPlaying: Bool
    let playheadTick: () -> Int

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { _ in
            Canvas { context, size in
                let loop = Double(max(1, track.bars) * Ticks.perBar)
                let rowH = size.height / 3
                func x(_ tick: Int) -> CGFloat { CGFloat(Double(tick) / loop) * size.width }
                for row in 0..<3 {
                    let rect = CGRect(x: 0, y: CGFloat(row) * rowH + 1, width: size.width, height: rowH - 2)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.night))
                }
                if let part = track.part(.melody), case .notes(let seq) = part.content, !seq.notes.isEmpty {
                    let lo = seq.notes.map(\.pitch).min() ?? 60, hi = seq.notes.map(\.pitch).max() ?? 60
                    for n in seq.notes {
                        let frac = hi == lo ? 0.5 : Double(n.pitch - lo) / Double(hi - lo)
                        let y = rowH - 4 - CGFloat(frac) * (rowH - 7)
                        let r = CGRect(x: x(n.start), y: y, width: max(2, x(n.length)), height: 3)
                        context.fill(Path(r), with: .color(Color.haze.opacity(part.muted ? 0.25 : 1)))
                    }
                }
                if let part = track.part(.chords), case .chords(let prog) = part.content {
                    for slot in prog.slots {
                        let r = CGRect(x: x(slot.start) + 1, y: rowH + 4, width: max(2, x(slot.length) - 2), height: rowH - 8)
                        context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(Color.color.opacity(part.muted ? 0.2 : 0.8)))
                    }
                }
                if let part = track.part(.drums), case .drums(let pattern) = part.content {
                    for hits in pattern.lanes.values {
                        for h in hits {
                            let r = CGRect(x: x(h.tick), y: 2 * rowH + 4, width: 2, height: rowH - 8)
                            let a = (0.35 + 0.65 * Double(h.velocity)) * (part.muted ? 0.25 : 1)
                            context.fill(Path(r), with: .color(Color.tone.opacity(a)))
                        }
                    }
                }
                if isPlaying {
                    let px = x(playheadTick() % Int(loop))
                    context.fill(Path(CGRect(x: px, y: 0, width: 2, height: size.height)), with: .color(Color.amber))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
