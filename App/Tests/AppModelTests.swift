import Testing
import Foundation
import AVFoundation
import MusicCore
import SoundEngine
@testable import Broken

@MainActor
private final class FakeAudio: AudioPlaying {
    var tracksSet: [Track] = []
    var playheadTick = 0
    var isPlaying = false
    var latencyTicks = 0
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
    func makeModel(audio: (any AudioPlaying)? = nil) throws -> AppModel {
        AppModel(content: try ContentLibrary(directory: contentDir),
                 trackStore: TrackStore(directory: tracksDir),
                 progressStore: ProgressStore(fileURL: progressURL),
                 audio: audio ?? FakeAudio() as any AudioPlaying)
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
@Test func workingTrackTransposesStarterIntoOwnersKey() throws {
    let model = try Sandbox().makeModel()
    let cMinor = try Key(parsing: "C minor")
    let mine = model.newTrack(name: "Mine", tempo: 150, key: cMinor)
    model.setActive(mine.id)
    let aMinorStarter = Clip(tempo: 92, key: "A minor", bars: 2, parts: [
        ClipPart(role: .melody, instrument: .bell, melody: "E4:4 G4:4 A4:4 r:4"),
    ])
    let working = model.workingTrack(for: chordFinderStep(uses: [.melody], starter: aMinorStarter),
                                     lessonID: "harmony.find")
    let pitches = notes(working, .melody).map(\.pitch)
    #expect(pitches == [67, 70, 72], "A minor starter shifted up 3 semitones")
    #expect(pitches.allSatisfy { cMinor.contains(PitchClass($0)) })
    #expect(CheckRunner.run([.inKey(role: .melody)], on: working).allSatisfy { $0.passed })
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
    #expect(audio.tracksSet.last?.name == "Chord Finder")
    #expect(audio.tracksSet.last?.tempo == 140, "an audition plays at the active track's tempo, not a stale one")
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

@MainActor
@Test func previewDoesNotWriteToDiskCommitDoes() throws {
    let sandbox = try Sandbox()
    let audio = FakeAudio()
    let model = try sandbox.makeModel(audio: audio)
    let t = model.startTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    model.previewActiveTrack { $0.tempo = 120 }
    model.previewActiveTrack { $0.tempo = 100 }
    #expect(model.activeTrack?.tempo == 100, "the change is live in memory")
    #expect(audio.tracksSet.last?.tempo == 100, "and heard")
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first { $0.id == t.id }?.tempo == 140,
            "but not saved yet")
    model.commitActiveTrack()
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first { $0.id == t.id }?.tempo == 100)
}

@MainActor
@Test func previewPartEditThenCommit() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    model.startTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    model.editActivePart(.melody, instrument: .bell, empty: .notes(NoteSequence(notes: [])), persist: false) {
        $0.sound.volume = 0.3
    }
    #expect(model.activeTrack?.part(.melody)?.sound.volume == 0.3)
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first?.part(.melody) == nil)
    model.commitActiveTrack()
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first?.part(.melody)?.sound.volume == 0.3)
}

@MainActor
@Test func failedDeleteKeepsTrackAndReportsError() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    let t = model.startTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    let fm = FileManager.default
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sandbox.tracksDir.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sandbox.tracksDir.path) }
    model.deleteTrack(id: t.id)
    #expect(model.tracks.contains { $0.id == t.id }, "still on disk, so still listed")
    #expect(model.activeTrack?.id == t.id)
    #expect(model.lastError != nil)
    model.dismissError()
    #expect(model.lastError == nil)
}

@MainActor
@Test func playWithoutActiveTrackIsNoOpEvenAfterDelete() throws {
    let audio = FakeAudio()
    let model = try Sandbox().makeModel(audio: audio)
    model.play()
    #expect(!model.isPlaying && !audio.isPlaying)
    let t = model.startTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    model.play()
    #expect(model.isPlaying)
    model.deleteTrack(id: t.id)
    #expect(!model.isPlaying && !audio.isPlaying)
    model.play()
    #expect(!model.isPlaying && !audio.isPlaying, "a deleted track is never replayed")
}

@MainActor
@Test func defaultTrackNamesAreUnique() throws {
    let model = try Sandbox().makeModel()
    #expect(model.defaultTrackName == "My first beat")
    let first = model.newTrack(name: model.defaultTrackName, tempo: 140, key: try Key(parsing: "A minor"))
    #expect(model.defaultTrackName == "Beat 2")
    _ = model.newTrack(name: model.defaultTrackName, tempo: 140, key: try Key(parsing: "A minor"))
    #expect(model.defaultTrackName == "Beat 3")
    model.deleteTrack(id: first.id)
    #expect(model.defaultTrackName == "Beat 3" || model.defaultTrackName == "Beat 4")
    let names = Set(model.tracks.map(\.name))
    #expect(!names.contains(model.defaultTrackName))
}

