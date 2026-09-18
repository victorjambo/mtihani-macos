import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updateManager: UpdateManager
    private let version = AppVersion()

    var body: some View {
        Section("Updates") {
            LabeledContent("Installed version", value: version.displayString)
                .textSelection(.enabled)

            Toggle(
                "Automatically check for updates",
                isOn: $updateManager.automaticallyChecksForUpdates
            )
            .disabled(updateManager.startupError != nil)

            Toggle(
                "Automatically download updates", isOn: $updateManager.automaticallyDownloadsUpdates
            )
            .disabled(
                !updateManager.state.allowsAutomaticUpdates || updateManager.startupError != nil)

            Text("Download updates in the background when available.")
                .font(.caption)
                .foregroundStyle(.secondary)

            CheckForUpdatesView(updateManager: updateManager, title: "Check for Updates Now")
            Text(updateManager.state.status).font(.callout).accessibilityLabel(
                "Update status: \(updateManager.state.status)")

            if let error = updateManager.startupError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
