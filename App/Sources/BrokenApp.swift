import SwiftUI
import MusicCore
import SoundEngine

@main
struct BrokenApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Br--ken")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
