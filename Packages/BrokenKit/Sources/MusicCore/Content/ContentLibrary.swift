import Foundation

public final class ContentLibrary: Sendable {
    public let journey: Journey
    private let lessonsByID: [String: Lesson]

    /// Reads `journey.json` and every `lessons/*.json`; throws if any is malformed.
    public init(directory: URL) throws {
        let decoder = JSONDecoder()
        journey = try decoder.decode(Journey.self, from: Data(contentsOf: directory.appendingPathComponent("journey.json")))
        var map: [String: Lesson] = [:]
        for url in try ContentLibrary.lessonFiles(in: directory) {
            let lesson = try decoder.decode(Lesson.self, from: Data(contentsOf: url))
            map[lesson.id] = lesson
        }
        lessonsByID = map
    }

    public func lesson(_ id: String) -> Lesson? { lessonsByID[id] }

    /// Lessons in the order the stage lists them; missing ids are skipped.
    public func lessons(in stage: Stage) -> [Lesson] {
        stage.lessons.compactMap { lessonsByID[$0] }
    }

    static func lessonFiles(in directory: URL) throws -> [URL] {
        let dir = directory.appendingPathComponent("lessons")
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
