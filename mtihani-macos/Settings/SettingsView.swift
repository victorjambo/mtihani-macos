import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    private var settings: AppSettings {
        appState.settings
    }

    private var coordinator: CaptureCoordinator {
        appState.captureCoordinator
    }

    var body: some View {
        Form {
            Section("Backend") {
                TextField("Backend URL", text: binding(for: \AppSettings.backendURL))
                    .textFieldStyle(.roundedBorder)

                SecureField(
                    "Mtihani Client Key",
                    text: binding(for: \AppSettings.apiKey)
                )
                    .textFieldStyle(.roundedBorder)

                Text("Include the API path, for example http://localhost:5173/api.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Session") {
                Picker("Previous Session", selection: previousSessionSelection) {
                    Text("Select a session…").tag("")
                    ForEach(appState.sessions, id: \.id) { session in
                        Text("\(session.id) · \(session.status.rawValue.capitalized)")
                            .tag(session.id)
                    }
                }
                .disabled(appState.isSessionOperationInProgress || appState.sessions.isEmpty)

                TextField("Session ID", text: binding(for: \AppSettings.sessionID))
                    .textFieldStyle(.roundedBorder)

                if let error = appState.sessionOperationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker(
                    "Preferred Language",
                    selection: binding(for: \AppSettings.preferredLanguage)
                ) {
                    ForEach(PreferredLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                HStack {
                    LabeledContent(
                        "Backend Connection",
                        value: coordinator.connectionState.title
                    )
                    Spacer()
                    Button("Test Connection") {
                        Task {
                            await coordinator.validateSession()
                        }
                    }
                    .disabled(
                        coordinator.state.isProcessing
                            || settings.trimmedSessionID.isEmpty
                    )

                    Button("Refresh Sessions") {
                        Task {
                            await appState.refreshSessions()
                        }
                    }
                    .disabled(appState.isSessionOperationInProgress)
                }
            }

            Section("Capture") {
                Toggle(
                    "Click anywhere to capture",
                    isOn: binding(for: \AppSettings.isTripleClickEnabled)
                )

                Stepper(
                    "Required clicks: \(settings.requiredClickCount)",
                    value: binding(for: \AppSettings.requiredClickCount),
                    in: AppSettings.requiredClickCountRange
                )
                .disabled(!settings.isTripleClickEnabled)

                LabeledContent(
                    "Global Click Monitor",
                    value: appState.triggerStatusTitle
                )
            }

            Section("Permissions") {
                LabeledContent(
                    "Screen Recording",
                    value: screenRecordingPermissionTitle
                )

                if appState.permissions.screenRecordingState != .granted {
                    Text(
                        "Grant Screen Recording access, then return to Mtihani. macOS may require the app to be relaunched."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        if !appState.permissions.hasRequestedScreenRecordingThisLaunch {
                            Button("Request Access") {
                                appState.requestScreenRecordingPermission()
                            }
                        }
                        Button("Open System Settings") {
                            appState.permissions.openScreenRecordingSettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 580)
        .onAppear {
            appState.start()
            appState.permissions.refreshScreenRecordingPermission()
            Task {
                await appState.refreshSessions()
            }
        }
    }

    private var screenRecordingPermissionTitle: String {
        switch appState.permissions.screenRecordingState {
        case .unknown:
            "Unknown"
        case .granted:
            "Granted"
        case .denied:
            "Not granted"
        }
    }

    private var previousSessionSelection: Binding<String> {
        Binding(
            get: {
                let currentID = settings.trimmedSessionID
                return appState.sessions.contains { $0.id == currentID }
                    ? currentID
                    : ""
            },
            set: { sessionID in
                guard !sessionID.isEmpty else { return }
                settings.sessionID = sessionID
            }
        )
    }

    private func binding<Value>(
        for keyPath: ReferenceWritableKeyPath<AppSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }
}
