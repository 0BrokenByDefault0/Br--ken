import Foundation
import Testing
@testable import MusicCore

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sampleTrack(name: String = "Test", createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws -> Track {
    let melody = Part(role: .melody, instrument: .bell, content: .notes(try Notation.melody("A4:4 C5:4")))
    let chords = Part(role: .chords, instrument: .pad, content: .chords(try Notation.chords("Am:16 F:16")))
    let drums = Part(role: .drums, instrument: .trapKit,
                     content: .drums(DrumPattern(lanes: [.kick: try Notation.drumLane("x...x...x...x...")])))
    return Track(name: name, createdAt: createdAt, tempo: 140, key: try Key(parsing: "A minor"), bars: 4,
                 parts: [melody, chords, drums])
}

private func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.sortedKeys]
    return e
}

@Test func trackRoundTrip() throws {
    var t = try sampleTrack()
    t.completedStages = ["a", "b"]
    let data = try encoder().encode(t)
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    let back = try d.decode(Track.self, from: data)
    #expect(back == t)
    #expect(back.parts.count == 3)
    if case .notes = back.part(.melody)?.content {} else { Issue.record("melody not notes") }
    if case .chords = back.part(.chords)?.content {} else { Issue.record("chords not chords") }
    if case .drums = back.part(.drums)?.content {} else { Issue.record("drums not drums") }
}

@Test func loadAllSkipsCorruptAndRenames() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TrackStore(directory: dir)
    try store.save(try sampleTrack(name: "one", createdAt: Date(timeIntervalSince1970: 1_700_000_000)))
    try store.save(try sampleTrack(name: "two", createdAt: Date(timeIntervalSince1970: 1_700_001_000)))
    let bad = dir.appendingPathComponent("bad.json")
    try Data("\"garbage\"".utf8).write(to: bad)
    let report = store.loadAll()
    #expect(report.tracks.count == 2)
    #expect(report.tracks.map(\.name) == ["two", "one"])
    #expect(report.skipped == [bad])
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bad.json.corrupt").path))
    #expect(!FileManager.default.fileExists(atPath: bad.path))
}

@Test func newerVersionSkippedNotRenamed() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TrackStore(directory: dir)
    var t = try sampleTrack()
    t.version = 99
    try store.save(t)
    let file = dir.appendingPathComponent("\(t.id.uuidString).json")
    let report = store.loadAll()
    #expect(report.tracks.isEmpty)
    #expect(report.skipped == [file])
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func deleteRemovesFile() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = TrackStore(directory: dir)
    let t = try sampleTrack()
    try store.save(t)
    let file = dir.appendingPathComponent("\(t.id.uuidString).json")
    #expect(FileManager.default.fileExists(atPath: file.path))
    try store.delete(id: t.id)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func corruptProgressResetsToEmpty() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("progress.json")
    try Data("not json".utf8).write(to: file)
    let store = ProgressStore(fileURL: file)
    #expect(store.load() == .empty)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("progress.json.corrupt").path))
}

@Test func progressRoundTripAndMissing() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ProgressStore(fileURL: dir.appendingPathComponent("progress.json"))
    #expect(store.load() == .empty)
    var p = Progress.empty
    p.completedLessons = ["l1"]
    p.currentLessonID = "l2"
    p.activeTrackID = UUID()
    try store.save(p)
    #expect(store.load() == p)
}

@Test func setPartReplacesSameRole() throws {
    var t = try sampleTrack()
    let replacement = Part(role: .melody, instrument: .pluck, content: .notes(try Notation.melody("C4:2")))
    t.setPart(replacement)
    #expect(t.parts.count == 3)
    #expect(t.part(.melody)?.instrument == .pluck)
    let bass = Part(role: .bass808, instrument: .eight08, content: .notes(try Notation.melody("A1:4")))
    t.setPart(bass)
    #expect(t.parts.count == 4)
    #expect(t.part(.bass808) != nil)
}
