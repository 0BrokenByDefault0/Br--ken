import SwiftUI
import MusicCore

/// Pick what to export, render it, then share the files (for example into Koala).
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ExportModel
    @State private var scope: ExportScope = .fullMix
    @State private var loopReady = true

    init(track: Track, directory: URL = ExportModel.defaultDirectory) {
        _model = State(initialValue: ExportModel(track: track, directory: directory))
    }

    private var exportableParts: [Part] { model.track.parts.filter(\.hasContent) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.track.name).font(Theme.title(20)).foregroundStyle(Color.ink)

                    Picker("What to export", selection: $scope) {
                        Text("Full mix").tag(ExportScope.fullMix)
                        Text("Stems").tag(ExportScope.stems)
                        ForEach(exportableParts) { part in
                            Text(part.role.displayName).tag(ExportScope.part(part.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(model.isExporting)
                    .tint(Color.haze)
                    .frame(minHeight: Theme.minTarget)

                    Text(scopeNote).font(Theme.body(14)).foregroundStyle(Color.mute)

                    Toggle("Loop-ready (tails wrap)", isOn: $loopReady)
                        .font(Theme.body(16)).foregroundStyle(Color.ink)
                        .tint(Color.haze)
                        .disabled(model.isExporting)
                        .frame(minHeight: Theme.minTarget)

                    Button {
                        Task { await model.run(scope: scope, loopReady: loopReady) }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isExporting { ProgressView().tint(Color.night) }
                            Text(model.isExporting ? "Rendering…" : "Export").font(Theme.title(17))
                        }
                        .foregroundStyle(Color.night)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTarget + 6)
                        .background(Color.amber, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(model.isExporting)

                    if let message = model.errorMessage {
                        Text(message).font(Theme.body(14)).foregroundStyle(Color.clash)
                    }

                    if !model.urls.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.urls, id: \.self) { url in
                                Text(url.lastPathComponent).font(Theme.mono(12)).foregroundStyle(Color.tone)
                            }
                            ShareLink(items: model.urls) {
                                Label("Share \(model.urls.count == 1 ? "file" : "\(model.urls.count) files")",
                                      systemImage: "square.and.arrow.up")
                                    .font(Theme.title(16)).foregroundStyle(Color.haze)
                                    .frame(minHeight: Theme.minTarget)
                            }
                            Text("In Koala: tap ＋ → Import → Files")
                                .font(Theme.body(14)).foregroundStyle(Color.mute)
                            Text("Files are also saved in Files app › Br--ken › Exports.")
                                .font(Theme.body(12)).foregroundStyle(Color.mute)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(Color.night.ignoresSafeArea())
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: scope) { _, _ in model.resetResult() }
            .onChange(of: loopReady) { _, _ in model.resetResult() }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var scopeNote: String {
        switch scope {
        case .fullMix: "One file with every part that isn't muted."
        case .stems: "One file per unmuted part, to rearrange in Koala."
        case .part: "Just this part, even if it is muted."
        }
    }
}
