import SwiftUI

/// Dismissible banners for `AppModel.lastError` (save and delete failures) and `AudioHost.lastError`
/// (the audio engine couldn't start).
struct ErrorBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(AudioHost.self) private var audioHost: AudioHost?

    var body: some View {
        // Nothing at all (not an empty stack) when there is no error, so it takes no spacing.
        if model.lastError != nil || audioHost?.lastError != nil {
            VStack(spacing: 8) {
                if let message = model.lastError {
                    ErrorRow(message: message) { model.dismissError() }
                }
                if let audioHost, let message = audioHost.lastError {
                    ErrorRow(message: "No sound: \(message)") { audioHost.dismissError() }
                }
            }
        }
    }
}

private struct ErrorRow: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.clash)
            Text(message).font(Theme.body(14)).foregroundStyle(Color.ink)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.mute)
                    .frame(width: Theme.minTarget, height: Theme.minTarget)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.clash.opacity(0.6), lineWidth: 1))
    }
}
