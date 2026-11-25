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
            LessonTab(onBackToJourney: { tab = .journey })
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

/// The current lesson's player, or a pointer to the Journey when no lesson is open.
struct LessonTab: View {
    @Environment(AppModel.self) private var model
    let onBackToJourney: () -> Void

    var body: some View {
        if let lesson = model.currentLesson {
            LessonPlayerView(lesson: lesson, onBackToJourney: onBackToJourney).id(lesson.id)
        } else {
            Text("Pick a lesson from the Journey").font(Theme.title(20)).foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.night.ignoresSafeArea())
        }
    }
}
