import Testing
import Foundation
@testable import MusicCore

private let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/sample-lesson.json")
private let repoContent = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Content")

private func stepType(_ s: LessonStep) -> String {
    switch s {
    case .idea: "idea"
    case .listen: "listen"
    case .task: "task"
    case .keep: "keep"
    case .koala: "koala"
    }
}

@Test func decodesSampleLesson() throws {
    let lesson = try JSONDecoder().decode(Lesson.self, from: Data(contentsOf: fixtureURL))
    #expect(lesson.id == "sample")
    #expect(lesson.steps.map(stepType) == ["idea", "listen", "task", "keep", "koala"])
    guard case .task(_, _, let tool, let target, let uses, let starter, let checks, let hints) = lesson.steps[2] else {
        Issue.record("step 3 is not a task"); return
    }
    #expect(tool == .drumGrid)
    #expect(target == .drums)
    #expect(uses == [.melody])
    #expect(starter != nil)
    #expect(checks.count == 2)
    #expect(hints.count == 1)
}

@Test func clipMakesTrack() throws {
    let clip = Clip(tempo: 92, key: "A minor", bars: 2, parts: [
        ClipPart(role: .melody, instrument: .bell, melody: "A4:4 C5:4"),
        ClipPart(role: .chords, instrument: .pad, chords: "Am:16 F:16"),
        ClipPart(role: .drums, instrument: .trapKit, drums: [.kick: "x...x...x...x..."]),
    ])
    let track = try clip.makeTrack(name: "T")
    #expect(track.name == "T")
    #expect(track.tempo == 92)
    #expect(track.bars == 2)
    #expect(track.key == (try Key(parsing: "A minor")))
    #expect(track.parts.map(\.role) == [.melody, .chords, .drums])
    guard case .notes(let seq) = track.part(.melody)!.content else { Issue.record("not notes"); return }
    #expect(seq.notes.count == 2)
    guard case .drums(let d) = track.part(.drums)!.content else { Issue.record("not drums"); return }
    #expect(d.lanes[.kick]?.count == 4)
}

@Test func clipPartNeedsExactlyOneContent() throws {
    let none = Clip(tempo: 90, key: "C major", bars: 1, parts: [ClipPart(role: .melody, instrument: .bell)])
    #expect(throws: ContentError.self) { try none.makeTrack(name: "x") }
    let two = Clip(tempo: 90, key: "C major", bars: 1,
                   parts: [ClipPart(role: .melody, instrument: .bell, melody: "C4:4", chords: "C:16")])
    #expect(throws: ContentError.self) { try two.makeTrack(name: "x") }
}

@Test func clipPartDecodesDrumObject() throws {
    let json = #"{"role":"drums","instrument":"trapKit","drums":{"kick":"x...","snare":"...."}}"#
    let part = try JSONDecoder().decode(ClipPart.self, from: Data(json.utf8))
    #expect(part.drums?.count == 2)
    #expect(part.drums?[.kick] == "x...")
}

// MARK: validator

private let goodClip = #"{"tempo":90,"key":"A minor","bars":1,"parts":[{"role":"melody","instrument":"bell","melody":"A4:4 C5:4 E5:4 r:4"}]}"#

private func lessonJSON(id: String = "L1", stage: String = "s1", steps: String) -> String {
    #"{"id":"\#(id)","stage":"\#(stage)","title":"t","summary":"s","steps":[\#(steps)]}"#
}

