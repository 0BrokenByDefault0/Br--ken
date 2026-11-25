import Foundation

public enum ContentValidator {
    /// Never throws; returns human-readable errors, each naming the lesson id or file involved.
    public static func validate(directory: URL) -> [String] {
        var errors: [String] = []
        let decoder = JSONDecoder()

        let journey: Journey
        do {
            journey = try decoder.decode(Journey.self, from: Data(contentsOf: directory.appendingPathComponent("journey.json")))
        } catch {
            return ["journey.json: cannot be read or decoded (\(error))"]
        }

        var lessons: [String: Lesson] = [:]
        var files: [URL] = []
        do { files = try ContentLibrary.lessonFiles(in: directory) } catch {
            errors.append("lessons folder: cannot be listed (\(error))")
        }
        for url in files {
            let name = url.lastPathComponent
            do {
                let lesson = try decoder.decode(Lesson.self, from: Data(contentsOf: url))
                if lessons[lesson.id] != nil {
                    errors.append("\(name): duplicate lesson id '\(lesson.id)'")
                } else {
                    lessons[lesson.id] = lesson
                }
            } catch {
                errors.append("\(name): lesson file failed to decode (\(error))")
            }
        }

        for stage in journey.stages {
            for id in stage.lessons {
                guard let lesson = lessons[id] else {
                    errors.append("stage '\(stage.id)': lists lesson '\(id)' but no lesson file has that id")
                    continue
                }
                if lesson.stage != stage.id {
                    errors.append("lesson '\(id)': stage is '\(lesson.stage)' but it is listed by stage '\(stage.id)'")
                }
            }
        }

        for lesson in lessons.values.sorted(by: { $0.id < $1.id }) {
            errors += validate(lesson)
        }
        return errors
    }

    private static func validate(_ lesson: Lesson) -> [String] {
        var errors: [String] = []
        func checkClip(_ clip: Clip, _ where_: String) {
            do { _ = try clip.makeTrack(name: "check") } catch {
                errors.append("lesson '\(lesson.id)', \(where_): clip does not parse (\(error))")
            }
        }
        for (i, step) in lesson.steps.enumerated() {
            let at = "step \(i + 1)"
            switch step {
            case .listen(_, _, let examples):
                for (j, ex) in examples.enumerated() { checkClip(ex.clip, "\(at) example \(j + 1)") }
            case .task(_, _, let tool, let targetRole, let uses, let starter, let checks, _):
                if let starter { checkClip(starter, "\(at) starter") }
                if !uses.isEmpty {
                    if let starter {
                        for role in uses where !starter.parts.contains(where: { $0.role == role }) {
                            errors.append("lesson '\(lesson.id)', \(at): uses '\(role.rawValue)' but its starter lacks that role")
                        }
                    } else {
                        errors.append("lesson '\(lesson.id)', \(at): uses roles but has no starter")
                    }
                }
                let allowed = Set(uses + (targetRole.map { [$0] } ?? []))
                for check in checks {
                    for role in roles(of: check) where !allowed.contains(role) {
                        errors.append("lesson '\(lesson.id)', \(at): check references role '\(role.rawValue)' which is neither targetRole nor in uses")
                    }
                    if isDrumCheck(check) && tool != .drumGrid {
                        errors.append("lesson '\(lesson.id)', \(at): drum check in a task whose tool is '\(tool.rawValue)', not drumGrid")
                    }
                }
            case .idea, .keep, .koala:
                break
            }
        }
        return errors
    }

    private static func roles(of check: TaskCheck) -> [PartRole] {
        switch check {
        case .inKey(let r), .noteCount(let r, _, _), .barRhythmRepeats(let r), .endsOnDegree(let r, _),
             .chordCount(let r, _, _), .chordsInKey(let r), .chordDegrees(let r, _), .extendedChordCount(let r, _),
             .barsDiffer(let r):
            return [r]
        case .chordsFitMelody(let chords, let melody, _):
            return [chords, melody]
        case .tempoInRange, .drumHitOnBeats, .laneHitCount, .hatRollPresent, .syncopatedKicks:
            return []
        }
    }

    private static func isDrumCheck(_ check: TaskCheck) -> Bool {
        switch check {
        case .drumHitOnBeats, .laneHitCount, .hatRollPresent, .syncopatedKicks: true
        case .tempoInRange, .inKey, .noteCount, .barRhythmRepeats, .endsOnDegree, .chordCount, .chordsInKey,
             .chordDegrees, .chordsFitMelody, .extendedChordCount, .barsDiffer: false
        }
    }
}
