import SwiftUI
import MusicCore

/// Velocity ramp of a roll: first hit to last hit.
enum RollRamp: String, CaseIterable, Identifiable {
    case up = "Up", flat = "Flat", down = "Down"
    var id: String { rawValue }
    /// Always an ordered range; `descending` runs it from the top.
    var velocities: ClosedRange<Float> {
        switch self {
        case .up, .down: 0.35...1.0
        case .flat: 0.75...0.75
        }
    }
    var descending: Bool { self == .down }
}

extension RollRate {
    /// The four rolls offered in the grid.
    static let offered: [RollRate] = [.thirtySecond, .sixteenthTriplet, .thirtySecondTriplet, .sixtyFourth]
    var label: String {
        switch self {
        case .thirtySecond: "1/32"
        case .sixteenthTriplet: "1/16T"
        case .thirtySecondTriplet: "1/32T"
        case .sixtyFourth: "1/64"
        }
    }
}

/// One bar of 16 steps across the lanes. Draw mode: tap toggles, hold a hit for its velocity.
/// Roll mode: drag along a lane to roll over those steps; tap a roll to clear it. Pads sit underneath.
struct DrumGridView: View {
    let model: DrumGridModel
    /// Loop position in ticks, read ~30 times a second by a small overlay while `isPlaying`.
    let playheadTick: () -> Int
    var isPlaying = false
    /// Pad touch-down (fires synchronously) and a new hit added in the grid, so the caller can play it.
    var onPad: ((DrumLane, Float) -> Void)?

    private enum Mode: String, CaseIterable { case draw = "Draw", roll = "Roll" }
    private struct Target: Equatable { var lane: DrumLane; var step: Int }

    @State private var mode = Mode.draw
    @State private var rate = RollRate.thirtySecond
    @State private var ramp = RollRamp.up
    @State private var velocityTarget: Target?
    @State private var halfBar = 0
    @State private var availableWidth: CGFloat = 390

    static let lanes = DrumLane.allCases
    static let padLanes: [DrumLane] = [.kick, .snare, .clap, .closedHat, .openHat, .perc]
    private let gutter: CGFloat = 44
    private let rowHeight: CGFloat = 38
    private let minCell: CGFloat = 21

