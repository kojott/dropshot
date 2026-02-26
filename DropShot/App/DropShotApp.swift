import SwiftUI
import KeyboardShortcuts

// MARK: - Keyboard Shortcut Names

extension KeyboardShortcuts.Name {
    static let captureScreenshot = Self("captureScreenshot", default: .init(.u, modifiers: [.command, .shift]))
    static let uploadClipboard = Self("uploadClipboard", default: .init(.v, modifiers: [.command, .control]))
}

// MARK: - App Entry Point

@main
struct DropShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}