@MainActor
@Test func switchingTracksSavesPendingPreview() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    let a = model.startTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    let b = model.newTrack(name: "B", tempo: 120, key: try Key(parsing: "A minor"))
    model.previewActiveTrack { $0.tempo = 99 }
    #expect(model.hasUncommittedPreview)
    model.setActive(b.id)
    #expect(!model.hasUncommittedPreview)
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first { $0.id == a.id }?.tempo == 99)
    #expect(model.activeTrack?.id == b.id)
}

@MainActor
@Test func flushPendingPreviewPersistsOnceAndIsNoOpOtherwise() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    let t = model.startTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    model.flushPendingPreview()  // nothing pending
    model.previewActiveTrack { $0.tempo = 101 }
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first?.tempo == 140)
    model.flushPendingPreview()  // what a tab change or leaving the foreground does
    #expect(!model.hasUncommittedPreview)
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first { $0.id == t.id }?.tempo == 101)
}

@MainActor
@Test func normalEditClearsPendingPreviewFlag() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "A", tempo: 140, key: try Key(parsing: "A minor"))
    model.previewActiveTrack { $0.tempo = 101 }
    model.editActivePart(.drums, instrument: .trapKit, empty: .drums(DrumPattern(lanes: [:]))) { _ in }
    #expect(!model.hasUncommittedPreview, "a saving edit writes the whole track, preview included")
}

// MARK: - Lesson player

private func melodyTask(checks: [TaskCheck] = [.noteCount(role: .melody, min: 3, max: nil)],
                        hints: [String] = []) -> LessonStep {
    .task(title: "Write a melody", prompt: "p", tool: .melodyEditor, targetRole: .melody, uses: [],
          starter: nil, checks: checks, hints: hints)
}

private func threeNotes() throws -> Part {
    Part(role: .melody, instrument: .bell, content: .notes(try Notation.melody("A4:4 C5:4 E5:4")))
}

@MainActor
@Test func taskChecksRunAgainstWorkingTrack() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    let task = TaskStepModel(step: melodyTask(), lessonID: "harmony.find", app: model)
    #expect(task.working.part(.melody) != nil, "the target role is created empty")
    #expect(task.runChecks().map(\.passed) == [false])

    let melody = try threeNotes()
    task.edit { $0.setPart(melody) }
    let results = task.runChecks()
    #expect(results.map(\.passed) == [true])
    #expect(task.allPassed)
    #expect(model.activeTrack?.part(.melody) == nil, "edits stay on the working track until kept")
}

@MainActor
@Test func continueAnywayAvailableWhenFailing() throws {
    let model = try Sandbox().makeModel()
    let task = TaskStepModel(step: melodyTask(), lessonID: "harmony.find", app: model)
    #expect(task.canContinue)
    #expect(!task.allPassed, "no results yet")
    #expect(task.continueLabel == "Continue anyway")
    _ = task.runChecks()
    #expect(task.canContinue == true)
    #expect(task.allPassed == false)
    #expect(task.continueLabel == "Continue anyway")
    task.edit { $0.setPart(try! threeNotes()) }
    _ = task.runChecks()
    #expect(task.allPassed)
    #expect(task.continueLabel == "Continue")
    task.edit { $0.setPart(Part(role: .melody, instrument: .bell, content: .notes(NoteSequence(notes: [])))) }
    #expect(!task.allPassed, "an edit clears stale results")
}

@MainActor
@Test func taskWithoutChecksNeverPasses() throws {
    let model = try Sandbox().makeModel()
    let task = TaskStepModel(step: melodyTask(checks: []), lessonID: "harmony.find", app: model)
    #expect(task.runChecks().isEmpty)
    #expect(!task.allPassed)
    #expect(task.canContinue)
}

@MainActor
@Test func hintsAdvanceAndStop() throws {
    let model = try Sandbox().makeModel()
    let task = TaskStepModel(step: melodyTask(hints: ["one", "two"]), lessonID: "harmony.find", app: model)
    #expect(task.hintIndex == 0)
    #expect(task.nextHint() == "one")
    #expect(task.hintIndex == 1)
    #expect(task.nextHint() == "two")
    #expect(task.hintIndex == 2)
    #expect(task.nextHint() == nil)
    #expect(task.hintIndex == 2)
    #expect(task.shownHints == ["one", "two"])
}

@MainActor
@Test func taskWorkingTrackUnmutesParts() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    model.updateActiveTrack { $0.setPart(Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: [:])), muted: true)) }
    let task = TaskStepModel(step: melodyTask(), lessonID: "harmony.find", app: model)
    #expect(task.working.part(.drums)?.muted == false, "a Journey mute must not silence a lesson")
    #expect(model.activeTrack?.part(.drums)?.muted == true, "the saved track keeps its mute")
}

