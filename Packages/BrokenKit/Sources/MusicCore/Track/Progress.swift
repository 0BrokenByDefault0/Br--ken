import Foundation

public struct Progress: Codable, Equatable, Sendable {
    public var version: Int
    public var completedLessons: Set<String>
    public var currentLessonID: String?
    public var activeTrackID: UUID?

    public init(version: Int = 1, completedLessons: Set<String> = [], currentLessonID: String? = nil,
                activeTrackID: UUID? = nil) {
        self.version = version
        self.completedLessons = completedLessons
        self.currentLessonID = currentLessonID
        self.activeTrackID = activeTrackID
    }

    public static let empty = Progress()
}

public final class ProgressStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> Progress {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return .empty }
        if let data = try? Data(contentsOf: fileURL),
           let p = try? Coding.decoder().decode(Progress.self, from: data) {
            return p
        }
        let corrupt = fileURL.appendingPathExtension("corrupt")
        try? fm.removeItem(at: corrupt)
        try? fm.moveItem(at: fileURL, to: corrupt)
        return .empty
    }

    public func save(_ p: Progress) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Coding.encoder().encode(p).write(to: fileURL, options: .atomic)
    }
}
