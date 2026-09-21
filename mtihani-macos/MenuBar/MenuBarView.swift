import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updateManager: UpdateManager
    let openSettings: @MainActor () -> Void
    let closePopover: @MainActor @Sendable () -> Void
    let accountMenuTrackingChanged: @MainActor @Sendable (Bool) -> Void

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

            LabeledContent(
                "Active session", value: appState.activeSession?.displayName ?? "No active session"
            )
            .font(.callout)

            LabeledContent(
                "Click trigger",
                value:
                    "\(appState.settings.requiredClickCount) clicks · \(appState.triggerStatusTitle)"
            )
            .font(.callout)

            if appState.permissions.screenRecordingState != .granted {
                Divider()
                permissionNotice
                Divider()
            }

            Button {
                Task {
                    await appState.startNewSession()
                }
            } label: {
                Label(
                    appState.isSessionOperationInProgress
                        ? "Starting Session…"
                        : "New session",
                    systemImage: "plus.circle"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuBarSelectionButtonStyle())
            .disabled(
                !appState.isAuthenticated || appState.isSessionOperationInProgress
                    || coordinator.state.isProcessing)

            Button {
                closePopover()
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    await coordinator.captureAndUpload()
                }
            } label: {
                Label("Capture now", systemImage: "camera")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuBarSelectionButtonStyle())
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!appState.canCapture)

            Button {
                appState.settings.isTripleClickEnabled.toggle()
            } label: {
                Label(
                    appState.settings.isTripleClickEnabled
                        ? "Pause click capture" : "Resume click capture",
                    systemImage: appState.settings.isTripleClickEnabled
                        ? "pause.circle" : "play.circle"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(MenuBarSelectionButtonStyle())

            Divider()
            if let account = appState.authentication?.account {
                AccountSubmenuRow(
                    name: account.name ?? account.email ?? "Account",
                    email: account.email ?? "",
                    manageAccount: { appState.authentication?.manageAccount() },
                    switchAccount: {
                        closePopover()
                        appState.authentication?.signIn()
                    },
                    signOut: { Task { await appState.authentication?.signOut() } },
                    trackingChanged: { tracking in accountMenuTrackingChanged(tracking) }
                )
                .frame(height: 22)
            }

            if let error = appState.sessionOperationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if !appState.isAuthenticated {
                Button {
                    closePopover()
                    appState.authentication?.signIn()
                } label: {
                    Label("Sign in", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuBarSelectionButtonStyle())
                Text("Sign in to connect your sessions.").font(.caption)
            }

            if updateManager.state.updateAvailable {
                Text("An update is available. Open Settings → Updates to review it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuBarSelectionButtonStyle())

            Divider()

            Button {
                appState.quit()
            } label: {
                Label("Quit Mtihani", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuBarSelectionButtonStyle())
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
                Text(appState.readiness)
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
            appState.canCapture ? .green : .orange
        case .capturing, .uploading:
            .blue
        case .success:
            .green
        case .failed:
            .red
        }
    }
}

private struct MenuBarSelectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuBarSelectionRow(configuration: configuration)
    }

    private struct MenuBarSelectionRow: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .onHover { isHovering = $0 }
        }

        private var isSelected: Bool {
            isEnabled && (isHovering || configuration.isPressed)
        }
    }
}