@MainActor
@Test func taskEditWhilePlayingSwapsAuditionWithoutTouchingActiveTrack() throws {
    let audio = FakeAudio()
    let model = try Sandbox().makeModel(audio: audio)
    let mine = model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    let task = TaskStepModel(step: melodyTask(), lessonID: "harmony.find", app: model)
    task.play()
    #expect(model.isPlaying && audio.isPlaying)
    let melody = try threeNotes()
    task.edit { $0.setPart(melody) }
    #expect(audio.tracksSet.last?.part(.melody)?.content == melody.content, "the edit is heard right away")
    #expect(audio.isPlaying)
    model.stop()
    #expect(audio.tracksSet.last?.id == mine.id)
    #expect(audio.tracksSet.last?.part(.melody) == nil, "stopping puts the saved track back")
}

@MainActor
@Test func auditionCanKeepItsOwnTempo() throws {
    let audio = FakeAudio()
    let model = try Sandbox().makeModel(audio: audio)
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    let example = Track(name: "Example", createdAt: Date(), tempo: 92, key: try Key(parsing: "D minor"), bars: 2, parts: [])
    model.audition(example, atTrackTempo: false)
    #expect(audio.tracksSet.last?.tempo == 92)
    model.stop()
    model.updateAudition(example)
    #expect(audio.tracksSet.last?.name == "Mine", "no audition is swapped in while stopped")
}

@MainActor
@Test func listenExampleTrackIsUnmutedExceptToggledParts() throws {
    let clip = Clip(tempo: 92, key: "D minor", bars: 2, parts: [
        ClipPart(role: .melody, instrument: .bell, melody: "D4:4 F4:4"),
        ClipPart(role: .chords, instrument: .pad, chords: "Dm:16 Bb:16"),
    ])
    let base = try ListenPlayback.track(for: clip)
    let all = ListenPlayback.track(base, mutedParts: [])
    #expect(all.parts.allSatisfy { !$0.muted })
    #expect(all.tempo == 92)
    let noChords = ListenPlayback.track(base, mutedParts: [1])
    #expect(noChords.part(.chords)?.muted == true)
    #expect(noChords.part(.melody)?.muted == false)
    #expect(noChords.parts.map(\.id) == base.parts.map(\.id), "the cached example keeps its parts")
    #expect(ListenPlayback.partLabels(base) == ["Melody", "Chords"])
}

@MainActor
@Test func listenSameRolePartsMuteIndependentlyWithDistinctLabels() throws {
    let clip = Clip(tempo: 92, key: "D minor", bars: 2, parts: [
        ClipPart(role: .chords, instrument: .pad, chords: "Dm:32"),
        ClipPart(role: .chords, instrument: .keys, chords: "Bb:32"),
        ClipPart(role: .chords, instrument: .pluck, chords: "F:32"),
        ClipPart(role: .bass808, instrument: .eight08, melody: "D2:32"),
    ])
    let base = try ListenPlayback.track(for: clip)
    let middleMuted = ListenPlayback.track(base, mutedParts: [1])
    #expect(middleMuted.parts.map(\.muted) == [false, true, false, false], "only the tapped part mutes")
    #expect(ListenPlayback.partLabels(base) == ["Chords 1", "Chords 2", "Chords 3", "808"])
}

@MainActor
@Test func keepSourceIsMostRecentTaskForTheRoles() {
    let melody = LessonStep.task(title: "m", prompt: "p", tool: .melodyEditor, targetRole: .melody, uses: [],
                                 starter: nil, checks: [], hints: [])
    let chords = LessonStep.task(title: "c", prompt: "p", tool: .chordPads, targetRole: .chords, uses: [.melody],
                                 starter: nil, checks: [], hints: [])
    let idea = LessonStep.idea(title: "i", body: "b", deeper: nil)
    let steps: [LessonStep] = [idea, melody, chords, .keep(message: "k", roles: [.melody]), melody,
                               .keep(message: "k", roles: [.drums])]
    #expect(LessonPlayerModel.keepSourceIndex(in: steps, before: 3, roles: [.melody]) == 1,
            "the latest task targeting a kept role wins over a later task for another role")
    #expect(LessonPlayerModel.keepSourceIndex(in: steps, before: 3, roles: [.chords, .melody]) == 2)
    #expect(LessonPlayerModel.keepSourceIndex(in: steps, before: 5, roles: [.drums]) == 4,
            "with no matching task, the most recent task")
    #expect(LessonPlayerModel.keepSourceIndex(in: steps, before: 1, roles: [.melody]) == nil)
}