    /// Which steps are on screen and how wide they are. When 16 steps would be narrower than `minCell`,
    /// Draw mode scrolls sideways and Roll mode pages by half bars (so drags never fight scrolling).
    private struct Layout { var cell: CGFloat; var first: Int; var count: Int; var scrolls: Bool }
    private var needsScroll: Bool { (availableWidth - gutter) / 16 < minCell }
    private var paged: Bool { mode == .roll && needsScroll }
    private var layout: Layout {
        let room = availableWidth - gutter
        if paged { return Layout(cell: room / 8, first: halfBar * 8, count: 8, scrolls: false) }
        return Layout(cell: max(minCell, room / 16), first: 0, count: 16, scrolls: needsScroll)
    }
    var body: some View {
        VStack(spacing: 10) {
            barSelector
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if mode == .roll { rollOptions }
            if paged {
                Picker("Steps", selection: $halfBar) {
                    Text("Steps 1–8").tag(0)
                    Text("Steps 9–16").tag(1)
                }
                .pickerStyle(.segmented)
            }
            if mode == .draw {
                Text("Tap: add / remove · Hold a hit: velocity · Long-press a roll to clear it")
                    .font(Theme.body(11)).foregroundStyle(Color.mute)
            }
            gridArea
            if let target = velocityTarget { velocityBar(target) }
            pads
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    // MARK: Controls

    private var barSelector: some View {
        HStack(spacing: 8) {
            Picker("Bar", selection: Binding(get: { model.selectedBar }, set: { model.selectedBar = $0; velocityTarget = nil })) {
                ForEach(0..<model.bars, id: \.self) { Text("Bar \($0 + 1)").tag($0) }
            }
            .pickerStyle(.segmented)
            if model.bars > 1 {
                Button {
                    model.copyBar(model.selectedBar, to: (model.selectedBar + 1) % model.bars)
                } label: {
                    Label("Copy to next", systemImage: "doc.on.doc")
                        .font(Theme.body(13)).foregroundStyle(Color.haze)
                        .frame(minHeight: Theme.minTarget).padding(.horizontal, 8)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var rollOptions: some View {
        VStack(spacing: 8) {
            Picker("Rate", selection: $rate) {
                ForEach(RollRate.offered, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Ramp", selection: $ramp) {
                ForEach(RollRamp.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Drag along a lane to roll. Tap a roll to clear it.")
                .font(Theme.body(11)).foregroundStyle(Color.mute)
        }
    }

    private func velocityBar(_ target: Target) -> some View {
        let hit = model.hits(lane: target.lane, step: target.step).first
        return HStack(spacing: 12) {
            Text("\(target.lane.rawValue) · step \(target.step + 1)")
                .font(Theme.mono(12)).foregroundStyle(Color.mute)
            Slider(value: Binding(get: { Double(hit?.velocity ?? 0.8) },
                                  set: { model.setVelocity(lane: target.lane, step: target.step, Float($0)) }),
                   in: 0.05...1)
                .tint(Color.haze)
                .frame(minHeight: Theme.minTarget)
                .accessibilityLabel("Velocity")
            Button("Done") { velocityTarget = nil }
                .font(Theme.title(14)).foregroundStyle(Color.amber)
                .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
        }
        .padding(.horizontal, 12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Grid

    private var gridArea: some View {
        GeometryReader { proxy in
            let l = layout
            HStack(alignment: .top, spacing: 0) {
                laneLabels
                ScrollView(.horizontal, showsIndicators: false) {
                    grid(l).overlay(alignment: .topLeading) { playhead(l) }
                }
                .scrollDisabled(!l.scrolls)
            }
        }
        .frame(height: rowHeight * CGFloat(Self.lanes.count))
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var laneLabels: some View {
        VStack(spacing: 0) {
            ForEach(Self.lanes, id: \.self) { lane in
                Text(Self.shortName(lane))
                    .font(Theme.mono(10)).foregroundStyle(Color.mute)
                    .frame(width: gutter, height: rowHeight)
            }
        }
    }

    static func shortName(_ lane: DrumLane) -> String {
        switch lane {
        case .kick: "KICK"
        case .snare: "SNR"
        case .clap: "CLP"
        case .closedHat: "HAT"
        case .openHat: "OPEN"
        case .rim: "RIM"
        case .perc: "PERC"
        }
    }

    private func grid(_ l: Layout) -> some View {
        let cell = l.cell
        let size = CGSize(width: cell * CGFloat(l.count), height: rowHeight * CGFloat(Self.lanes.count))
        return Canvas { context, size in
            drawBackground(context, size: size, l)
            for (row, lane) in Self.lanes.enumerated() {
                let y = CGFloat(row) * rowHeight
                for step in l.first..<(l.first + l.count) {
                    drawStep(context, lane: lane, step: step, x: CGFloat(step - l.first) * cell, y: y, cell: cell)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in handleTap(at: tap.location, l) })
        .gesture(
            LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { value in
                    if mode == .draw, case .second(true, let drag?) = value { handleHold(at: drag.startLocation, l) }
                },
            including: mode == .draw ? .all : .none
        )
        .gesture(
            DragGesture(minimumDistance: 10).onEnded { drag in handleRoll(drag, l) },
            including: mode == .roll ? .all : .none
        )
    }

    private func drawBackground(_ context: GraphicsContext, size: CGSize, _ l: Layout) {
        let cell = l.cell
        for i in 0..<l.count where ((l.first + i) / 4) % 2 == 0 {  // shade beats 1 and 3
            context.fill(Path(CGRect(x: CGFloat(i) * cell, y: 0, width: cell, height: size.height)),
                         with: .color(Color.haze.opacity(0.07)))
        }
        for row in 1..<Self.lanes.count {
            context.fill(Path(CGRect(x: 0, y: CGFloat(row) * rowHeight - 0.5, width: size.width, height: 0.5)),
                         with: .color(Color.mute.opacity(0.15)))
        }
        for i in 0...l.count {
            let strong = (l.first + i) % 4 == 0
            context.fill(Path(CGRect(x: CGFloat(i) * cell, y: 0, width: strong ? 1 : 0.5, height: size.height)),
                         with: .color(Color.mute.opacity(strong ? 0.35 : 0.15)))
        }
    }

    private func drawStep(_ context: GraphicsContext, lane: DrumLane, step: Int, x: CGFloat, y: CGFloat, cell: CGFloat) {
        let hits = model.hits(lane: lane, step: step)
        guard !hits.isEmpty else { return }
        let rect = CGRect(x: x + 2, y: y + 4, width: cell - 4, height: rowHeight - 8)
        if model.isRoll(lane: lane, step: step) {
            context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color.haze.opacity(0.18)))
            let stepStart = (model.selectedBar * 16 + step) * Ticks.perSixteenth
            for hit in hits {
                let tx = rect.minX + CGFloat(hit.tick - stepStart) / CGFloat(Ticks.perSixteenth) * rect.width
                let h = max(3, rect.height * CGFloat(hit.velocity))
                context.fill(Path(CGRect(x: tx - 0.75, y: rect.maxY - h, width: 1.5, height: h)), with: .color(Color.haze))
            }
        } else {
            let v = Double(hits[0].velocity)
            context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color.haze.opacity(0.35 + 0.65 * v)))
        }
    }

    private func playhead(_ l: Layout) -> some View {
        let cell = l.cell
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { _ in
            Canvas { context, size in
                guard isPlaying else { return }
                let tick = playheadTick() % max(1, model.loopTicks)
                let barStart = model.selectedBar * Ticks.perBar
                guard tick >= barStart, tick < barStart + Ticks.perBar else { return }
                let step = (tick - barStart) / Ticks.perSixteenth - l.first
                guard step >= 0, step < l.count else { return }
                context.fill(Path(CGRect(x: CGFloat(step) * cell, y: 0, width: cell, height: size.height)),
                             with: .color(Color.amber.opacity(0.22)))
                let x = CGFloat(tick - barStart) / CGFloat(Ticks.perSixteenth) * cell - CGFloat(l.first) * cell
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(Color.amber))
            }
        }
        .frame(width: cell * CGFloat(l.count), height: rowHeight * CGFloat(Self.lanes.count))
        .allowsHitTesting(false)
    }

    private func cellAt(_ point: CGPoint, _ l: Layout, clamp: Bool = false) -> Target? {
        var i = Int((point.x / l.cell).rounded(.down)), row = Int((point.y / rowHeight).rounded(.down))
        if clamp { i = min(l.count - 1, max(0, i)); row = min(Self.lanes.count - 1, max(0, row)) }
        guard i >= 0, i < l.count, row >= 0, row < Self.lanes.count else { return nil }
        return Target(lane: Self.lanes[row], step: l.first + i)
    }

    private func handleTap(at point: CGPoint, _ l: Layout) {
        guard let t = cellAt(point, l) else { return }
        let isRoll = model.isRoll(lane: t.lane, step: t.step)
        if isRoll {
            // Draw mode never deletes a roll by accident; Roll mode clears it on tap.
            guard mode == .roll else { return }
            Theme.lightHaptic()
            model.clearRolls(lane: t.lane, step: t.step)
        } else if mode == .draw {
            Theme.lightHaptic()
            let existed = !model.hits(lane: t.lane, step: t.step).isEmpty
            model.toggle(lane: t.lane, step: t.step)
            if !existed { onPad?(t.lane, 0.8) }
        }
    }

    private func handleHold(at point: CGPoint, _ l: Layout) {
        guard let t = cellAt(point, l), !model.hits(lane: t.lane, step: t.step).isEmpty else { return }
        Theme.lightHaptic()
        if model.isRoll(lane: t.lane, step: t.step) {
            model.clearRolls(lane: t.lane, step: t.step)
            if velocityTarget == t { velocityTarget = nil }
        } else {
            velocityTarget = t
        }
    }

    private func handleRoll(_ drag: DragGesture.Value, _ l: Layout) {
        guard let start = cellAt(drag.startLocation, l),
              let end = cellAt(drag.location, l, clamp: true) else { return }
        model.roll(lane: start.lane, fromStep: start.step, toStep: end.step, rate: rate, ramp: ramp.velocities,
                   descending: ramp.descending)
        Theme.lightHaptic()
    }

    // MARK: Pads

    private var pads: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Self.padLanes, id: \.self) { lane in
                PadView(lane: lane) { onPad?(lane, 0.9) }
            }
        }
    }
}

/// One finger-drumming pad. Fires on touch-down; the highlight lives in a `@GestureState`, so a cancelled
/// touch (a call, a system gesture) still un-highlights it.
private struct PadView: View {
    let lane: DrumLane
    let onHit: () -> Void
    @GestureState private var isDown = false

    var body: some View {
        Text(lane.rawValue)
            .font(Theme.title(15)).foregroundStyle(isDown ? Color.night : Color.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(isDown ? Color.amber : Color.panel, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDown) { _, state, _ in
                        if !state {
                            state = true
                            onHit()  // on touch-down, synchronously
                            Theme.lightHaptic()
                        }
                    }
            )
            .accessibilityLabel("\(lane.rawValue) pad")
            .accessibilityAddTraits(.isButton)
    }
}
