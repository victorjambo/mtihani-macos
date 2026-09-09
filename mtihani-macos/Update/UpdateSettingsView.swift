import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updateManager: UpdateManager
    private let version = AppVersion()

    var body: some View {
        Section("General · Updates") {
            LabeledContent("Version", value: version.displayString)
                .textSelection(.enabled)

            Toggle("Automatically check for updates", isOn: $updateManager.automaticallyChecksForUpdates)
                .disabled(updateManager.startupError != nil)

            Toggle("Automatically download updates", isOn: $updateManager.automaticallyDownloadsUpdates)
                .disabled(!updateManager.state.allowsAutomaticUpdates || updateManager.startupError != nil)

            Text("Check daily. When automatic downloads are enabled, updates can install when you quit.")
                .font(.caption)
                .foregroundStyle(.secondary)

            CheckForUpdatesView(updateManager: updateManager, title: "Check for Updates Now")

            if let error = updateManager.startupError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
