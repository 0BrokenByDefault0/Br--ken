import Foundation
import MusicCore
// Foundation also has a `Progress` (NSProgress); this scoped import makes MusicCore's win in this file.
import struct MusicCore.Progress
import Observation

/// App-wide state: lesson content, the owner's tracks, and lesson progress. Every change is saved
/// right away; save failures are shown through `lastError` instead of crashing.
@Observable @MainActor
final class AppModel {
    /// Used when there is no track and no starter to take tempo, key, and length from.
    static let defaultTempo = 140.0
    static let defaultKey = Key(tonic: PitchClass(9), mode: .minor)  // A minor
    static let defaultBars = 2

    let content: ContentLibrary
    var tracks: [Track]
    var progress: Progress
    /// Track files that could not be loaded (corrupt, or saved by a newer app version).
    var skippedFiles: [URL]
    private(set) var lastError: String?

    private let trackStore: TrackStore
    private let progressStore: ProgressStore
    private let audio: any AudioPlaying

    init(content: ContentLibrary, trackStore: TrackStore, progressStore: ProgressStore, audio: any AudioPlaying) {
        self.content = content
        self.trackStore = trackStore
        self.progressStore = progressStore
        self.audio = audio
        let report = trackStore.loadAll()
        tracks = report.tracks
        skippedFiles = report.skipped
        progress = progressStore.load()
        if let activeTrack { audio.setTrack(activeTrack) }
    }

    /// The owner's track that lessons build on ("Your Track").
    var activeTrack: Track? {
        guard let id = progress.activeTrackID else { return nil }
        return tracks.first { $0.id == id }
    }

    /// Creates and saves an empty track (it does not become active).
    func newTrack(name: String, tempo: Double, key: Key) -> Track {
        let track = Track(name: name, createdAt: Date(), tempo: tempo, key: key, bars: Self.defaultBars, parts: [])
        save(track)
        return track
    }

    func setActive(_ id: UUID) {
        progress.activeTrackID = id
        saveProgress()
        if let activeTrack { audio.setTrack(activeTrack) }
    }

    /// Applies `mutate` to the active track, saves it, then plays the result. No-op without an active track.
    func updateActiveTrack(_ mutate: (inout Track) -> Void) {
        guard var track = activeTrack else { return }
        mutate(&track)
        save(track)
        audio.setTrack(track)
    }

    /// The track a lesson step works on. It is a copy of the active track (the owner's tempo, key, and
    /// parts win), or a new "Practice" track at the starter's (or the default) tempo and key. Every role
    /// the step `uses` that the track lacks is filled with the starter's part, so any lesson works on
    /// an empty or partial track.
    func workingTrack(for step: LessonStep, lessonID: String) -> Track {
        guard case .task(_, _, _, _, let uses, let starter, _, _) = step else {
            return activeTrack ?? Self.emptyTrack(name: "Practice")
        }
        let starterTrack = starter.flatMap { try? $0.makeTrack(name: "Practice") }
        var working = activeTrack
            ?? starterTrack.map { Track(name: "Practice", createdAt: Date(), tempo: $0.tempo, key: $0.key,
                                        bars: $0.bars, parts: []) }
            ?? Self.emptyTrack(name: "Practice")
        for role in uses where working.part(role) == nil {
            if let part = starterTrack?.part(role) { working.setPart(part) }
        }
        return working
    }

    /// Copies `roles` from the working track into the active track (creating "My first beat" from the
    /// working track's tempo, key, and length if there is none), makes it active, completes the lesson,
    /// and saves both.
    func keep(roles: [PartRole], from working: Track, lessonID: String) {
        var track = activeTrack
            ?? Track(name: "My first beat", createdAt: Date(), tempo: working.tempo, key: working.key,
                     bars: working.bars, parts: [])
        for role in roles {
            if let part = working.part(role) { track.setPart(part) }
        }
        save(track)
        progress.activeTrackID = track.id
        progress.completedLessons.insert(lessonID)
        saveProgress()
        audio.setTrack(track)
    }

    func markLessonComplete(_ id: String) {
        progress.completedLessons.insert(id)
        saveProgress()
    }

    private static func emptyTrack(name: String) -> Track {
        Track(name: name, createdAt: Date(), tempo: defaultTempo, key: defaultKey, bars: defaultBars, parts: [])
    }

    /// Writes the track and puts it in `tracks` (replacing the one with the same id, else first).
    private func save(_ track: Track) {
        if let i = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[i] = track
        } else {
            tracks.insert(track, at: 0)
        }
        do {
            try trackStore.save(track)
        } catch {
            lastError = "Couldn't save \(track.name): \(error.localizedDescription)"
        }
    }

    private func saveProgress() {
        do {
            try progressStore.save(progress)
        } catch {
            lastError = "Couldn't save progress: \(error.localizedDescription)"
        }
    }
}
