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

    /// `stages`: (stage id, lesson ids) in order; the default is one stage with one lesson.
    init(stages: [(String, [String])] = [("harmony", ["harmony.find"])]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("appmodel-\(UUID().uuidString)")
        let lessons = root.appendingPathComponent("Content/lessons")
        try FileManager.default.createDirectory(at: lessons, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("tracks"), withIntermediateDirectories: true)
        let stageJSON = stages.enumerated().map { i, stage in
            let ids = stage.1.map { "\"\($0)\"" }.joined(separator: ",")
            let title = stage.0 == "harmony" ? "Harmony" : stage.0
            return #"{"id":"\#(stage.0)","title":"\#(title)","tagline":"t","order":\#(i + 1),"lessons":[\#(ids)]}"#
        }.joined(separator: ",")
        let journey = #"{"version":1,"stages":[\#(stageJSON)]}"#
        try journey.write(to: root.appendingPathComponent("Content/journey.json"), atomically: true, encoding: .utf8)
        for (stageID, ids) in stages {
            for id in ids {
                let title = id == "harmony.find" ? "Find chords" : id
                let lesson = #"{"id":"\#(id)","stage":"\#(stageID)","title":"\#(title)","summary":"s","steps":[{"type":"koala","body":"b"}]}"#
                try lesson.write(to: lessons.appendingPathComponent("\(id).json"), atomically: true, encoding: .utf8)
            }
        }
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

// MARK: - Journey

private let journeyStages: [(String, [String])] = [
    ("rhythm", ["r.1", "r.2"]), ("melody", ["m.1", "m.2"]), ("harmony", ["h.1"]), ("later", [])]

@MainActor
@Test func stageStatuses() throws {
    let model = try Sandbox(stages: journeyStages).makeModel()
    let stages = model.content.journey.stages
    #expect(stages.map { model.stageStatus($0) } == [.notStarted, .notStarted, .notStarted, .comingLater])
    model.markLessonComplete("r.1")
    #expect(model.stageStatus(stages[0]) == .inProgress)
    model.markLessonComplete("r.2")
    #expect(model.stageStatus(stages[0]) == .done)
    #expect(model.stageStatus(stages[3]) == .comingLater)
}

@MainActor
@Test func currentStageIsFirstUnfinished() throws {
    let model = try Sandbox(stages: journeyStages).makeModel()
    #expect(model.currentStageID == "rhythm")
    model.markLessonComplete("r.1")
    #expect(model.currentStageID == "rhythm", "in progress is not done")
    model.markLessonComplete("r.2")
    #expect(model.currentStageID == "melody")
    for id in ["m.1", "m.2", "h.1"] { model.markLessonComplete(id) }
    #expect(model.currentStageID == nil, "coming-later stages never count")
}

@MainActor
@Test func nextLessonSkipsCompleted() throws {
    let model = try Sandbox(stages: journeyStages).makeModel()
    let stages = model.content.journey.stages
    #expect(model.nextLesson(in: stages[0])?.id == "r.1")
    model.markLessonComplete("r.1")
    #expect(model.nextLesson(in: stages[0])?.id == "r.2")
    model.markLessonComplete("r.2")
    #expect(model.nextLesson(in: stages[0]) == nil)
    #expect(model.nextLesson(in: stages[3]) == nil)
}

@MainActor
@Test func openLessonPersistsCurrent() throws {
    let sandbox = try Sandbox(stages: journeyStages)
    let model = try sandbox.makeModel()
    model.openLesson("m.2")
    #expect(model.progress.currentLessonID == "m.2")
    #expect(model.currentLesson?.id == "m.2")
    #expect(ProgressStore(fileURL: sandbox.progressURL).load().currentLessonID == "m.2")
}

// MARK: - Track management

@MainActor
@Test func renameTrackPersists() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    let t = model.newTrack(name: "Old", tempo: 140, key: try Key(parsing: "A minor"))
    model.renameTrack(id: t.id, to: "  New name ")
    #expect(model.tracks.first?.name == "New name")
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first?.name == "New name")
    model.renameTrack(id: t.id, to: "   ")
    #expect(model.tracks.first?.name == "New name", "a blank name is ignored")
}