@MainActor
@Test func keepStepSavesFromItsSourceTaskAndAsksOnlyForExistingRoles() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    model.updateActiveTrack { $0.setPart(Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: [:])))) }
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        melodyTask(), .keep(message: "k", roles: [.melody, .drums]),
    ])
    let player = LessonPlayerModel(lesson: lesson, app: model)
    #expect(player.conflictingRoles(forKeepAt: 1).isEmpty, "an unchanged part replaces nothing")
    let melody = try threeNotes()
    let kick = DrumPattern(lanes: [.kick: [DrumHit(tick: 0, velocity: 1)]])
    player.taskModel(at: 0).edit {
        $0.setPart(melody)
        $0.setPart(Part(role: .drums, instrument: .trapKit, content: .drums(kick)))
    }
    #expect(player.conflictingRoles(forKeepAt: 1) == [.drums], "only roles Your Track already has are asked about")
    player.keep(at: 1, roles: [.melody])  // "Keep mine" for the drums
    #expect(model.activeTrack?.part(.melody)?.content == melody.content)
    #expect(model.activeTrack?.part(.drums)?.content == .drums(DrumPattern(lanes: [:])))
    #expect(model.progress.completedLessons.contains("harmony.find"))
    #expect(player.kept.contains(1))
}

@MainActor
@Test func trackSetupKeepAppliesTempoAndKey() throws {
    let setup = LessonStep.task(title: "Set up", prompt: "p", tool: .trackSetup, targetRole: nil, uses: [],
                                starter: nil, checks: [.tempoInRange(min: 130, max: 170)], hints: [])
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        setup, .keep(message: "k", roles: []),
    ])
    let cMinor = try Key(parsing: "C minor")

    // No track yet: the keep creates one with the chosen name, tempo, and key.
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    let player = LessonPlayerModel(lesson: lesson, app: model)
    player.taskModel(at: 0).edit { $0.name = "Night drive"; $0.tempo = 150; $0.key = cMinor }
    #expect(player.taskModel(at: 0).runChecks().map(\.passed) == [true])
    player.keep(at: 1, roles: [])
    let created = try #require(model.activeTrack)
    #expect(created.name == "Night drive")
    #expect(created.tempo == 150)
    #expect(created.key == cMinor)
    #expect(TrackStore(directory: sandbox.tracksDir).loadAll().tracks.first?.tempo == 150)

    // An active track already exists: its tempo and key change, its parts stay.
    let other = try Sandbox().makeModel()
    let mine = other.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    other.updateActiveTrack { $0.setPart(try! threeNotes()) }
    let player2 = LessonPlayerModel(lesson: lesson, app: other)
    player2.taskModel(at: 0).edit { $0.name = "Renamed"; $0.tempo = 160; $0.key = cMinor }
    player2.keep(at: 1, roles: [])
    #expect(other.activeTrack?.id == mine.id)
    #expect(other.activeTrack?.name == "Mine", "a setup keep never renames Your Track")
    #expect(other.tracks.count == 1)
    #expect(other.activeTrack?.tempo == 160)
    #expect(other.activeTrack?.key == cMinor)
    #expect(other.activeTrack?.part(.melody) != nil)
}

@MainActor
@Test func finishingMarksComplete() throws {
    let sandbox = try Sandbox()
    let model = try sandbox.makeModel()
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        .idea(title: "i", body: "b", deeper: nil), .koala(body: "k"),
    ])
    let player = LessonPlayerModel(lesson: lesson, app: model)
    player.next()
    #expect(player.index == 1)
    #expect(player.isLast)
    #expect(!model.progress.completedLessons.contains("harmony.find"))
    player.next()  // "Finish lesson"
    #expect(player.finished)
    #expect(model.progress.completedLessons.contains("harmony.find"))
    #expect(ProgressStore(fileURL: sandbox.progressURL).load().completedLessons.contains("harmony.find"))
}

@MainActor
@Test func keepSkipsEmptyPartsAndLeavesSavedPartIntact() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        melodyTask(), .keep(message: "k", roles: [.melody]),
    ])

    // Task skipped: the empty target part is not saved.
    let skipped = LessonPlayerModel(lesson: lesson, app: model)
    #expect(skipped.emptyRoles(forKeepAt: 1) == [.melody])
    #expect(skipped.rolesToSave(atKeep: 1).isEmpty)
    skipped.saveKeep(at: 1)
    #expect(model.activeTrack?.part(.melody) == nil, "no empty part is added")
    #expect(skipped.saved[1] == [])
    #expect(model.progress.completedLessons.contains("harmony.find"), "the lesson still completes")

    // A saved melody exists and the task's melody was cleared: the saved melody stays.
    let melody = try threeNotes()
    model.updateActiveTrack { $0.setPart(melody) }
    let cleared = LessonPlayerModel(lesson: lesson, app: model)
    cleared.taskModel(at: 0).editTarget { $0.content = .notes(NoteSequence(notes: [])) }
    #expect(cleared.emptyRoles(forKeepAt: 1) == [.melody])
    #expect(cleared.conflictingRoles(forKeepAt: 1).isEmpty, "an empty part never asks to replace")
    cleared.keep(at: 1, roles: [.melody])  // even when asked directly, AppModel.keep skips empty parts
    #expect(model.activeTrack?.part(.melody)?.content == melody.content)
}

