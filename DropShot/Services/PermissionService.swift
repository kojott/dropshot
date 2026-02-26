import Foundation
import AppKit
import CoreGraphics

// MARK: - Permission Service

@MainActor
final class PermissionService {
    static let shared = PermissionService()

    private init() {}

    // MARK: - Screen Recording Permission

    /// Checks whether the app has screen recording permission by attempting to
    /// capture a 1x1 pixel region of the screen. If the system denies access,
    /// the capture returns nil or an empty image.
    ///
    /// This is the standard detection technique recommended for macOS apps that
    /// need screen capture. The CGWindowListCreateImage call is lightweight and
    /// does not produce a visible side effect.
    func hasScreenRecordingPermission() -> Bool {
        // Attempt to capture a tiny region of the main display.
        let screenRect = CGRect(x: 0, y: 0, width: 1, height: 1)

        guard let image = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            return false
        }

        // On macOS 10.15+, if permission is denied the image will be created
        // but will be entirely transparent (zero-width or zero-height is also
        // possible on some versions). A valid capture should have non-zero
        // dimensions.
        return image.width > 0 && image.height > 0
    }

    // MARK: - Open System Settings

    /// Opens System Settings to the Screen Recording privacy pane.
    func openScreenRecordingSettings() {
        openSystemPreferencesPane("com.apple.preference.security", anchor: "Privacy_ScreenCapture")
    }

    /// Opens System Settings to the Input Monitoring privacy pane.
    func openInputMonitoringSettings() {
        openSystemPreferencesPane("com.apple.preference.security", anchor: "Privacy_ListenEvent")
    }

    /// Opens System Settings to the Accessibility privacy pane.
    func openAccessibilitySettings() {
        openSystemPreferencesPane("com.apple.preference.security", anchor: "Privacy_Accessibility")
    }

    // MARK: - Guidance Dialogs

    /// Presents a modal alert explaining that screen recording permission is required,
    /// with a button to jump directly to System Settings.
    func showScreenRecordingGuidance() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
            DropShot needs screen recording permission to capture screenshots for upload.

            To grant access:
            1. Click "Open System Settings" below.
            2. Find "DropShot" in the list.
            3. Toggle the switch ON.
            4. You may need to restart DropShot for the change to take effect.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }

    /// Presents a modal alert explaining that input monitoring permission is required,
    /// with a button to jump directly to System Settings.
    func showInputMonitoringGuidance() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Permission Required"
        alert.informativeText = """
            DropShot needs input monitoring permission to detect global keyboard shortcuts \
            (e.g., screenshot hotkeys).

            To grant access:
            1. Click "Open System Settings" below.
            2. Find "DropShot" in the list.
            3. Toggle the switch ON.
            4. You may need to restart DropShot for the change to take effect.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openInputMonitoringSettings()
        }
    }

    // MARK: - Private Helpers

    /// Opens a specific System Preferences / System Settings pane using the
    /// `x-apple.systempreferences:` URL scheme (macOS 13+).
    /// Falls back to the legacy `com.apple.systempreferences` bundle approach
    /// if the URL scheme is unavailable.
    private func openSystemPreferencesPane(_ paneId: String, anchor: String) {
        // macOS 13 Ventura and later use the x-apple.systempreferences URL scheme.
        // The format is: x-apple.systempreferences:<paneId>?<anchor>
        let urlString = "x-apple.systempreferences:\(paneId)?\(anchor)"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: attempt to open System Settings directly.
            let fallbackURL = URL(string: "x-apple.systempreferences:")!
            NSWorkspace.shared.open(fallbackURL)
        }
    }
}
