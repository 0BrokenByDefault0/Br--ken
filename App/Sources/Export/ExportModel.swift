import Foundation
import MusicCore
import SoundEngine
import Observation

enum ExportScope: Hashable {
    case fullMix, part(UUID), stems
}

/// Renders a track to WAV files in `directory` (Documents/Exports in the app).
@MainActor
@Observable
final class ExportModel {
    let track: Track
    let directory: URL
    private(set) var isExporting = false
    private(set) var urls: [URL] = []
    private(set) var errorMessage: String?

    init(track: Track, directory: URL) {
        self.track = track
        self.directory = directory
    }

    /// The app's export folder, visible in the Files app: Documents/Exports.
    static var defaultDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("Exports", isDirectory: true)
    }

    /// Renders off the main actor and writes the files (same name overwrites). Full mix renders the
    /// unmuted parts; stems write one file per unmuted part with content; `.part` exports that part
    /// even if muted.
    func export(scope: ExportScope, loopReady: Bool) async throws -> [URL] {
        let track = self.track
        let directory = self.directory
        return try await Task.detached(priority: .userInitiated) {
            try Self.render(track: track, scope: scope, loopReady: loopReady, directory: directory)
        }.value
    }

    /// Runs `export` and publishes progress, files, and any error for the sheet.
    func run(scope: ExportScope, loopReady: Bool) async {
        guard !isExporting else { return }
        isExporting = true
        errorMessage = nil
        urls = []
        defer { isExporting = false }
        do {
            urls = try await export(scope: scope, loopReady: loopReady)
        } catch {
            errorMessage = "Couldn't export: \(error.localizedDescription)"
        }
    }

    func resetResult() { urls = []; errorMessage = nil }

    nonisolated private static func render(track: Track, scope: ExportScope, loopReady: Bool,
                                           directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var jobs: [(name: String, only: UUID?)] = []
        switch scope {
        case .fullMix:
            jobs = [(ExportNaming.fileName(track: track, part: nil), nil)]
        case .part(let id):
            guard let part = track.parts.first(where: { $0.id == id }) else { throw ExportError.partMissing }
            jobs = [(ExportNaming.fileName(track: track, part: part), id)]
        case .stems:
            var used = Set<String>()
            for part in track.parts where !part.muted && part.hasContent {
                var name = ExportNaming.fileName(track: track, part: part)
                var n = 2
                while !used.insert(name).inserted {
                    name = ExportNaming.fileName(track: track, part: part)
                        .replacingOccurrences(of: ".wav", with: "-\(n).wav")
                    n += 1
                }
                jobs.append((name, part.id))
            }
            if jobs.isEmpty { throw ExportError.nothingToExport }
        }
        var out: [URL] = []
        for job in jobs {
            let buffer = OfflineRenderer.render(track: track, onlyPart: job.only, loopReady: loopReady)
            let url = directory.appendingPathComponent(job.name)
            try WAVWriter.write(buffer, sampleRate: 48_000, to: url)
            out.append(url)
        }
        return out
    }

    nonisolated private static func hasContent(_ part: Part) -> Bool { part.hasContent }
}

enum ExportError: LocalizedError {
    case partMissing, nothingToExport
    var errorDescription: String? {
        switch self {
        case .partMissing: "That part isn't in the track any more."
        case .nothingToExport: "No part has any notes yet."
        }
    }
}
