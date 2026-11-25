import SwiftUI
import MusicCore

/// Two playable octaves from C of `octave` (C4 = MIDI 60). Each key reacts on touch-down; fingers are
/// independent, so chords and fast runs work.
struct KeyboardView: View {
    let key: Key
    let scale: ScaleType
    @Binding var scaleLock: Bool
    @Binding var octave: Int
    let instrument: InstrumentID
    let onNote: (Int, Bool) -> Void

    @State private var tracker = KeyPressTracker()
    @State private var twoOctaves = true

    private static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
    private static let blackAfterWhite = [0: 1, 1: 3, 3: 6, 4: 8, 5: 10]  // white index in octave -> black semitone

    private var basePitch: Int { (octave + 1) * 12 }
    private var scaleClasses: [PitchClass] { scale.pitchClasses(tonic: key.tonic) }

    var body: some View {
        VStack(spacing: 8) {
            controls
            GeometryReader { geo in
                let whiteCount = twoOctaves ? 14 : 7
                let whiteWidth = geo.size.width / CGFloat(whiteCount)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<whiteCount, id: \.self) { w in
                        let pitch = basePitch + (w / 7) * 12 + Self.whiteOffsets[w % 7]
                        keyView(pitch: pitch, black: false, inset: 0)
                            .frame(width: whiteWidth, height: geo.size.height)
                            .offset(x: CGFloat(w) * whiteWidth)
                    }
                    ForEach(0..<whiteCount, id: \.self) { w in
                        if let semitone = Self.blackAfterWhite[w % 7], w + 1 < whiteCount {
                            let pitch = basePitch + (w / 7) * 12 + semitone
                            // The hit area is wider than the drawn key (see `keyView`).
                            keyView(pitch: pitch, black: true, inset: whiteWidth * 0.09)
                                .frame(width: whiteWidth * 0.8, height: geo.size.height * 0.64)
                                .offset(x: CGFloat(w + 1) * whiteWidth - whiteWidth * 0.4)
                        }
                    }
                }
            }
            .frame(height: 170)
        }
        .onChange(of: octave) { _, _ in releaseAll() }
        .onChange(of: scaleLock) { _, _ in releaseAll() }
        .onChange(of: twoOctaves) { _, _ in releaseAll() }
        .onDisappear { releaseAll() }
    }

    private func press(_ pitch: Int) {
        if tracker.press(pitch) { onNote(pitch, true) }  // synchronous, on touch-down
    }

    private func release(_ pitch: Int) {
        if tracker.release(pitch) { onNote(pitch, false) }
    }

    private func releaseAll() {
        for pitch in tracker.releaseAll() { onNote(pitch, false) }
    }

    /// Two rows so nothing clips at 320 pt: octave and range on top, scale lock below.
    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { octave = max(1, octave - 1) } label: {
                    Image(systemName: "minus").frame(width: Theme.minTarget, height: Theme.minTarget)
                }
                Text("C\(octave)–C\(octave + (twoOctaves ? 2 : 1))")
                    .font(Theme.mono(15)).foregroundStyle(Color.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Button { octave = min(6, octave + 1) } label: {
                    Image(systemName: "plus").frame(width: Theme.minTarget, height: Theme.minTarget)
                }
                Spacer(minLength: 8)
                Picker("Range", selection: $twoOctaves) {
                    Text("1 oct").tag(false)
                    Text("2 oct").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 110, height: Theme.minTarget)
            }
            Toggle("Scale lock", isOn: $scaleLock)
                .toggleStyle(.switch).tint(Color.haze)
                .font(Theme.body(15)).foregroundStyle(Color.ink)
                .frame(minHeight: Theme.minTarget)
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(Color.haze)
    }

    private func keyView(pitch: Int, black: Bool, inset: CGFloat) -> some View {
        let pc = PitchClass(pitch)
        let inScale = scaleClasses.contains(pc)
        let locked = scaleLock && !inScale
        let isDown = tracker.isHeld(pitch)
        let fill: Color = isDown ? Color.amber
            : black ? (inScale ? Color.haze.opacity(0.55) : Color(hex: 0x2A2740))
            : (inScale ? Color.ink : Color.ink.opacity(0.35))
        // Black keys are drawn narrower than their touch area (`inset` per side).
        return KeyCell(pitch: pitch, onPress: press, onRelease: release) {
          ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.night, lineWidth: 1))
            VStack(spacing: 1) {
                if inScale, let degree = key.degree(of: pc) {
                    Text("\(degree)").font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(black ? Color.ink : Color.night.opacity(0.7))
                }
                Text(key.spell(pc))
                    .font(Theme.mono(black ? 9 : 10))
                    .foregroundStyle(black ? Color.ink : Color.night)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.bottom, 6)
        }
          .padding(.horizontal, inset)
          .opacity(locked ? (black ? 0 : 0.18) : 1)
          .scaleEffect(isDown ? 0.97 : 1, anchor: .top)
        }
        .allowsHitTesting(!locked)
        .accessibilityLabel(key.spell(midi: pitch))
    }
}

/// One key's touch handling. A cancelled gesture (system takes the touch) resets `@GestureState`, which
/// releases the key just like a normal lift.
private struct KeyCell<Content: View>: View {
    let pitch: Int
    let onPress: (Int) -> Void
    let onRelease: (Int) -> Void
    @ViewBuilder let content: () -> Content
    @GestureState private var touching = false

    var body: some View {
        content()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { _ in onPress(pitch) }
                    .onEnded { _ in onRelease(pitch) }
            )
            .onChange(of: touching) { _, isTouching in
                if !isTouching { onRelease(pitch) }
            }
    }
}
