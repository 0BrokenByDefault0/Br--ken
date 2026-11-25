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
    /// The audio player: tool screens use it directly for live notes and the playhead.
    let audio: any AudioPlaying
    /// True while the loop is playing (the active track, or a Chord Finder audition).
    private(set) var isPlaying = false
    /// While on, a rim click on every beat is mixed into what is played (the saved track is unchanged).
    var metronome = false { didSet { if let activeTrack, !auditioning { send(activeTrack) } } }
    private var auditioning = false
    /// True while the active track has slider changes that are heard but not yet saved.
    private(set) var hasUncommittedPreview = false

    init(content: ContentLibrary, trackStore: TrackStore, progressStore: ProgressStore, audio: any AudioPlaying) {
        self.content = content
        self.trackStore = trackStore
        self.progressStore = progressStore
        self.audio = audio
        let report = trackStore.loadAll()
        tracks = report.tracks
        skippedFiles = report.skipped
        progress = progressStore.load()
        if let activeTrack { send(activeTrack) }
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

    /// Creates a track and makes it active.
    @discardableResult
    func startTrack(name: String, tempo: Double, key: Key) -> Track {
        let track = newTrack(name: name, tempo: tempo, key: key)
        setActive(track.id)
        return track
    }

    func setActive(_ id: UUID) {
        flushPendingPreview()  // the track being left keeps its edits
        progress.activeTrackID = id
        saveProgress()
        if let activeTrack { send(activeTrack) }
    }

    /// Applies `mutate` to the active track, saves it, then plays the result. No-op without an active track.
    /// With `persist: false` (a slider mid-drag) the change is kept in memory and heard, but not written to
    /// disk; call `commitActiveTrack()` when the drag ends.
    func updateActiveTrack(persist: Bool = true, _ mutate: (inout Track) -> Void) {
        guard var track = activeTrack else { return }
        mutate(&track)
        save(track, persist: persist)
        hasUncommittedPreview = !persist
        send(track)
    }

    /// Live change without saving (see `updateActiveTrack(persist:)`).
    func previewActiveTrack(_ mutate: (inout Track) -> Void) {
        updateActiveTrack(persist: false, mutate)
    }

    /// Writes the active track's current in-memory state to disk (the end of a slider drag).
    func commitActiveTrack() {
        guard let track = activeTrack else { return }
        save(track)
        hasUncommittedPreview = false
    }

    /// Saves previewed changes that were never committed (an interrupted drag, a tab change, the app
    /// going to the background, switching tracks). No-op when there are none.
    func flushPendingPreview() {
        if hasUncommittedPreview { commitActiveTrack() }
    }

    /// Edits the active track's part for `role`, creating an empty one (`instrument`, `empty`) on the
    /// first edit. An existing part keeps its instrument. No-op without an active track.
    func editActivePart(_ role: PartRole, instrument: InstrumentID, empty: PartContent, persist: Bool = true,
                        _ mutate: (inout Part) -> Void) {
        updateActiveTrack(persist: persist) { track in
            var part = track.part(role) ?? Part(role: role, instrument: instrument, content: empty)
            mutate(&part)
            track.setPart(part)
        }
    }

    /// Mutes or unmutes a part of the active track. No-op if the track has no such part.
    func setMuted(role: PartRole, _ muted: Bool) {
        guard activeTrack?.part(role) != nil else { return }
        updateActiveTrack { track in
            guard var part = track.part(role) else { return }
            part.muted = muted
            track.setPart(part)
        }
    }

    func renameTrack(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var track = tracks.first(where: { $0.id == id }) else { return }
        track.name = trimmed
        save(track)
    }

    /// Deletes the track's file. If it was the active track, there is no active track afterwards.
    func deleteTrack(id: UUID) {
        let wasActive = progress.activeTrackID == id
        do {
            try trackStore.delete(id: id)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // Already gone from disk: nothing left to keep.
        } catch {
            lastError = "Couldn't delete the track: \(error.localizedDescription)"
            return  // still on disk, so it stays in the list
        }
        tracks.removeAll { $0.id == id }
        if wasActive {
            hasUncommittedPreview = false
            stop()
            progress.activeTrackID = nil
            saveProgress()
        }
    }

    /// Plays the active track from the start (puts it back first if an audition replaced it).
    func play() {
        guard let activeTrack else { return }
        auditioning = false
        send(activeTrack)
        audio.play()
        isPlaying = true
    }

    /// Plays a temporary track (a Chord Finder audition, a lesson loop or example) from the start.
    /// `stop()` restores the active track. With `atTrackTempo` (the default) it plays at the active
    /// track's current tempo; lesson examples and working tracks keep their own.
    func audition(_ track: Track, atTrackTempo: Bool = true) {
        auditioning = true
        var track = track
        if atTrackTempo, let activeTrack { track.tempo = activeTrack.tempo }
        send(track)
        audio.play()
        isPlaying = true
    }

    /// Swaps what a playing audition plays without restarting it (an edit, or a mute toggle, while a
    /// lesson loop plays). No-op unless an audition is playing.
    func updateAudition(_ track: Track) {
        guard auditioning, isPlaying else { return }
        send(track)
    }

    func stop() {
        audio.stop()
        isPlaying = false
        if auditioning {
            auditioning = false
            if let activeTrack { send(activeTrack) }
        }
    }

    func dismissError() { lastError = nil }

    /// "My first beat" for the first track, then "Beat 2", "Beat 3"... skipping names already in use.
    var defaultTrackName: String {
        if tracks.isEmpty { return "My first beat" }
        var n = tracks.count + 1
        while tracks.contains(where: { $0.name == "Beat \(n)" }) { n += 1 }
        return "Beat \(n)"
    }

    /// Saves lesson progress: the lesson the Lesson tab shows.
    func openLesson(_ id: String) {
        progress.currentLessonID = id
        saveProgress()
    }

    var currentLesson: Lesson? { progress.currentLessonID.flatMap { content.lesson($0) } }

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

    /// Copies `roles` that have content from the working track into the active track (creating "My first beat" from the
    /// working track's tempo, key, and length if there is none), makes it active, completes the lesson,
    /// and saves both.
    func keep(roles: [PartRole], from working: Track, lessonID: String) {
        var track = activeTrack
            ?? Track(name: "My first beat", createdAt: Date(), tempo: working.tempo, key: working.key,
                     bars: working.bars, parts: [])
        for role in roles {
            // An empty part (a skipped task) is never kept: it would add an empty part, or replace a real
            // part with silence. A replaced part keeps the saved part's mute.
            guard var part = working.part(role), part.hasContent else { continue }
            if let saved = track.part(role) { part.muted = saved.muted }
            track.setPart(part)
        }
        commitKept(track, lessonID: lessonID)
    }

    /// The keep after a track-setup task: applies the working track's tempo and key to the active track
    /// (its name and parts stay), or creates the active track from the working track's name, tempo, and
    /// key. Completes the lesson and saves.
    func keepSetup(from working: Track, lessonID: String) {
        var track = activeTrack
            ?? Track(name: working.name, createdAt: Date(), tempo: working.tempo, key: working.key,
                     bars: working.bars, parts: [])
        track.tempo = working.tempo
        track.key = working.key
        commitKept(track, lessonID: lessonID)
    }

    private func commitKept(_ track: Track, lessonID: String) {
        save(track)
        hasUncommittedPreview = false  // the whole track, preview included, was just written
        progress.activeTrackID = track.id
        progress.completedLessons.insert(lessonID)
        saveProgress()
        send(track)
    }

    func markLessonComplete(_ id: String) {
        progress.completedLessons.insert(id)
        saveProgress()
    }

    private func send(_ track: Track) {
        audio.setTrack(metronome ? withMetronome(track) : track)
    }

    private static func emptyTrack(name: String) -> Track {
        Track(name: name, createdAt: Date(), tempo: defaultTempo, key: defaultKey, bars: defaultBars, parts: [])
    }

    /// Writes the track and puts it in `tracks` (replacing the one with the same id, else first).
    private func save(_ track: Track, persist: Bool = true) {
        if let i = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[i] = track
        } else {
            tracks.insert(track, at: 0)
        }
        guard persist else { return }
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

extension Part {
    /// False for a part with no notes, no chord slots, or no drum hits.
    var hasContent: Bool {
        switch content {
        case .notes(let sequence): !sequence.notes.isEmpty
        case .chords(let progression): !progression.slots.isEmpty
        case .drums(let pattern): pattern.lanes.values.contains { !$0.isEmpty }
        }
    }
}
