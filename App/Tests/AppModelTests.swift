import Testing
import Foundation
import MusicCore
@testable import Broken

@MainActor
private final class FakeAudio: AudioPlaying {
    var tracksSet: [Track] = []
    var playheadTick = 0
    var isPlaying = false
    func setTrack(_ t: Track) { tracksSet.append(t) }
    func play() { isPlaying = true }
    func stop() { isPlaying = false }
    func noteOn(_ i: InstrumentID, _ pitch: Int, _ vel: Float) {}
    func noteOff(_ i: InstrumentID, _ pitch: Int) {}
}

/// A temp sandbox with a tiny content library (journey.json + one lesson) and empty storage.
private struct Sandbox {
    let root: URL
    var contentDir: URL { root.appendingPathComponent("Content") }
    var tracksDir: URL { root.appendingPathComponent("tracks") }
    var progressURL: URL { root.appendingPathComponent("progress.json") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("appmodel-\(UUID().uuidString)")
        let lessons = root.appendingPathComponent("Content/lessons")
        try FileManager.default.createDirectory(at: lessons, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("tracks"), withIntermediateDirectories: true)
        let journey = #"{"version":1,"stages":[{"id":"harmony","title":"Harmony","tagline":"t","order":1,"lessons":["harmony.find"]}]}"#
        try journey.write(to: root.appendingPathComponent("Content/journey.json"), atomically: true, encoding: .utf8)
        let lesson = #"{"id":"harmony.find","stage":"harmony","title":"Find chords","summary":"s","steps":[{"type":"koala","body":"b"}]}"#
        try lesson.write(to: lessons.appendingPathComponent("harmony.find.json"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func makeModel(audio: FakeAudio? = nil) throws -> AppModel {
        AppModel(content: try ContentLibrary(directory: contentDir),
                 trackStore: TrackStore(directory: tracksDir),
                 progressStore: ProgressStore(fileURL: progressURL),
                 audio: audio ?? FakeAudio())
    }
}

private let starter = Clip(tempo: 92, key: "D minor", bars: 2, parts: [
    ClipPart(role: .melody, instrument: .bell, melody: "D4:4 F4:4 A4:4 r:4"),
])

private func chordFinderStep(uses: [PartRole] = [.melody], starter: Clip? = starter) -> LessonStep {
    .task(title: "Find chords", prompt: "p", tool: .chordFinder, targetRole: .chords, uses: uses,
          starter: starter, checks: [], hints: [])
}

private func notes(_ t: Track, _ role: PartRole) -> [NoteEvent] {
    guard case .notes(let seq)? = t.part(role)?.content else { return [] }
    return seq.notes
}

@MainActor
@Test func contentLoadsIntoModel() throws {
    let model = try Sandbox().makeModel()
    #expect(model.content.journey.stages.map(\.title) == ["Harmony"])
    #expect(model.tracks.isEmpty)
    #expect(model.activeTrack == nil)
    #expect(model.progress == .empty)
}

@MainActor
@Test func workingTrackUsesStarterWhenNoTrack() throws {
    let model = try Sandbox().makeModel()
    let working = model.workingTrack(for: chordFinderStep(), lessonID: "harmony.find")
    #expect(notes(working, .melody).map(\.pitch) == [62, 65, 69])
    #expect(working.tempo == 92)
    #expect(working.key == (try Key(parsing: "D minor")))
    #expect(working.part(.chords) == nil)
}

@MainActor
@Test func workingTrackDefaultsWithoutStarter() throws {
    let model = try Sandbox().makeModel()
    let working = model.workingTrack(for: chordFinderStep(uses: [], starter: nil), lessonID: "harmony.find")
    #expect(working.tempo == 140)
    #expect(working.key == (try Key(parsing: "A minor")))
    #expect(working.parts.isEmpty)
}

@MainActor
@Test func workingTrackPrefersOwnersPart() throws {
    let model = try Sandbox().makeModel()
    let mine = model.newTrack(name: "Mine", tempo: 150, key: try Key(parsing: "C minor"))
    model.setActive(mine.id)
    let ownMelody = Part(role: .melody, instrument: .pluck,
                         content: .notes(try Notation.melody("C5:8 Eb5:8")))
    model.updateActiveTrack { $0.setPart(ownMelody) }

    let working = model.workingTrack(for: chordFinderStep(uses: [.melody]), lessonID: "harmony.find")
    #expect(working.id == mine.id)
    #expect(working.part(.melody) == ownMelody)
    #expect(working.tempo == 150, "the owner's tempo wins over the starter's")
    #expect(working.key == (try Key(parsing: "C minor")))
}

@MainActor
@Test func workingTrackFillsMissingRoleIntoOwnersTrack() throws {
    let model = try Sandbox().makeModel()
    let mine = model.newTrack(name: "Mine", tempo: 150, key: try Key(parsing: "C minor"))
    model.setActive(mine.id)
    let working = model.workingTrack(for: chordFinderStep(uses: [.melody]), lessonID: "harmony.find")
    #expect(notes(working, .melody).count == 3, "the starter's melody fills the empty role")
    #expect(working.tempo == 150)
    #expect(model.activeTrack?.part(.melody) == nil, "the active track itself is untouched")
}

@MainActor
@Test func keepCreatesTrackAndPersists() throws {
    let sandbox = try Sandbox()
    let audio = FakeAudio()
    let model = try sandbox.makeModel(audio: audio)
    var working = model.workingTrack(for: chordFinderStep(), lessonID: "harmony.find")
    let chords = Part(role: .chords, instrument: .pad, content: .chords(try Notation.chords("Dm:16 Bb:16")))
    working.setPart(chords)

    model.keep(roles: [.chords], from: working, lessonID: "harmony.find")

    let active = try #require(model.activeTrack)
    #expect(active.name == "My first beat")
    #expect(active.tempo == 92)
    #expect(active.part(.chords) == chords)
    #expect(active.part(.melody) == nil, "only the kept roles are copied")
    #expect(audio.tracksSet.last == active)

    let reloaded = TrackStore(directory: sandbox.tracksDir).loadAll()
    #expect(reloaded.tracks.count == 1)
    #expect(reloaded.tracks.first?.part(.chords) == chords)
    let progress = ProgressStore(fileURL: sandbox.progressURL).load()
    #expect(progress.completedLessons.contains("harmony.find"))
    #expect(progress.activeTrackID == active.id)

    let again = try sandbox.makeModel()
    #expect(again.activeTrack?.id == active.id)
}

@MainActor
@Test func keepAddsToExistingActiveTrack() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    let mine = model.newTrack(name: "Mine", tempo: 150, key: try Key(parsing: "C minor"))
    model.setActive(mine.id)
    var working = model.workingTrack(for: chordFinderStep(), lessonID: "harmony.find")
    working.setPart(Part(role: .chords, instrument: .pad, content: .chords(try Notation.chords("Cm:16 Ab:16"))))

    model.keep(roles: [.chords], from: working, lessonID: "harmony.find")

    #expect(model.tracks.count == 1)
    #expect(model.activeTrack?.id == mine.id)
    #expect(model.activeTrack?.name == "Mine")
    #expect(model.activeTrack?.part(.chords) != nil)
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first?.part(.chords) != nil)
}

@MainActor
@Test func markLessonCompletePersists() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    model.markLessonComplete("harmony.find")
    #expect(model.progress.completedLessons == ["harmony.find"])
    #expect(ProgressStore(fileURL: sandbox.progressURL).load().completedLessons == ["harmony.find"])
}

@MainActor
@Test func skippedFilesSurfaced() throws {
    let sandbox = try Sandbox()
    try Data("not a track".utf8).write(to: sandbox.tracksDir.appendingPathComponent("broken.json"))
    let model = try sandbox.makeModel()
    #expect(model.skippedFiles.count == 1)
    #expect(model.tracks.isEmpty)
}