@MainActor
@Test func keepWithoutEarlierTaskFallsBackToYourTrack() throws {
    let model = try Sandbox().makeModel()
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        .idea(title: "i", body: "b", deeper: nil), .keep(message: "k", roles: [.melody]),
    ])
    let none = LessonPlayerModel(lesson: lesson, app: model)
    #expect(none.emptyRoles(forKeepAt: 1) == [.melody])
    none.saveKeep(at: 1)
    let created = try #require(model.activeTrack, "a keep with no track creates one")
    #expect(created.parts.isEmpty)
    #expect(model.progress.completedLessons.contains("harmony.find"))

    let melody = try threeNotes()
    model.updateActiveTrack { $0.setPart(melody) }
    let again = LessonPlayerModel(lesson: lesson, app: model)
    #expect(again.emptyRoles(forKeepAt: 1).isEmpty)
    #expect(again.conflictingRoles(forKeepAt: 1).isEmpty)
    again.saveKeep(at: 1)
    #expect(model.activeTrack?.part(.melody) == melody, "Your Track is saved back unchanged")
    #expect(model.tracks.count == 1)
}

@MainActor
@Test func conflictsIgnoreMuteAndReplaceKeepsSavedMute() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    var melody = try threeNotes()
    melody.muted = true
    model.updateActiveTrack { $0.setPart(melody) }
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        melodyTask(), .keep(message: "k", roles: [.melody]),
    ])
    let player = LessonPlayerModel(lesson: lesson, app: model)
    #expect(player.taskModel(at: 0).working.part(.melody)?.muted == false)
    #expect(player.conflictingRoles(forKeepAt: 1).isEmpty, "only the mute differs: nothing to replace")

    let newNotes = try Notation.melody("E5:4 D5:4 C5:4 A4:4")
    player.taskModel(at: 0).editTarget { $0.content = .notes(newNotes) }
    #expect(player.conflictingRoles(forKeepAt: 1) == [.melody])
    player.setReplace(true, role: .melody, atKeep: 1)
    player.saveKeep(at: 1)
    #expect(model.activeTrack?.part(.melody)?.content == .notes(newNotes))
    #expect(model.activeTrack?.part(.melody)?.muted == true, "Replace keeps the saved part's mute")
}

@MainActor
@Test func replaceChoicesDecideSavedRoles() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    model.updateActiveTrack {
        $0.setPart(try! threeNotes())
        $0.setPart(Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: [.kick: [DrumHit(tick: 0, velocity: 1)]]))))
    }
    let both = LessonStep.task(title: "t", prompt: "p", tool: .drumGrid, targetRole: .drums, uses: [],
                               starter: nil, checks: [], hints: [])
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        both, .keep(message: "k", roles: [.melody, .drums, .chords]),
    ])
    let player = LessonPlayerModel(lesson: lesson, app: model)
    player.taskModel(at: 0).edit {
        $0.setPart(Part(role: .melody, instrument: .bell, content: .notes(try! Notation.melody("C5:4"))))
        $0.setPart(Part(role: .drums, instrument: .trapKit, content: .drums(DrumPattern(lanes: [.snare: [DrumHit(tick: 96, velocity: 1)]]))))
    }
    #expect(player.conflictingRoles(forKeepAt: 1) == [.melody, .drums])
    #expect(player.emptyRoles(forKeepAt: 1) == [.chords])
    #expect(player.rolesToSave(atKeep: 1) == [.drums],
            "the task's own edit of the saved drums defaults to Replace; the melody (not its part) to Keep mine")
    player.setReplace(false, role: .drums, atKeep: 1)
    #expect(player.rolesToSave(atKeep: 1).isEmpty)
    player.setReplace(true, role: .drums, atKeep: 1)
    #expect(player.replaces(.drums, atKeep: 1))
    #expect(player.rolesToSave(atKeep: 1) == [.drums])
    player.setReplace(true, role: .melody, atKeep: 1)
    player.setReplace(false, role: .drums, atKeep: 1)
    #expect(player.rolesToSave(atKeep: 1) == [.melody])
    player.saveKeep(at: 1)
    #expect(player.saved[1] == [.melody])
    #expect(notes(try #require(model.activeTrack), .melody).map(\.pitch) == [72])
    #expect(model.activeTrack?.part(.drums)?.content == .drums(DrumPattern(lanes: [.kick: [DrumHit(tick: 0, velocity: 1)]])))
}

