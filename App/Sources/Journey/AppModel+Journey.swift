import MusicCore

enum StageStatus: Equatable {
    case done, inProgress, notStarted, comingLater
}

extension AppModel {
    func stageStatus(_ s: Stage) -> StageStatus {
        guard s.isAvailable else { return .comingLater }
        let completed = s.lessons.filter { progress.completedLessons.contains($0) }.count
        if completed == s.lessons.count { return .done }
        return completed > 0 ? .inProgress : .notStarted
    }

    /// The first available stage that is not done; nil when every available stage is done.
    var currentStageID: String? {
        content.journey.stages.first { s in
            let status = stageStatus(s)
            return status != .done && status != .comingLater
        }?.id
    }

    /// The first lesson of the stage the owner has not completed.
    func nextLesson(in s: Stage) -> Lesson? {
        s.lessons.first { !progress.completedLessons.contains($0) }.flatMap { content.lesson($0) }
    }
}
