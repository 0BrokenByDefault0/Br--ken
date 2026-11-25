import SwiftUI

enum AppTab: Hashable {
    case journey, lesson, melody, chords, drums
}

/// The app's home: Journey · Lesson · Melody · Chords · Drums.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.journey

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { JourneyMapView(onOpenLesson: { tab = .lesson }) }
                .tabItem { Label("Journey", systemImage: "map") }.tag(AppTab.journey)
            LessonPlaceholderView()
                .tabItem { Label("Lesson", systemImage: "book") }.tag(AppTab.lesson)
            MelodyScreen()
                .tabItem { Label("Melody", systemImage: "pianokeys") }.tag(AppTab.melody)
            ChordsScreen()
                .tabItem { Label("Chords", systemImage: "music.note.list") }.tag(AppTab.chords)
            DrumsScreen()
                .tabItem { Label("Drums", systemImage: "square.grid.4x3.fill") }.tag(AppTab.drums)
        }
        .tint(Color.haze)
        .toolbarBackground(Color.panel, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .preferredColorScheme(.dark)
        // Playback belongs to the screen it was started on.
        .onChange(of: tab) { _, _ in
            model.flushPendingPreview()
            if model.isPlaying { model.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flushPendingPreview() }
        }
    }
}

/// Stand-in until the lesson player (Task 18): names the current lesson.
struct LessonPlaceholderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            if let lesson = model.currentLesson {
                Text(lesson.title).font(Theme.title(24)).foregroundStyle(Color.ink)
                Text(lesson.summary).font(Theme.body(15)).foregroundStyle(Color.mute)
            } else {
                Text("Pick a lesson from the Journey").font(Theme.title(20)).foregroundStyle(Color.ink)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.night.ignoresSafeArea())
    }
}