@MainActor
@Test func taskToolModelsAreBuiltOnce() throws {
    let model = try Sandbox().makeModel()
    let task = TaskStepModel(step: melodyTask(), lessonID: "harmony.find", app: model)
    let melody1 = task.melodyTool, melody2 = task.melodyTool
    let grid1 = task.drumGrid, grid2 = task.drumGrid
    let finder1 = task.chordFinder, finder2 = task.chordFinder
    #expect(melody1 === melody2)
    #expect(grid1 === grid2)
    #expect(finder1 === finder2)
    task.melodyTool.roll.toggle(step: 0, pitch: 69)
    #expect(notes(task.working, .melody).map(\.pitch) == [69], "roll edits write the working track")
}

@MainActor
@Test func leavingTaskWhileRecordingKeepsTheTake() throws {
    let audio = FakeAudio()
    let model = try Sandbox().makeModel(audio: audio)
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        melodyTask(), .idea(title: "i", body: "b", deeper: nil),
    ])
    let player = LessonPlayerModel(lesson: lesson, app: model)
    let task = player.taskModel(at: 0)
    let tool = task.melodyTool
    tool.toggleRecording()
    #expect(tool.isRecording)
    #expect(model.isPlaying, "recording starts the loop")
    audio.playheadTick = 0
    tool.keyEvent(pitch: 69, on: true)
    audio.playheadTick = 96
    tool.keyEvent(pitch: 69, on: false)
    player.next()
    #expect(!tool.isRecording)
    #expect(!model.isPlaying)
    #expect(notes(task.working, .melody).map(\.pitch) == [69], "the take is written before leaving")
}

@MainActor
@Test func restartResetsLessonState() throws {
    let model = try Sandbox().makeModel()
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        melodyTask(hints: ["one"]), .keep(message: "k", roles: [.melody]),
    ])
    let player = LessonPlayerModel(lesson: lesson, app: model)
    let first = player.taskModel(at: 0)
    _ = first.nextHint()
    player.setReplace(true, role: .melody, atKeep: 1)
    player.saveKeep(at: 1)
    player.next()
    player.next()
    #expect(player.finished)
    player.restart()
    #expect(!player.finished)
    #expect(player.index == 0)
    #expect(player.kept.isEmpty)
    #expect(!player.replaces(.melody, atKeep: 1))
    let fresh = player.taskModel(at: 0)
    #expect(fresh !== first, "fresh task models")
    #expect(fresh.hintIndex == 0)
}

// MARK: - Final fix wave

private func chordsTask(tool: ToolKind, uses: [PartRole]) -> LessonStep {
    .task(title: "Chords", prompt: "p", tool: tool, targetRole: .chords, uses: uses, starter: starter,
          checks: [], hints: [])
}

private func chordsLesson(_ id: String, tool: ToolKind, uses: [PartRole]) -> Lesson {
    Lesson(id: id, stage: "harmony", title: "t", summary: "s", steps: [
        chordsTask(tool: tool, uses: uses), .keep(message: "k", roles: [.chords]),
    ])
}

@MainActor
@Test func keepDefaultsToReplaceForTheOwnersEditOfTheirSavedPart() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "D minor"))
    let found = try Notation.chords("Dm:16 Bb:16")
    let first = LessonPlayerModel(lesson: chordsLesson("harmony.chords-from-melody", tool: .chordFinder, uses: [.melody]),
                                  app: model)
    first.taskModel(at: 0).editTarget { $0.content = .chords(found) }
    first.saveKeep(at: 1)
    #expect(model.activeTrack?.part(.chords)?.content == .chords(found))

    let second = LessonPlayerModel(lesson: chordsLesson("harmony.sound-expensive", tool: .chordPads, uses: [.melody, .chords]),
                                   app: model)
    #expect(second.taskModel(at: 0).working.part(.chords)?.content == .chords(found), "the task starts from the saved chords")
    let richer = try Notation.chords("Dm7:16 Bbmaj7:16")
    second.taskModel(at: 0).editTarget { $0.content = .chords(richer) }
    #expect(second.conflictingRoles(forKeepAt: 1) == [.chords])
    #expect(second.replaces(.chords, atKeep: 1), "an edit of the owner's own saved part defaults to Replace")
    #expect(second.rolesToSave(atKeep: 1) == [.chords])
    second.saveKeep(at: 1)
    #expect(model.activeTrack?.part(.chords)?.content == .chords(richer))
    #expect(second.saved[1] == [.chords])

    // Back to the task for another edit: the saved part is still the owner's own work.
    let again = try Notation.chords("Dm9:16 Bbmaj7:16")
    second.taskModel(at: 0).editTarget { $0.content = .chords(again) }
    #expect(second.replaces(.chords, atKeep: 1))
    second.saveKeep(at: 1)
    #expect(model.activeTrack?.part(.chords)?.content == .chords(again))
}

