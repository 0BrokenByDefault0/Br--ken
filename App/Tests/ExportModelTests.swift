import Testing
import Foundation
import MusicCore
import SoundEngine
@testable import Broken

@MainActor
struct ExportModelTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)/Exports")
    }

    private func melody(muted: Bool = false) -> Part {
        Part(role: .melody, instrument: .bell,
             content: .notes(NoteSequence(notes: [NoteEvent(start: 0, length: 96, pitch: 72, velocity: 1)])),
             sound: SoundSettings(volume: 0.8, reverb: 0), muted: muted)
    }

    private func chords(muted: Bool = false) -> Part {
        Part(role: .chords, instrument: .pad,
             content: .notes(NoteSequence(notes: [NoteEvent(start: 0, length: 192, pitch: 57, velocity: 1)])),
             sound: SoundSettings(volume: 0.8, reverb: 0), muted: muted)
    }

    private func drums(muted: Bool = false) -> Part {
        Part(role: .drums, instrument: .trapKit,
             content: .drums(DrumPattern(lanes: [.kick: [DrumHit(tick: 0, velocity: 1)]])),
             sound: SoundSettings(volume: 0.8, reverb: 0), muted: muted)
    }

    private func track(_ parts: [Part]) -> Track {
        Track(name: "My Beat", createdAt: Date(timeIntervalSince1970: 0), tempo: 140,
              key: Key(tonic: PitchClass(9), mode: .minor), bars: 2, parts: parts)
    }

    @Test func fullMixWritesOneFileNamedCorrectly() async throws {
        let dir = tempDir()
        let t = track([melody(), drums()])
        let urls = try await ExportModel(track: t, directory: dir).export(scope: .fullMix, loopReady: true)
        #expect(urls.count == 1)
        #expect(urls[0].lastPathComponent == "My-Beat-140bpm-Aminor.wav")
        #expect(urls[0].deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: urls[0].path))
    }

    @Test func stemsOnePerUnmutedPart() async throws {
        let t = track([melody(), chords(muted: true), drums()])
        let urls = try await ExportModel(track: t, directory: tempDir()).export(scope: .stems, loopReady: false)
        #expect(urls.map(\.lastPathComponent).sorted()
                == ["My-Beat-140bpm-Aminor-drums.wav", "My-Beat-140bpm-Aminor-melody.wav"])
    }

    @Test func stemsSkipEmptyParts() async throws {
        let empty = Part(role: .chords, instrument: .pad, content: .notes(NoteSequence(notes: [])))
        let urls = try await ExportModel(track: track([melody(), empty]), directory: tempDir())
            .export(scope: .stems, loopReady: false)
        #expect(urls.count == 1)
    }

    @Test func singlePartExportsEvenWhenMuted() async throws {
        let c = chords(muted: true)
        let urls = try await ExportModel(track: track([melody(), c]), directory: tempDir())
            .export(scope: .part(c.id), loopReady: false)
        #expect(urls.map(\.lastPathComponent) == ["My-Beat-140bpm-Aminor-chords.wav"])
    }

    @Test func exportedFileFrameCountExact() async throws {
        let urls = try await ExportModel(track: track([melody()]), directory: tempDir())
            .export(scope: .fullMix, loopReady: true)
        let data = try Data(contentsOf: urls[0])
        // Walk the RIFF chunks to the "data" chunk and read its size.
        var offset = 12
        var dataSize = -1
        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = data[offset + 4..<offset + 8].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            if id == "data" { dataSize = size; break }
            offset += 8 + size + (size & 1)
        }
        let frames = OfflineRenderer.frameCount(bars: 2, tempo: 140, sampleRate: 48_000)
        #expect(dataSize == frames * 4)
    }

    @Test func overwritesExistingFile() async throws {
        let dir = tempDir()
        let model = ExportModel(track: track([melody()]), directory: dir)
        _ = try await model.export(scope: .fullMix, loopReady: false)
        let urls = try await model.export(scope: .fullMix, loopReady: false)
        #expect(urls.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
    }
}
