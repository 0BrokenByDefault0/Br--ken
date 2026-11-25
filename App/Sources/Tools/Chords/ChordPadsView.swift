import SwiftUI
import MusicCore

/// Quality choices for a pad's long-press switcher.
enum PadVariant: String, CaseIterable {
    case triad = "Triad", seventh = "7", ninth = "9", sus2 = "sus2", sus4 = "sus4"
}

/// One pad: a diatonic (or borrowed) degree with its triad and seventh.
struct ChordPad: Equatable {
    let roman: String
    let triad: Chord
    let seventh: Chord
    let borrowed: Bool

    /// One pad per scale degree, then the borrowed dominant (minor keys).
    static func pads(key: Key) -> [ChordPad] {
        let triads = key.diatonicTriads()
        let sevenths = key.diatonicSevenths()
        var pads = zip(triads, sevenths).map {
            ChordPad(roman: $0.roman, triad: $0.chord, seventh: $1.chord, borrowed: false)
        }
        for b in key.borrowedChords() where !b.chord.quality.isExtended {
            pads.append(ChordPad(roman: b.roman, triad: b.chord,
                                 seventh: Chord(root: b.chord.root, quality: .dominant7), borrowed: true))
        }
        return pads
    }

    /// 7 is the degree's diatonic seventh; 9 is minor9 for minor-ish and major9 for major-ish sevenths
    /// (dominant and diminished fall back to the seventh); sus chords keep the root.
    func chord(_ variant: PadVariant) -> Chord {
        switch variant {
        case .triad: return triad
        case .seventh: return seventh
        case .ninth:
            switch seventh.quality {
            case .minor7: return Chord(root: seventh.root, quality: .minor9)
            case .major7: return Chord(root: seventh.root, quality: .major9)
            default: return seventh
            }
        case .sus2: return Chord(root: triad.root, quality: .sus2)
        case .sus4: return Chord(root: triad.root, quality: .sus4)
        }
    }
}

/// Pad press bookkeeping: every note-on gets exactly one note-off, and the voicing released is the one
/// that was pressed (even if the pad's quality changed meanwhile). A pad stays "touching" until its touch
/// ends, so repeated drag events and the events after a long-press do not re-sound it.
struct PadTouchState {
    private var touching: Set<Int> = []
    private var sounding: [Int: [Int]] = [:]
    private var long: Set<Int> = []

    func isSounding(_ pad: Int) -> Bool { sounding[pad] != nil }

    /// The pitches to note-on, or nil if this touch already pressed the pad.
    mutating func press(_ pad: Int, voicing: [Int]) -> [Int]? {
        guard touching.insert(pad).inserted else { return nil }
        long.remove(pad)
        sounding[pad] = voicing
        return voicing
    }

    /// A hold: stops the sound (the quality switcher opens) and marks the touch as not a tap.
    mutating func longPress(_ pad: Int) -> [Int] {
        long.insert(pad)
        return sounding.removeValue(forKey: pad) ?? []
    }

    /// Ends the touch. `release` are the pitches to note-off; `place` is true for a completed tap
    /// (not a hold). Safe to call twice per touch (lift and gesture reset), in either order.
    mutating func finish(_ pad: Int, completed: Bool) -> (release: [Int], place: Bool) {
        touching.remove(pad)
        return (sounding.removeValue(forKey: pad) ?? [], completed && !long.contains(pad))
    }

    mutating func releaseAll() -> [Int] {
        defer { touching.removeAll(); sounding.removeAll() }
        return sounding.values.flatMap { $0 }.sorted()
    }
}

/// Chord pads (tap to hear, hold a pad to switch its quality) and a slot strip to place chords in.
/// A pad sounds on touch-down and stops on release; notes are always released on cancel or disappear.
struct ChordPadsView: View {
    let key: Key
    @Binding var showSevenths: Bool
    let onChord: (Chord) -> Void
    @Binding var progression: ChordProgression
    let bars: Int
    /// Note-on (true) / note-off (false) for each pitch of a pressed pad.
    let onNote: (Int, Bool) -> Void

    @State private var touches = PadTouchState()
    @State private var overrides: [Int: PadVariant] = [:]
    @State private var switcherPad: Int?
    @State private var twoPerBar = false
    @State private var selectedSlot: Int?

    private var pads: [ChordPad] { ChordPad.pads(key: key) }
    private var slotLength: Int { twoPerBar ? Ticks.perBar / 2 : Ticks.perBar }
    private var slotCount: Int { bars * (twoPerBar ? 2 : 1) }

    var body: some View {
        VStack(spacing: 12) {
            slotStrip
            HStack {
                Toggle("7ths", isOn: $showSevenths)
                    .toggleStyle(.switch).tint(Color.haze)
                    .font(Theme.body(15)).foregroundStyle(Color.ink)
                    .frame(minHeight: Theme.minTarget)
                Spacer(minLength: 8)
                Text("Hold a pad for quality").font(Theme.body(11)).foregroundStyle(Color.mute)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(Array(pads.enumerated()), id: \.offset) { index, pad in padView(index, pad) }
            }
        }
        .onChange(of: showSevenths) { _, _ in releaseAll() }
        .onChange(of: key) { _, _ in releaseAll(); overrides = [:] }
        .onDisappear { releaseAll() }
        .confirmationDialog("Quality", isPresented: Binding(get: { switcherPad != nil },
                                                           set: { if !$0 { switcherPad = nil } }),
                            titleVisibility: .visible) {
            ForEach(PadVariant.allCases, id: \.self) { variant in
                Button(variant.rawValue) { if let p = switcherPad { overrides[p] = variant } }
            }
        }
    }