@MainActor
@Test func keepDefaultsToKeepMineWhenTheSavedPartIsDifferent() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "D minor"))
    let mine = try Notation.chords("Dm:16 Bb:16")
    model.updateActiveTrack { $0.setPart(Part(role: .chords, instrument: .pad, content: .chords(mine))) }
    let player = LessonPlayerModel(lesson: chordsLesson("harmony.sound-expensive", tool: .chordPads, uses: [.melody, .chords]),
                                   app: model)
    let task = player.taskModel(at: 0)
    // Your Track's chords change elsewhere (the Chords tab) after the task started.
    let elsewhere = try Notation.chords("Gm:16 F:16")
    model.updateActiveTrack { $0.setPart(Part(role: .chords, instrument: .pad, content: .chords(elsewhere))) }
    task.editTarget { $0.content = .chords(try! Notation.chords("Dm7:16 Bbmaj7:16")) }
    #expect(player.conflictingRoles(forKeepAt: 1) == [.chords])
    #expect(!player.replaces(.chords, atKeep: 1), "a saved part that isn't the task's starting part defaults to Keep mine")
    #expect(player.rolesToSave(atKeep: 1).isEmpty)
    player.saveKeep(at: 1)
    #expect(model.activeTrack?.part(.chords)?.content == .chords(elsewhere))
}

@MainActor
@Test func changingTheChoiceAfterSavingThenSavingAgainAppliesIt() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "D minor"))
    let player = LessonPlayerModel(lesson: chordsLesson("harmony.sound-expensive", tool: .chordPads, uses: [.melody, .chords]),
                                   app: model)
    let task = player.taskModel(at: 0)
    let elsewhere = try Notation.chords("Gm:16 F:16")
    model.updateActiveTrack { $0.setPart(Part(role: .chords, instrument: .pad, content: .chords(elsewhere))) }
    let mine = try Notation.chords("Dm7:16 Bbmaj7:16")
    task.editTarget { $0.content = .chords(mine) }
    player.saveKeep(at: 1)  // default Keep mine
    #expect(player.saved[1] == [])
    #expect(model.activeTrack?.part(.chords)?.content == .chords(elsewhere))
    #expect(player.conflictingRoles(forKeepAt: 1) == [.chords], "the choice is still offered after saving")
    player.setReplace(true, role: .chords, atKeep: 1)
    player.saveKeep(at: 1)  // "Save again"
    #expect(player.saved[1] == [.chords])
    #expect(model.activeTrack?.part(.chords)?.content == .chords(mine))
}

private func hasClick(_ track: Track?) -> Bool {
    track?.parts.contains { part in
        if part.role == .texture, case .drums(let p) = part.content { return p.lanes[.rim] != nil }
        return false
    } ?? false
}

@MainActor
@Test func metronomeIsOnlyMixedIntoTheActiveTrack() throws {
    let audio = FakeAudio()
    let model = try Sandbox().makeModel(audio: audio)
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    model.metronome = true
    let example = Track(name: "Example", createdAt: Date(), tempo: 92, key: try Key(parsing: "D minor"), bars: 2, parts: [])
    model.audition(example, atTrackTempo: false)
    #expect(audio.tracksSet.last?.name == "Example")
    #expect(!hasClick(audio.tracksSet.last), "a lesson loop or example plays without the click")
    model.updateAudition(example)
    #expect(!hasClick(audio.tracksSet.last))
    model.play()
    #expect(audio.tracksSet.last?.name == "Mine")
    #expect(hasClick(audio.tracksSet.last), "the active track plays with the click")
}

@MainActor
@Test func keepSetupTransposesPartsIntoTheNewKey() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    let kick = DrumPattern(lanes: [.kick: [DrumHit(tick: 0, velocity: 1)]])
    model.updateActiveTrack {
        $0.setPart(try! threeNotes())  // A4 C5 E5
        $0.setPart(Part(role: .chords, instrument: .pad, content: .chords(try! Notation.chords("Am:16 F:16"))))
        $0.setPart(Part(role: .drums, instrument: .trapKit, content: .drums(kick)))
    }
    let setup = LessonStep.task(title: "Set up", prompt: "p", tool: .trackSetup, targetRole: nil, uses: [],
                                starter: nil, checks: [], hints: [])
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        setup, .keep(message: "k", roles: []),
    ])
    let player = LessonPlayerModel(lesson: lesson, app: model)
    let cMinor = try Key(parsing: "C minor")
    player.taskModel(at: 0).edit { $0.key = cMinor }
    player.keep(at: 1, roles: [])
    let track = try #require(model.activeTrack)
    #expect(track.key == cMinor)
    #expect(notes(track, .melody).map(\.pitch) == [72, 75, 79], "A minor to C minor moves up 3")
    #expect(track.part(.chords)?.content == .chords(try Notation.chords("Cm:16 Ab:16")))
    #expect(track.part(.drums)?.content == .drums(kick), "drums are untouched")

    // The same key again changes nothing.
    let player2 = LessonPlayerModel(lesson: lesson, app: model)
    player2.keep(at: 1, roles: [])
    #expect(notes(try #require(model.activeTrack), .melody).map(\.pitch) == [72, 75, 79])
}

