import SwiftUI
import MusicCore

/// Chord Finder: the melody bar by bar as chips (colored by role under the tapped or used chord), and the
/// ranked fits for the selected bar. Tap a fit to hear it under the melody; "Use" writes it into the bar.
struct ChordFinderView: View {
    let model: ChordFinderModel
    let isPlaying: Bool
    /// Plays a track from the start (an audition, or the whole progression).
    let onPlay: (Track) -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            slotStrip
            Picker("Bar", selection: Binding(get: { model.focusedBar }, set: { model.focusedBar = $0 })) {
                ForEach(0..<model.bars, id: \.self) { Text("Bar \($0 + 1)").tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: Theme.minTarget)
            ForEach(0..<model.bars, id: \.self) { bar in melodyBar(bar) }
            legend
            if model.fitsPerBar.indices.contains(model.focusedBar) {
                VStack(spacing: 8) {
                    ForEach(model.fitsPerBar[model.focusedBar], id: \.chord) { fit in
                        fitRow(fit, best: model.fitsPerBar[model.focusedBar].first?.score ?? 0)
                    }
                }
            }
        }
    }

    // MARK: Slot strip

    private var slotStrip: some View {
        HStack(spacing: 6) {
            Button { isPlaying ? onStop() : onPlay(model.fullTrack()) } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.night)
                    .frame(width: Theme.minTarget, height: 56)
                    .background(Color.amber, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(isPlaying ? "Stop" : "Play all")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<model.bars, id: \.self) { bar in
                        let chords = model.progression.chords(inBar: bar)
                        Button { model.focusedBar = bar } label: {
                            VStack(spacing: 1) {
                                Text("Bar \(bar + 1)").font(Theme.mono(10)).foregroundStyle(Color.mute)
                                Text(chords.isEmpty ? "–" : chords.map { $0.symbol(in: model.key) }.joined(separator: " | "))
                                    .font(Theme.mono(15, weight: .bold)).foregroundStyle(Color.ink)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                Text(chords.isEmpty ? " " : chords.map { model.key.roman(of: $0) ?? "?" }.joined(separator: " | "))
                                    .font(Theme.mono(10)).foregroundStyle(Color.haze)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .frame(width: 96, height: 56)
                            .background(Color.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(model.focusedBar == bar ? Color.haze : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Melody

    private func color(_ role: ChordFinderRules.ChipRole) -> Color {
        switch role {
        case .chordTone: Color.tone
        case .colorTone: Color.color
        case .clash: Color.clash
        }
    }

    private func melodyBar(_ bar: Int) -> some View {
        let notes = model.notes(inBar: bar)
        let chord = model.chord(forBar: bar)
        let lo = notes.map(\.pitch).min() ?? 60
        let hi = notes.map(\.pitch).max() ?? 60
        return VStack(alignment: .leading, spacing: 4) {
            Text("Bar \(bar + 1) melody" + (chord.map { " · under \($0.symbol(in: model.key))" } ?? ""))
                .font(Theme.mono(11)).foregroundStyle(model.focusedBar == bar ? Color.haze : Color.mute)
            GeometryReader { geo in
                let step = geo.size.width / 16
                ZStack(alignment: .topLeading) {
                    ForEach(0..<4, id: \.self) { beat in
                        Rectangle().fill(Color.mute.opacity(0.25)).frame(width: 1)
                            .offset(x: CGFloat(beat * 4) * step)
                    }
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        let start = max(note.start - bar * Ticks.perBar, 0)
                        let lane = hi == lo ? 1 : Int((Double(hi - note.pitch) / Double(hi - lo) * 2).rounded())
                        let role = chord.map { ChordFinderRules.chipRole(pitch: note.pitch, chord: $0) }
                        chip(note: note, chord: chord, role: role, width: max(CGFloat(note.length) / 24 * step - 2, 24))
                            .offset(x: CGFloat(start) / 24 * step, y: CGFloat(lane) * 30 + 2)
                    }
                }
            }
            .frame(height: 92)
            .padding(.horizontal, 2)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func chip(note: NoteEvent, chord: Chord?, role: ChordFinderRules.ChipRole?, width: CGFloat) -> some View {
        let label = chord.map { ChordFinderRules.intervalLabel(pitch: note.pitch, chord: $0) }
            ?? model.key.spell(PitchClass(note.pitch))
        return Text(label)
            .font(Theme.mono(12, weight: .bold))
            .foregroundStyle(role == nil ? Color.ink : Color.night)
            .frame(width: width, height: 26)
            .background(role.map(color) ?? Color.mute.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("\(model.key.spell(midi: note.pitch))\(role.map { ", \($0)" } ?? "")")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach([("chord tone", Color.tone), ("color tone", Color.color), ("clash", Color.clash)], id: \.0) { item in
                HStack(spacing: 5) {
                    Circle().fill(item.1).frame(width: 10, height: 10)
                    Text(item.0).font(Theme.body(12)).foregroundStyle(Color.mute)
                }
            }
        }
    }

    // MARK: Fits

    private func bandColor(_ band: ChordFinderRules.ScoreBand) -> Color {
        switch band {
        case .tone: Color.tone
        case .color: Color.color
        case .clash: Color.clash
        }
    }

    private func fitRow(_ fit: ChordFit, best: Double) -> some View {
        let bar = model.focusedBar
        let relative = ChordFinderRules.relativeScore(fit.score, best: best)
        let tint = bandColor(ChordFinderRules.band(forRelative: relative))
        let selected = model.selection[bar]?.chord == fit.chord
        let used = model.progression.chord(at: bar * Ticks.perBar) == fit.chord
        let tones = Voicer.closeVoicing(fit.chord).map { model.key.spell(PitchClass($0)) }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    model.select(bar: bar, fit: fit)
                    onPlay(model.audition(bar: bar, fit: fit))
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(fit.chord.symbol(in: model.key)).font(Theme.mono(17, weight: .bold))
                                .foregroundStyle(Color.ink)
                            Text(fit.roman).font(Theme.mono(12)).foregroundStyle(Color.haze)
                        }
                        Text(tones).font(Theme.mono(11)).foregroundStyle(Color.mute)
                        HStack(spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.night)
                                    Capsule().fill(tint).frame(width: geo.size.width * CGFloat(relative) / 100)
                                }
                            }
                            .frame(height: 8)
                            Text("\(relative)").font(Theme.mono(12)).foregroundStyle(tint)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(fit.chord.symbol(in: model.key)), score \(relative) of 100. Tap to hear.")
                Button { model.choose(bar: bar, fit: fit) } label: {
                    Text(used ? "Used" : "Use").font(Theme.title(14))
                        .foregroundStyle(used ? Color.haze : Color.night)
                        .frame(width: 60, height: Theme.minTarget)
                        .background(used ? Color.night : Color.haze, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PressableButtonStyle())
            }
            if selected {
                Text(ChordFinderRules.reason(for: fit, key: model.key))
                    .font(Theme.body(13)).foregroundStyle(Color.ink)
            }
        }
        .padding(10)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.haze : Color.clear, lineWidth: 1.5))
    }
}
