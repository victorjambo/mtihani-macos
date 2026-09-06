import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    let openSettings: @MainActor () -> Void

    private var coordinator: CaptureCoordinator {
        appState.captureCoordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHeader

            if let detail = coordinator.state.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            LabeledContent("Session", value: coordinator.connectionState.title)
                .font(.callout)

            LabeledContent(
                "Click trigger",
                value: "\(appState.settings.requiredClickCount) clicks · \(appState.triggerStatusTitle)"
            )
                .font(.callout)

            if appState.permissions.screenRecordingState != .granted {
                permissionNotice
            }

            Divider()

            Button {
                Task {
                    await appState.startNewSession()
                }
            } label: {
                Label(
                    appState.isSessionOperationInProgress
                        ? "Starting Session…"
                        : "Start New Session",
                    systemImage: "plus.circle"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(appState.isSessionOperationInProgress || coordinator.state.isProcessing)

            Button {
                Task {
                    await coordinator.captureAndUpload()
                }
            } label: {
                Label("Capture Now", systemImage: "camera")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!coordinator.canCapture)

            if let error = appState.sessionOperationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                appState.quit()
            } label: {
                Label("Quit Mtihani", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            appState.start()
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.title2)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mtihani")
                    .font(.headline)
                Text(coordinator.state.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Screen Recording permission is required for captures.",
                systemImage: "rectangle.inset.filled.badge.record"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                if !appState.permissions.hasRequestedScreenRecordingThisLaunch {
                    Button("Request Access") {
                        appState.requestScreenRecordingPermission()
                    }
                }
                Button("Open Settings") {
                    appState.permissions.openScreenRecordingSettings()
                }
            }
            .controlSize(.small)
        }
    }

    private var statusSymbol: String {
        switch coordinator.state {
        case .idle:
            "circle.fill"
        case .capturing:
            "camera.viewfinder"
        case .uploading:
            "arrow.up.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .idle:
            .green
        case .capturing, .uploading:
            .blue
        case .success:
            .green
        case .failed:
            .red
        }
    }
}