@MainActor
@Test func toolTabsFollowTheKeyAfterKeepSetup() throws {
    let model = try Sandbox().makeModel()
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    let before = try #require(model.activeTrack)
    let setup = LessonStep.task(title: "Set up", prompt: "p", tool: .trackSetup, targetRole: nil, uses: [],
                                starter: nil, checks: [], hints: [])
    let lesson = Lesson(id: "harmony.find", stage: "harmony", title: "t", summary: "s", steps: [
        setup, .keep(message: "k", roles: []),
    ])
    let player = LessonPlayerModel(lesson: lesson, app: model)
    let cMinor = try Key(parsing: "C minor")
    player.taskModel(at: 0).edit { $0.key = cMinor }
    player.keep(at: 1, roles: [])
    let after = try #require(model.activeTrack)
    #expect(after.toolIdentity != before.toolIdentity, "the Chords and Melody tabs rebuild on a key change")
    #expect(ChordFinderModel(track: after).key == cMinor)
    #expect(MelodyToolModel(app: model, track: after).roll.key == cMinor)
}

@MainActor
@Test func glideModeOnlyFor808() throws {
    let model = try Sandbox().makeModel()
    func tool(_ instrument: InstrumentID) -> MelodyToolModel {
        MelodyToolModel(part: Part(role: .melody, instrument: instrument, content: .notes(NoteSequence(notes: []))),
                        bars: 2, key: AppModel.defaultKey, audio: model.audio, isPlaying: { false }, play: {}, write: { _ in })
    }
    #expect(tool(.eight08).showsGlide)
    #expect(!tool(.bell).showsGlide)
    #expect(!tool(.pad).showsGlide)
}

@MainActor
@Test func liveRecordingSubtractsOutputLatency() throws {
    let audio = FakeAudio()
    audio.latencyTicks = 16
    let model = try Sandbox().makeModel(audio: audio)
    model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
    let tool = MelodyToolModel(app: model, track: try #require(model.activeTrack))
    tool.toggleRecording()
    audio.playheadTick = 40  // heard at 24
    tool.keyEvent(pitch: 69, on: true)
    audio.playheadTick = 100  // heard at 84
    tool.keyEvent(pitch: 69, on: false)
    tool.toggleRecording()
    let recorded = notes(try #require(model.activeTrack), .melody)
    #expect(recorded.map(\.start) == [24])
    #expect(recorded.map(\.length) == [72])
}

private final class StubSession: AudioSessionControlling {
    func configure() throws {}
}

private final class StubEngine: AudioEngineControlling {
    var isRunning = false
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}

/// Renders one block so the renderer applies queued commands and publishes its play state.
private func renderBlock(_ renderer: Renderer) {
    var left = [Float](repeating: 0, count: 256), right = [Float](repeating: 0, count: 256)
    left.withUnsafeMutableBufferPointer { l in
        right.withUnsafeMutableBufferPointer { r in renderer.render(frames: 256, left: l.baseAddress!, right: r.baseAddress!) }
    }
}

@MainActor
@Test func mediaResetKeepsAppPlayStateTrue() throws {
    for playing in [true, false] {
        let player = AudioPlayer()
        var renderers: [Renderer] = []
        let center = NotificationCenter()
        let host = AudioHost(session: StubSession(), makeEngine: {
            let renderer = Renderer(sampleRate: 48_000)
            renderers.append(renderer)
            player.attach(renderer)
            return StubEngine()
        }, center: center)
        try host.start()
        let model = try Sandbox().makeModel(audio: player)
        model.startTrack(name: "Mine", tempo: 140, key: try Key(parsing: "A minor"))
        if playing { model.play() }
        renderBlock(renderers[0])
        #expect(player.isPlaying == playing)

        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        #expect(renderers.count == 2, "the reset built a new renderer")
        renderBlock(renderers[1])
        #expect(model.isPlaying == playing)
        #expect(player.isPlaying == model.isPlaying, "the rebuilt renderer resumes (or stays stopped) to match the app")
        withExtendedLifetime(host) {}
    }
}
