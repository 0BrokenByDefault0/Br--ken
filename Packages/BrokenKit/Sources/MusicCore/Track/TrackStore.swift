import Foundation

public struct LoadReport {
    public var tracks: [Track]
    public var skipped: [URL]

    public init(tracks: [Track], skipped: [URL]) {
        self.tracks = tracks
        self.skipped = skipped
    }
}

private struct VersionProbe: Decodable {
    let version: Int?
}

public final class TrackStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func loadAll() -> LoadReport {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var tracks: [Track] = []
        var skipped: [URL] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else {
                skipped.append(url)
                continue
            }
            if let probe = try? JSONDecoder().decode(VersionProbe.self, from: data),
               let v = probe.version, v > Track.currentVersion {
                skipped.append(url)
                continue
            }
            if let track = try? Coding.decoder().decode(Track.self, from: data) {
                tracks.append(track)
            } else {
                let corrupt = url.appendingPathExtension("corrupt")
                try? fm.removeItem(at: corrupt)
                try? fm.moveItem(at: url, to: corrupt)
                skipped.append(url)
            }
        }
        tracks.sort { $0.createdAt > $1.createdAt }
        return LoadReport(tracks: tracks, skipped: skipped)
    }

    public func save(_ t: Track) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Coding.encoder().encode(t)
        try data.write(to: fileURL(for: t.id), options: .atomic)
    }

    public func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: fileURL(for: id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}

enum Coding {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
