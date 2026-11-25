import SwiftUI
import MusicCore

/// The Journey: Your Track card on top, then a vertical timeline of every stage. Tap a stage to list its
/// lessons; nothing is locked except stages that are coming later.
struct JourneyMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Set<String> = []
    @State private var pulse = false

    /// Called when a lesson is tapped (after it is saved as the current lesson).
    let onOpenLesson: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                YourTrackBar()
                let stages = model.content.journey.stages.sorted { $0.order < $1.order }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                        stageRow(stage, number: index + 1)
                    }
                    styleGuidesRow
                }
            }
            .padding(16)
        }
        .background(Color.night.ignoresSafeArea())
        .navigationTitle("Journey")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func stageRow(_ stage: Stage, number: Int) -> some View {
        let status = model.stageStatus(stage)
        let isCurrent = model.currentStageID == stage.id
        let isOpen = expanded.contains(stage.id) && status != .comingLater
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                node(number: number, status: status, isCurrent: isCurrent)
                Rectangle().fill(Color.mute.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    guard status != .comingLater else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        if isOpen { expanded.remove(stage.id) } else { expanded.insert(stage.id) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(stage.title).font(Theme.title(19))
                                .foregroundStyle(status == .comingLater ? Color.mute : Color.ink)
                            if isCurrent { pill("you're here", fill: Color.amber) }
                            Spacer(minLength: 0)
                            if status != .comingLater {
                                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.mute)
                            }
                        }
                        Text(stage.tagline).font(Theme.body(14)).foregroundStyle(Color.mute)
                            .multilineTextAlignment(.leading)
                        if status == .comingLater {
                            Text("coming in a later update").font(Theme.mono(12)).foregroundStyle(Color.mute)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(status == .comingLater)
                .accessibilityElement(children: .combine)
                .accessibilityValue(accessibilityStatus(status, isCurrent: isCurrent))

                if isOpen { lessonList(stage) }
            }
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private func node(number: Int, status: StageStatus, isCurrent: Bool) -> some View {
        let label = Text("\(number)").font(Theme.title(16))
        ZStack {
            switch status {
            case .done:
                Circle().fill(Color.haze)
                label.foregroundStyle(Color.night)
            case .comingLater:
                Circle().strokeBorder(Color.mute.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                label.foregroundStyle(Color.mute)
            default:
                if isCurrent {
                    Circle().strokeBorder(Color.amber, lineWidth: 3)
                        .scaleEffect(pulse ? 1.12 : 1).opacity(pulse ? 0.55 : 1)
                    Circle().strokeBorder(Color.amber, lineWidth: 3).padding(2)
                    label.foregroundStyle(Color.amber)
                } else {
                    Circle().strokeBorder(Color.haze, lineWidth: 2)
                    label.foregroundStyle(Color.haze)
                }
            }
        }
        .frame(width: 40, height: 40)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func lessonList(_ stage: Stage) -> some View {
        let next = model.nextLesson(in: stage)
        return VStack(spacing: 6) {
            ForEach(model.content.lessons(in: stage)) { lesson in
                let done = model.progress.completedLessons.contains(lesson.id)
                Button {
                    model.openLesson(lesson.id)
                    onOpenLesson()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundStyle(done ? Color.tone : Color.mute)
                        Text(lesson.title).font(Theme.body(16)).foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if lesson.id == next?.id { pill("Start", fill: Color.amber) }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: Theme.minTarget)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityValue(done ? "Completed" : "Not completed")
            }
        }
    }

    private var styleGuidesRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.closed").font(.system(size: 18)).foregroundStyle(Color.mute)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Style guides").font(Theme.title(17)).foregroundStyle(Color.mute)
                Text("coming later").font(Theme.mono(12)).foregroundStyle(Color.mute)
            }
            Spacer()
        }
        .frame(minHeight: Theme.minTarget)
        .accessibilityElement(children: .combine)
    }

    private func pill(_ text: String, fill: Color) -> some View {
        Text(text).font(Theme.body(12).weight(.semibold)).foregroundStyle(Color.night)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(fill, in: Capsule())
    }

    private func accessibilityStatus(_ status: StageStatus, isCurrent: Bool) -> String {
        switch status {
        case .done: "Done"
        case .inProgress: isCurrent ? "In progress, you're here" : "In progress"
        case .notStarted: isCurrent ? "Not started, you're here" : "Not started"
        case .comingLater: "Coming in a later update"
        }
    }
}
