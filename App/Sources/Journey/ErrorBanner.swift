import SwiftUI

/// A dismissible banner for `AppModel.lastError` (save and delete failures).
struct ErrorBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.lastError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.clash)
                Text(message).font(Theme.body(14)).foregroundStyle(Color.ink)
                Spacer(minLength: 0)
                Button { model.dismissError() } label: {
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
}
