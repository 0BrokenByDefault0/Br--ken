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

    @State private var pressed: Set<Int> = []

    private static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
    private static let blackAfterWhite = [0: 1, 1: 3, 3: 6, 4: 8, 5: 10]  // white index in octave -> black semitone

    private var basePitch: Int { (octave + 1) * 12 }
    private var scaleClasses: [PitchClass] { scale.pitchClasses(tonic: key.tonic) }

    var body: some View {
        VStack(spacing: 8) {
            controls
            GeometryReader { geo in
                let whiteWidth = geo.size.width / 14
                ZStack(alignment: .topLeading) {
                    ForEach(0..<14, id: \.self) { w in
                        let pitch = basePitch + (w / 7) * 12 + Self.whiteOffsets[w % 7]
                        keyView(pitch: pitch, black: false)
                            .frame(width: whiteWidth, height: geo.size.height)
                            .offset(x: CGFloat(w) * whiteWidth)
                    }
                    ForEach(0..<14, id: \.self) { w in
                        if let semitone = Self.blackAfterWhite[w % 7] {
                            let pitch = basePitch + (w / 7) * 12 + semitone
                            keyView(pitch: pitch, black: true)
                                .frame(width: whiteWidth * 0.62, height: geo.size.height * 0.62)
                                .offset(x: CGFloat(w + 1) * whiteWidth - whiteWidth * 0.31)
                        }
                    }
                }
            }
            .frame(height: 170)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { octave = max(1, octave - 1) } label: {
                Image(systemName: "minus").frame(width: Theme.minTarget, height: Theme.minTarget)
            }
            Text("C\(octave)–C\(octave + 2)")
                .font(Theme.mono(15)).foregroundStyle(Color.ink)
            Button { octave = min(6, octave + 1) } label: {
                Image(systemName: "plus").frame(width: Theme.minTarget, height: Theme.minTarget)
            }
            Spacer()
            Toggle("Scale lock", isOn: $scaleLock)
                .toggleStyle(.switch).tint(Color.haze)
                .font(Theme.body(15)).foregroundStyle(Color.ink)
                .fixedSize()
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(Color.haze)
    }

    private func keyView(pitch: Int, black: Bool) -> some View {
        let pc = PitchClass(pitch)
        let inScale = scaleClasses.contains(pc)
        let locked = scaleLock && !inScale
        let isDown = pressed.contains(pitch)
        let fill: Color = isDown ? Color.amber
            : black ? (inScale ? Color.haze.opacity(0.55) : Color(hex: 0x2A2740))
            : (inScale ? Color.ink : Color.ink.opacity(0.35))
        return ZStack(alignment: .bottom) {
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
        .opacity(locked ? (black ? 0 : 0.18) : 1)
        .scaleEffect(isDown ? 0.97 : 1, anchor: .top)
        .contentShape(Rectangle())
        .allowsHitTesting(!locked)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed.contains(pitch) else { return }
                    pressed.insert(pitch)
                    onNote(pitch, true)  // synchronous, on touch-down
                }
                .onEnded { _ in
                    pressed.remove(pitch)
                    onNote(pitch, false)
                }
        )
        .accessibilityLabel(key.spell(midi: pitch))
    }
}
