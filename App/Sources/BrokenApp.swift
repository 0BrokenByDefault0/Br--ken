import SwiftUI
import MusicCore
import SoundEngine

@main
struct BrokenApp: App {
    @State private var audioHost: AudioHost
    @State private var model: AppModel?
    private let loadError: String?
    private let player: AudioPlayer

    init() {
        let player = AudioPlayer()
        self.player = player
        let host = AudioHost(session: SystemAudioSession(), makeEngine: {
            let engine = AVAudioEngineController()
            player.attach(engine.renderer)
            return engine
        })
        try? host.start()  // a failure is kept in host.lastError
        _audioHost = State(initialValue: host)

        do {
            guard let contentURL = Bundle.main.url(forResource: "Content", withExtension: nil) else {
                throw AppLaunchError.contentMissing
            }
            let documents = URL.documentsDirectory
            let model = AppModel(
                content: try ContentLibrary(directory: contentURL),
                trackStore: TrackStore(directory: documents.appendingPathComponent("tracks", isDirectory: true)),
                progressStore: ProgressStore(fileURL: documents.appendingPathComponent("progress.json")),
                audio: player)
            _model = State(initialValue: model)
            loadError = nil
        } catch {
            _model = State(initialValue: nil)
            loadError = "\(error)"
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    LabRootView(audio: player)  // temporary root until the real navigation (Task 17)
                        .environment(model)
                        .environment(audioHost)
                } else {
                    LaunchErrorView(message: loadError ?? "Unknown error")
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

private enum AppLaunchError: Error, CustomStringConvertible {
    case contentMissing
    var description: String { "The lesson content folder is missing from the app." }
}

/// Stand-in until the real Journey screen exists: the stage titles.
private struct JourneyPlaceholderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.content.journey.stages) { stage in
                Text(stage.title)
            }
            .navigationTitle("Br--ken")
        }
    }
}

private struct LaunchErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Br--ken can't open its lessons")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
