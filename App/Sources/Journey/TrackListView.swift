import SwiftUI
import MusicCore

/// All saved tracks: set active, new, rename, delete.
struct TrackListView: View {
    @Environment(AppModel.self) private var model
    @State private var showNew = false
    @State private var renaming: Track?
    @State private var renameText = ""
    @State private var deleting: Track?
    @State private var exporting: Track?

    var body: some View {
        List {
            if !model.skippedFiles.isEmpty {
                Text("\(model.skippedFiles.count) \(model.skippedFiles.count == 1 ? "file" : "files") couldn't be read")
                    .font(Theme.body(14)).foregroundStyle(Color.clash)
                    .listRowBackground(Color.panel)
            }
            ForEach(model.tracks) { track in
                row(track).listRowBackground(Color.panel)
            }
            if model.tracks.isEmpty {
                Text("No tracks yet.").font(Theme.body(15)).foregroundStyle(Color.mute)
                    .listRowBackground(Color.panel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.night.ignoresSafeArea())
        .safeAreaInset(edge: .top) { ErrorBanner().padding(.horizontal, 16) }
        .navigationTitle("Your tracks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Label("New track", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showNew) { NewTrackSheet() }
        .sheet(item: $exporting) { ExportSheet(track: $0) }
        .alert("Rename track", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { track in
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { model.renameTrack(id: track.id, to: renameText) }
        }
        .confirmationDialog("Delete track?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { track in
            Button("Delete \(track.name)", role: .destructive) { model.deleteTrack(id: track.id) }
            Button("Cancel", role: .cancel) {}
        } message: { track in
            Text("\(track.name) can't be recovered.")
        }
    }

    private func row(_ track: Track) -> some View {
        let isActive = model.progress.activeTrackID == track.id
        return HStack(spacing: 12) {
            Button { model.setActive(track.id) } label: {
                HStack(spacing: 12) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isActive ? Color.haze : Color.mute)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name).font(Theme.title(17)).foregroundStyle(Color.ink)
                        Text("\(track.key.name) · \(Int(track.tempo.rounded())) BPM · \(track.bars) bars")
                            .font(Theme.mono(12)).foregroundStyle(Color.mute)
                    }
                    Spacer()
                }
                .frame(minHeight: Theme.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isActive ? "Your Track" : "")
            .accessibilityHint("Makes this Your Track")
            Menu {
                Button("Export", systemImage: "square.and.arrow.up") { exporting = track }
                Button("Rename", systemImage: "pencil") { renameText = track.name; renaming = track }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = track }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(Color.mute)
                    .frame(width: Theme.minTarget, height: Theme.minTarget)
            }
            .accessibilityLabel("More for \(track.name)")
        }
    }
}
