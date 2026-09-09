import SwiftUI

struct CheckForUpdatesView: View {
    @ObservedObject var updateManager: UpdateManager
    var title = "Check for Updates…"
    var beforeCheck: @MainActor @Sendable () -> Void = {}

    var body: some View {
        Button(title) {
            beforeCheck()
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.state.canCheckForUpdates)
    }
}