    private func current(_ index: Int, _ pad: ChordPad) -> Chord {
        pad.chord(overrides[index] ?? (showSevenths ? PadVariant.seventh : PadVariant.triad))
    }

    private func padView(_ index: Int, _ pad: ChordPad) -> some View {
        let chord = current(index, pad)
        let down = touches.isSounding(index)
        return PadCell(onPress: { press(index, chord) },
                       onFinish: { completed in finish(index, chord, completed: completed) },
                       onLongPress: { longPress(index) }) {
            VStack(spacing: 2) {
                Text(chord.symbol(in: key)).font(Theme.mono(17, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(pad.borrowed ? "\(pad.roman) ·borrowed" : pad.roman).font(Theme.mono(11))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(down ? Color.night : Color.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(down ? Color.amber : Color.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(overrides[index] != nil ? Color.haze : Color.clear, lineWidth: 1.5))
            .scaleEffect(down ? 0.96 : 1)
        }
        .accessibilityLabel("\(chord.symbol(in: key)), \(pad.roman)")
    }

    private func press(_ index: Int, _ chord: Chord) {
        guard let pitches = touches.press(index, voicing: Voicer.closeVoicing(chord)) else { return }
        for pitch in pitches { onNote(pitch, true) }  // synchronous, on touch-down
        onChord(chord)
    }

    /// Releases the pad's notes. A completed tap (not a hold, not a cancel) also fills the selected slot.
    private func finish(_ index: Int, _ chord: Chord, completed: Bool) {
        let result = touches.finish(index, completed: completed)
        for pitch in result.release { onNote(pitch, false) }
        if result.place, let slot = selectedSlot {
            progression = progression.placing(chord, start: slot * slotLength, length: slotLength)
            selectedSlot = slot + 1 < slotCount ? slot + 1 : nil
        }
    }

    private func longPress(_ index: Int) {
        for pitch in touches.longPress(index) { onNote(pitch, false) }
        switcherPad = index
    }

    private func releaseAll() {
        for pitch in touches.releaseAll() { onNote(pitch, false) }
    }

    private var slotStrip: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Slots").font(Theme.title(15)).foregroundStyle(Color.ink)
                Text("tap a slot, then a pad").font(Theme.body(11)).foregroundStyle(Color.mute)
                Spacer()
                Picker("Chords per bar", selection: $twoPerBar) {
                    Text("1 / bar").tag(false)
                    Text("2 / bar").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 130, height: Theme.minTarget)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<slotCount, id: \.self) { i in slotCell(i) }
                }
            }
        }
        .onChange(of: twoPerBar) { _, _ in selectedSlot = nil }
        .onChange(of: bars) { _, _ in
            if let s = selectedSlot, s >= slotCount { selectedSlot = nil }
        }
    }

    private func slotCell(_ i: Int) -> some View {
        // At 1 per bar a bar may hold two chords (placed at 2 per bar): show both.
        let chords = twoPerBar ? (progression.chord(at: i * slotLength).map { [$0] } ?? [])
                               : progression.chords(inBar: i)
        let selected = selectedSlot == i
        let label = twoPerBar ? "\(i / 2 + 1)\(i % 2 == 0 ? "a" : "b")" : "\(i + 1)"
        return Button { selectedSlot = selected ? nil : i } label: {
            VStack(spacing: 2) {
                Text("Bar \(label)").font(Theme.mono(10)).foregroundStyle(Color.mute)
                Text(chords.isEmpty ? "–" : chords.map { $0.symbol(in: key) }.joined(separator: " | "))
                    .font(Theme.mono(15, weight: .bold)).foregroundStyle(Color.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(chords.isEmpty ? " " : chords.map { key.roman(of: $0) ?? "?" }.joined(separator: " | "))
                    .font(Theme.mono(10)).foregroundStyle(Color.haze)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: twoPerBar ? 70 : 110, height: 64)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.amber : Color.clear, lineWidth: 2))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Slot \(label)")
    }
}

/// One pad's touch handling: reports touch-down (`onPress` on every drag event; `PadTouchState` makes repeats harmless), a hold after 0.5 s, and the finish
/// (`completed` is true for a normal lift, false when the system cancelled the touch; both can arrive, in either order).
private struct PadCell<Content: View>: View {
    let onPress: () -> Void
    let onFinish: (_ completed: Bool) -> Void
    let onLongPress: () -> Void
    @ViewBuilder let content: () -> Content
    @GestureState private var touching = false

    var body: some View {
        content()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onFinish(true) }
            )
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() })
            .onChange(of: touching) { _, isTouching in
                if !isTouching { onFinish(false) }
            }
    }
}
