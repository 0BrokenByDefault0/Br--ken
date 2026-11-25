import SwiftUI
import MusicCore

/// Piano roll: tap a cell to add or remove a note; touch-and-hold a note, then drag sideways to resize it.
/// Glide mode turns taps into glide toggles. Rows run high pitch at the top.
struct PianoRollView: View {
    let model: PianoRollModel
    let playheadTick: Int
    /// Called with the pitch when a note is added, so the caller can let the owner hear it.
    var onAudition: ((Int) -> Void)?

    @State private var glideMode = false

    private let cellWidth: CGFloat = 36
    private let rowHeight: CGFloat = 30
    private let gutter: CGFloat = 40

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Tap does", selection: $glideMode) {
                    Text("Notes").tag(false)
                    Text("Glide").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                Spacer()
                Text("Tap: add / remove · Hold + drag: length")
                    .font(Theme.body(11)).foregroundStyle(Color.mute)
            }
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    pitchGutter
                    ScrollView(.horizontal, showsIndicators: false) {
                        grid
                    }
                }
            }
            .frame(height: 260)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var gridSize: CGSize {
        CGSize(width: cellWidth * CGFloat(model.steps), height: rowHeight * CGFloat(PianoRollModel.pitchCount))
    }

    private func row(of pitch: Int) -> Int { model.highestPitch - pitch }

    private var pitchGutter: some View {
        VStack(spacing: 0) {
            ForEach((model.lowestPitch...model.highestPitch).reversed(), id: \.self) { pitch in
                let pc = PitchClass(pitch)
                Text(model.key.spell(pc))
                    .font(Theme.mono(10))
                    .foregroundStyle(model.key.contains(pc) ? Color.ink : Color.mute.opacity(0.5))
                    .frame(width: gutter, height: rowHeight)
            }
        }
    }

    private var grid: some View {
        Canvas { context, size in
            for pitch in model.lowestPitch...model.highestPitch {
                let pc = PitchClass(pitch)
                let y = CGFloat(row(of: pitch)) * rowHeight
                let rect = CGRect(x: 0, y: y, width: size.width, height: rowHeight)
                let tint: Color = pc == model.key.tonic ? Color.haze.opacity(0.16)
                    : model.key.contains(pc) ? Color.haze.opacity(0.06) : Color.clear
                context.fill(Path(rect), with: .color(tint))
                context.fill(Path(CGRect(x: 0, y: y + rowHeight - 0.5, width: size.width, height: 0.5)),
                             with: .color(Color.mute.opacity(0.15)))
            }
            for step in 0...model.steps {
                let x = CGFloat(step) * cellWidth
                let strong = step % 16 == 0 ? 1.5 : (step % 4 == 0 ? 1.0 : 0.5)
                context.fill(Path(CGRect(x: x, y: 0, width: strong, height: size.height)),
                             with: .color(Color.mute.opacity(step % 4 == 0 ? 0.35 : 0.15)))
            }
            for note in model.sequence.notes where note.pitch >= model.lowestPitch && note.pitch <= model.highestPitch {
                let x = CGFloat(note.start) / CGFloat(Ticks.perSixteenth) * cellWidth
                let w = CGFloat(note.length) / CGFloat(Ticks.perSixteenth) * cellWidth
                let rect = CGRect(x: x + 1, y: CGFloat(row(of: note.pitch)) * rowHeight + 2,
                                  width: max(4, w - 2), height: rowHeight - 4)
                context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color.haze))
                if note.glide {
                    var slide = Path()
                    slide.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 4))
                    slide.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 4))
                    context.stroke(slide, with: .color(Color.night), lineWidth: 2)
                }
            }
            if playheadTick >= 0 {
                let x = CGFloat(playheadTick % max(1, model.loopTicks)) / CGFloat(Ticks.perSixteenth) * cellWidth
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(Color.amber))
            }
        }
        .frame(width: gridSize.width, height: gridSize.height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { tap in handleTap(at: tap.location) }
        )
        .gesture(
            LongPressGesture(minimumDuration: 0.25)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { value in
                    if case .second(true, let drag?) = value { handleResize(drag) }
                }
        )
    }

    private func cell(at point: CGPoint) -> (step: Int, pitch: Int)? {
        let step = Int(point.x / cellWidth)
        let rowIndex = Int(point.y / rowHeight)
        guard point.x >= 0, point.y >= 0, step < model.steps, rowIndex < PianoRollModel.pitchCount else { return nil }
        return (step, model.highestPitch - rowIndex)
    }

    private func handleTap(at point: CGPoint) {
        guard let (step, pitch) = cell(at: point) else { return }
        Theme.lightHaptic()
        if glideMode {
            model.toggleGlide(step: step, pitch: pitch)
        } else {
            let existed = model.noteIndex(step: step, pitch: pitch) != nil
            model.toggle(step: step, pitch: pitch)
            if !existed { onAudition?(pitch) }
        }
    }

    private func handleResize(_ drag: DragGesture.Value) {
        guard let (startStep, pitch) = cell(at: drag.startLocation), let end = cell(at: drag.location) ?? clampedEnd(drag.location),
              let index = model.noteIndex(step: startStep, pitch: pitch) else { return }
        let noteStep = model.sequence.notes[index].start / Ticks.perSixteenth
        model.resize(noteAt: startStep, pitch: pitch, toSteps: end.step - noteStep + 1)
        Theme.lightHaptic()
    }

    /// Dragging past the right edge or off the grid vertically still resizes along the row.
    private func clampedEnd(_ point: CGPoint) -> (step: Int, pitch: Int)? {
        let step = min(model.steps - 1, max(0, Int(point.x / cellWidth)))
        return (step, 0)
    }
}
