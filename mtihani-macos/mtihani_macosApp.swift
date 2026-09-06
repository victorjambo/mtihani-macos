//
//  mtihani_macosApp.swift
//  mtihani-macos
//
//  Created by Victor Mutai on 05/09/2026.
//

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState.live()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.start()
        menuBarController = MenuBarController(appState: appState)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
    }
}

@main
struct MtihaniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}