@MainActor
@Test func deleteActiveTrackClearsActive() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    let a = model.newTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    let b = model.newTrack(name: "B", tempo: 140, key: try Key(parsing: "A minor"))
    model.setActive(a.id)
    model.deleteTrack(id: b.id)
    #expect(model.activeTrack?.id == a.id, "deleting another track keeps the active one")
    model.deleteTrack(id: a.id)
    #expect(model.tracks.isEmpty)
    #expect(model.activeTrack == nil)
    #expect(model.progress.activeTrackID == nil)
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.isEmpty)
    #expect(ProgressStore(fileURL: sandbox.progressURL).load().activeTrackID == nil)
}

@MainActor
@Test func setMutedTogglesPartAndSendsAudio() throws {
    let audio = FakeAudio()
    let model = try Sandbox().makeModel(audio: audio)
    let t = model.newTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    model.setActive(t.id)
    model.updateActiveTrack { $0.setPart(Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: [:])))) }
    model.setMuted(role: .drums, true)
    #expect(model.activeTrack?.part(.drums)?.muted == true)
    #expect(audio.tracksSet.last?.part(.drums)?.muted == true)
    model.setMuted(role: .drums, false)
    #expect(model.activeTrack?.part(.drums)?.muted == false)
    model.setMuted(role: .melody, true)  // no melody part: nothing happens
    #expect(model.activeTrack?.part(.melody) == nil)
}

@MainActor
@Test func editActivePartCreatesEmptyPartOnFirstEdit() throws {
    let model = try Sandbox().makeModel()
    model.editActivePart(.melody, instrument: .bell, empty: .notes(NoteSequence(notes: []))) { _ in }
    #expect(model.activeTrack == nil, "no active track: no-op")
    let t = model.newTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    model.setActive(t.id)
    let seq = NoteSequence(notes: [NoteEvent(start: 0, length: 96, pitch: 69)])
    model.editActivePart(.melody, instrument: .bell, empty: .notes(NoteSequence(notes: []))) { $0.content = .notes(seq) }
    #expect(model.activeTrack?.part(.melody)?.instrument == .bell)
    #expect(model.activeTrack?.part(.melody)?.content == .notes(seq))
    model.editActivePart(.melody, instrument: .pluck, empty: .notes(NoteSequence(notes: []))) { $0.sound.volume = 0.5 }
    #expect(model.activeTrack?.parts.count == 1)
    #expect(model.activeTrack?.part(.melody)?.instrument == .bell, "an existing part keeps its instrument")
    #expect(model.activeTrack?.part(.melody)?.content == .notes(seq))
}

@MainActor
@Test func playAndStopRestoreActiveTrackAfterAudition() throws {
    let audio = FakeAudio()
    let model = try Sandbox().makeModel(audio: audio)
    let t = model.newTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    model.setActive(t.id)
    let audition = Track(name: "Chord Finder", createdAt: Date(), tempo: 100, key: t.key, bars: 2, parts: [])
    model.audition(audition)
    #expect(audio.tracksSet.last == audition)
    #expect(model.isPlaying && audio.isPlaying)
    model.stop()
    #expect(!model.isPlaying && !audio.isPlaying)
    #expect(audio.tracksSet.last?.id == t.id, "stopping puts the active track back")
    model.play()
    #expect(model.isPlaying && audio.isPlaying)
}

@MainActor
@Test func metronomeAddsTemporaryRimPartToAudioOnly() throws {
    let audio = FakeAudio()
    let model = try Sandbox().makeModel(audio: audio)
    let t = model.newTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    model.setActive(t.id)
    model.metronome = true
    #expect(audio.tracksSet.last?.part(.texture) != nil)
    #expect(model.activeTrack?.part(.texture) == nil, "the saved track is unchanged")
    model.metronome = false
    #expect(audio.tracksSet.last?.part(.texture) == nil)
}

@MainActor
@Test func startTrackCreatesAndActivates() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    let t = model.startTrack(name: "My first beat", tempo: 150, key: try Key(parsing: "C minor"))
    #expect(model.activeTrack?.id == t.id)
    #expect(model.activeTrack?.tempo == 150)
    #expect(ProgressStore(fileURL: sandbox.progressURL).load().activeTrackID == t.id)
}

@MainActor
@Test func genreFitHints() {
    #expect(TrackSetupView.genreFit(tempo: 140) == "Fits: trap, cloud")
    #expect(TrackSetupView.genreFit(tempo: 165) == "Fits: trap")
    #expect(TrackSetupView.genreFit(tempo: 70) == "Fits: cloud")
    #expect(TrackSetupView.genreFit(tempo: 100) == "Between the usual trap and cloud tempos")
}