private func taskStep(tool: String = "melodyEditor", target: String? = "melody", uses: String = "[]",
                      starter: String? = nil, checks: String = "[]") -> String {
    var s = #"{"type":"task","title":"t","prompt":"p","tool":"\#(tool)","uses":\#(uses),"checks":\#(checks)"#
    if let target { s += #","targetRole":"\#(target)""# }
    if let starter { s += #","starter":\#(starter)"# }
    return s + "}"
}

/// Builds a temp content dir with stage "s1" listing `listed`, and the given lesson files.
private func makeDir(listed: [String], files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("content-\(UUID().uuidString)")
    let lessons = dir.appendingPathComponent("lessons")
    try FileManager.default.createDirectory(at: lessons, withIntermediateDirectories: true)
    let ids = listed.map { "\"\($0)\"" }.joined(separator: ",")
    let journey = #"{"version":1,"stages":[{"id":"s1","title":"S","tagline":"t","order":1,"lessons":[\#(ids)]}]}"#
    try journey.write(to: dir.appendingPathComponent("journey.json"), atomically: true, encoding: .utf8)
    for (name, body) in files { try body.write(to: lessons.appendingPathComponent(name), atomically: true, encoding: .utf8) }
    return dir
}

private func errors(listed: [String] = ["L1"], files: [String: String]) throws -> [String] {
    ContentValidator.validate(directory: try makeDir(listed: listed, files: files))
}

@Test func validatorAcceptsGoodLesson() throws {
    let step = taskStep(uses: #"["melody"]"#, starter: goodClip, checks: #"[{"kind":"inKey","role":"melody"}]"#)
    #expect(try errors(files: ["L1.json": lessonJSON(steps: step)]) == [])
}

@Test func validatorAcceptsEmptyStages() throws {
    #expect(try errors(listed: [], files: [:]) == [])
}

@Test func validatorFlagsEachRule() throws {
    func expectError(_ e: [String], id: String = "L1", fragment: String, decodeCase: Bool = false, _ rule: String) {
        #expect(e.contains { $0.contains(id) && $0.contains(fragment) }, "rule '\(rule)' produced no error with '\(fragment)': \(e)")
        if !decodeCase {
            #expect(!e.contains { $0.contains("failed to decode") }, "rule '\(rule)' fixture failed to decode: \(e)")
        }
    }
    expectError(try errors(listed: ["L1"], files: [:]), fragment: "no lesson file", "missing file")
    expectError(try errors(files: ["L1.json": lessonJSON(stage: "other", steps: #"{"type":"koala","body":"b"}"#)]),
                fragment: "but it is listed by stage", "stage mismatch")
    let badMelody = #"{"tempo":90,"key":"A minor","bars":1,"parts":[{"role":"melody","instrument":"bell","melody":"nonsense"}]}"#
    expectError(try errors(files: ["L1.json": lessonJSON(steps: taskStep(uses: #"["melody"]"#, starter: badMelody))]),
                fragment: "clip does not parse", "bad notation")
    let badKey = #"{"tempo":90,"key":"H sharp","bars":1,"parts":[{"role":"melody","instrument":"bell","melody":"A4:4"}]}"#
    let listen = #"{"type":"listen","title":"t","caption":"c","examples":[{"label":"l","explanation":"e","clip":\#(badKey)}]}"#
    expectError(try errors(files: ["L1.json": lessonJSON(steps: listen)]), fragment: "clip does not parse", "bad key")
    let roleStep = taskStep(uses: #"["melody"]"#, starter: goodClip, checks: #"[{"kind":"chordsInKey","role":"chords"}]"#)
    expectError(try errors(files: ["L1.json": lessonJSON(steps: roleStep)]),
                fragment: "neither targetRole nor in uses", "check role")
    let usesStep = taskStep(uses: #"["chords"]"#, starter: goodClip)
    expectError(try errors(files: ["L1.json": lessonJSON(steps: usesStep)]),
                fragment: "starter lacks that role", "starter lacks role")
    expectError(try errors(files: ["L1.json": lessonJSON(steps: taskStep(uses: #"["melody"]"#))]),
                fragment: "has no starter", "uses without starter")
    let drumStep = taskStep(tool: "melodyEditor", checks: #"[{"kind":"hatRollPresent"}]"#)
    expectError(try errors(files: ["L1.json": lessonJSON(steps: drumStep)]),
                fragment: "not drumGrid", "drum check")
    let koala = lessonJSON(steps: #"{"type":"koala","body":"b"}"#)
    expectError(try errors(files: ["a.json": koala, "b.json": koala]), id: "b.json",
                fragment: "duplicate lesson id 'L1'", "duplicate ids")
    expectError(try errors(listed: [], files: ["broken.json": "{ not json"]), id: "broken.json",
                fragment: "failed to decode", decodeCase: true, "undecodable")
}

@Test func validatorAcceptsDrumCheckInDrumGridTask() throws {
    let step = taskStep(tool: "drumGrid", target: "drums", checks: #"[{"kind":"hatRollPresent"},{"kind":"laneHitCount","lane":"kick","min":1}]"#)
    #expect(try errors(files: ["L1.json": lessonJSON(steps: step)]) == [])
}

@Test func libraryLoadsAndOrdersLessons() throws {
    let koala = { (id: String) in lessonJSON(id: id, steps: #"{"type":"koala","body":"b"}"#) }
    let dir = try makeDir(listed: ["B", "missing", "A"], files: ["a.json": koala("A"), "b.json": koala("B")])
    let lib = try ContentLibrary(directory: dir)
    let stage = lib.journey.stages[0]
    #expect(lib.lessons(in: stage).map(\.id) == ["B", "A"])
    #expect(lib.lesson("A")?.id == "A")
    #expect(lib.lesson("zzz") == nil)
}

@Test func libraryThrowsOnMalformedLesson() throws {
    let dir = try makeDir(listed: [], files: ["x.json": "{ nope"])
    #expect(throws: (any Error).self) { try ContentLibrary(directory: dir) }
}

@Test func repoContentIsValid() throws {
    #expect(ContentValidator.validate(directory: repoContent) == [])
    let lib = try ContentLibrary(directory: repoContent)
    let expected: [(String, String, String)] = [
        ("first-sounds", "First sounds", "tempo, key, picking a vibe"),
        ("the-idea", "The idea", "melody or loop as your seed"),
        ("harmony", "Harmony", "chords that fit your melody"),
        ("drums-groove", "Drums & groove", "patterns that lock with it"),
        ("eight08-bass", "808 & bass", "following the chords, sliding"),
        ("layers", "Layers", "counter-melodies, texture"),
        ("arrangement", "Arrangement", "loop → intro/verse/hook/bridge"),
        ("room-for-vocals", "Leave room for vocals", "space for the rapper or singer"),
    ]
    let stages = lib.journey.stages
    #expect(stages.map(\.id) == expected.map(\.0))
    #expect(stages.map(\.title) == expected.map(\.1))
    #expect(stages.map(\.tagline) == expected.map(\.2))
    #expect(stages.map(\.order) == Array(1...8))
}
