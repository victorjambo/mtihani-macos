//
//  mtihani_macosApp.swift
//  mtihani-macos
//
//  Created by Victor Mutai on 05/09/2026.
//

import SwiftUI

@main
struct MtihaniApp: App {
    @StateObject private var appState: AppState

    init() {
        let state = AppState.live()
        _appState = StateObject(wrappedValue: state)
        state.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
    }
}
