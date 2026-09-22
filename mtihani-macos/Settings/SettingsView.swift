import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case sessions = "Sessions"
    case capture = "Capture"
    case permissions = "Permissions"
    case updates = "Updates"
    case account = "Account"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sessions: "rectangle.stack"
        case .capture: "camera"
        case .permissions: "hand.raised"
        case .updates: "arrow.down.circle"
        case .account: "person.crop.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let updateManager: UpdateManager
    @State private var tab: SettingsTab? = .sessions
    @State private var manualID = ""
    @State private var sessionSearch = ""
    @State private var validating = false
    @State private var confirmSignOut = false
    private var settings: AppSettings { appState.settings }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $tab) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
                    .padding(.vertical, 5)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 165, max: 190)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text((tab ?? .sessions).rawValue).font(.title2.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }.padding(24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch tab ?? .sessions {
                        case .sessions: sessionsContent
                        case .capture: captureContent
                        case .permissions: permissionsContent
                        case .updates:
                            Form { UpdateSettingsView(updateManager: updateManager) }
                                .formStyle(.grouped).frame(minHeight: 330)
                        case .account: accountContent
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
                if tab == .sessions {
                    Divider()
                    HStack {
                        Label(appState.connectionTitle, systemImage: "network")
                        Spacer()
                        Button("Test connection") { Task { await appState.testConnection() } }
                            .disabled(appState.checkingConnection)
                    }.padding(20)
                }
            }
        }
        .frame(minWidth: 700, idealWidth: 780, minHeight: 530, idealHeight: 600)
        .onAppear { appState.start() }
        .onChange(of: appState.authentication?.generation) {
            manualID = ""
            sessionSearch = ""
        }
        .confirmationDialog("Sign out of Mtihani on this Mac?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) {
                Task { await appState.authentication?.signOut() }
            }
        } message: {
            Text("Capture will pause. Your device preferences will be kept.")
        }
    }

    private var subtitle: String {
        switch tab ?? .sessions {
        case .sessions: "Choose where your captures are sent."
        case .capture: "Choose how to capture your screen."
        case .permissions: "Manage access needed to capture your screen."
        case .updates: "Keep Mtihani up to date."
        case .account: "Manage your connected account."
        }
    }
    private var signInButton: some View {
        Button("Sign in") { appState.authentication?.signIn() }
            .buttonStyle(.borderedProminent)
            .disabled(appState.authentication?.state == .signingIn)
    }
    @ViewBuilder private var sessionsContent: some View {
        if !appState.isAuthenticated {
            ContentUnavailableView {
                Label("Connect your sessions", systemImage: "rectangle.stack")
            } description: {
                Text("Sign in to create a session or continue an existing one.")
            } actions: {
                signInButton
            }
        } else {
            GroupBox {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active session").font(.subheadline).foregroundStyle(.secondary)
                        Text(appState.activeSession?.displayName ?? "No active session").font(
                            .headline
                        )
                        .textSelection(.enabled).lineLimit(2)
                        .help(appState.activeSession?.id ?? "Select or create a session")
                        if let session = appState.activeSession {
                            Button("Copy session ID", systemImage: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(session.id, forType: .string)
                            }.controlSize(.small)
                        }
                    }
                    Spacer()
                    Button(appState.isSessionOperationInProgress ? "Please wait…" : "New session") {
                        Task { await appState.startNewSession() }
                    }.buttonStyle(.borderedProminent).disabled(
                        appState.isSessionOperationInProgress)
                }.padding(10)
            }
            if appState.sessions.isEmpty && !appState.isSessionOperationInProgress {
                Text("Create your first session to start capturing.").foregroundStyle(.secondary)
            }
            if appState.sessions.count > 20 {
                TextField("Search sessions", text: $sessionSearch).textFieldStyle(.roundedBorder)
            }
            if appState.isSessionOperationInProgress {
                ProgressView("Loading sessions…").controlSize(.small)
            }
            HStack {
                Picker(
                    "Choose session",
                    selection: Binding(
                        get: { appState.activeSession?.id ?? "" },
                        set: { id in Task { await validate(id) } }
                    )
                ) {
                    Text("Select a session…").tag("")
                    ForEach(
                        appState.sessions.filter {
                            sessionSearch.isEmpty || $0.id == appState.activeSession?.id
                                || $0.displayName.localizedCaseInsensitiveContains(sessionSearch)
                                || $0.id.localizedCaseInsensitiveContains(sessionSearch)
                        }, id: \.id
                    ) { session in
                        Text(
                            session.displayName + (session.status == .closed ? " · Closed" : "")
                        )
                        .tag(session.id).disabled(session.status != .active)
                    }
                }.disabled(validating || appState.isSessionOperationInProgress)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await appState.refreshSessions() }
                }
                .disabled(appState.isSessionOperationInProgress)
            }
            DisclosureGroup("Enter session ID") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Session ID", text: $manualID).textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await validate(manualID) } }
                        Button("Use session") { Task { await validate(manualID) } }
                            .disabled(
                                validating
                                    || manualID.trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty
                            )
                    }
                    Text("Only sessions available to your account can be used.").font(.caption)
                        .foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            if validating { ProgressView("Validating session…").controlSize(.small) }
            if let error = appState.sessionOperationError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(
                    .callout)
                Button("Retry refresh") { Task { await appState.refreshSessions() } }
                    .disabled(appState.isSessionOperationInProgress)
            }
            Picker("Programming language", selection: binding(\.preferredLanguage)) {
                ForEach(PreferredLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            Text("Signed in as \(appState.authentication?.account?.email ?? "your account")")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
    private func validate(_ id: String) async {
        guard !validating else { return }
        validating = true
        await appState.selectSession(id)
        validating = false
    }
    private var captureContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Capture with repeated clicks", isOn: binding(\.isTripleClickEnabled))
                        .toggleStyle(.switch)
                    Text("Click \(settings.requiredClickCount) times quickly to capture.")
                        .foregroundStyle(.secondary)
                    Divider()
                    Stepper(
                        "Required clicks: \(settings.requiredClickCount)",
                        value: binding(\.requiredClickCount), in: 3...6
                    )
                    .disabled(!settings.isTripleClickEnabled)
                    Text("Choose between 3 and 6 clicks.").font(.caption).foregroundStyle(
                        .secondary)
                }.padding(10)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text(
                        "Triggering again within \(settings.bufferWindowSeconds)s adds another screenshot to the same capture, for questions that scroll off one screen."
                    )
                    .foregroundStyle(.secondary)
                    Divider()
                    Stepper(
                        "Buffer window: \(settings.bufferWindowSeconds)s",
                        value: binding(\.bufferWindowSeconds), in: 5...60
                    )
                    Text("Choose between 5 and 60 seconds.").font(.caption).foregroundStyle(
                        .secondary)
                }.padding(10)
            }
            LabeledContent("Capture display", value: "Display containing the pointer")
            Label("Clicks inside Mtihani do not trigger captures.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
            Text("Click trigger: \(appState.triggerStatusTitle)").font(.callout)
            Divider()
            HStack {
                Text(appState.readiness)
                Spacer()
                Button("Capture now") {
                    Task { await appState.captureCoordinator.captureAndUpload() }
                }
                .disabled(!appState.canCapture)
            }
            if let detail = appState.captureCoordinator.state.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var permissionsContent: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Screen recording", systemImage: "display").font(.headline)
                Label(
                    permissionTitle,
                    systemImage: appState.permissions.screenRecordingState == .granted
                        ? "checkmark.circle" : "exclamationmark.circle")
                Text("Allow Mtihani to capture screenshots of your screen.").foregroundStyle(
                    .secondary)
                HStack {
                    if appState.permissions.screenRecordingState != .granted
                        && !appState.permissions.hasRequestedScreenRecordingThisLaunch
                    {
                        Button("Allow screen recording") {
                            appState.requestScreenRecordingPermission()
                        }.buttonStyle(.borderedProminent)
                    }
                    Button("Open System Settings", systemImage: "arrow.up.right") {
                        appState.permissions.openScreenRecordingSettings()
                    }
                }
                Text("Permission status updates when you return to Mtihani.").font(.caption)
                    .foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var permissionTitle: String {
        switch appState.permissions.screenRecordingState {
        case .unknown: "Checking…"
        case .granted: "Granted"
        case .denied: "Not granted"
        }
    }
    @ViewBuilder private var accountContent: some View {
        if appState.authentication?.state == .signingIn {
            ProgressView("Complete sign-in in your browser.")
            Button("Cancel") { appState.authentication?.cancelSignIn() }
        } else if let account = appState.authentication?.account {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        AsyncImage(url: account.avatarUrl.flatMap(URL.init(string:))) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill").resizable()
                        }
                        .frame(width: 48, height: 48).clipShape(Circle()).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(account.name ?? "Mtihani account").font(.headline)
                            Text(account.email ?? "").foregroundStyle(.secondary).textSelection(
                                .enabled)
                        }
                    }
                    Label("Signed in", systemImage: "checkmark.circle")
                    HStack {
                        Button("Switch account") { appState.authentication?.signIn() }
                        Button("Manage account", systemImage: "arrow.up.right") {
                            appState.authentication?.manageAccount()
                        }
                    }
                    Text("Account settings open in your browser.").font(.caption).foregroundStyle(
                        .secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Button("Sign out", role: .destructive) { confirmSignOut = true }
            Text("Signing out pauses capture on this Mac.").font(.caption).foregroundStyle(
                .secondary)
        } else {
            Text("Sign in to connect your account and sessions.")
            signInButton
            Button("Retry saved sign-in") { appState.authentication?.retryRestore() }
        }
        if let message = appState.authentication?.message {
            Text(message).foregroundStyle(.secondary)
        }
    }
    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}
