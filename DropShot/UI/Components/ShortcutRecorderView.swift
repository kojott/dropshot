import SwiftUI
import KeyboardShortcuts

// MARK: - Shortcut Recorder View

/// A labeled enable/disable toggle paired with the current shortcut display.
///
/// Uses `KeyboardShortcuts.Recorder` with the documented SwiftUI API
/// (`Recorder(_:name:)`) which integrates correctly with SwiftUI's
/// view lifecycle, avoiding NSViewRepresentable issues in custom windows.
///
/// When the toggle is off, the recorder is visually disabled to indicate
/// that the shortcut will not fire even if a key combination is assigned.
struct ShortcutRecorderView: View {
    /// The keyboard shortcut name to record for.
    let name: KeyboardShortcuts.Name

    /// The human-readable label displayed alongside the toggle.
    let label: String

    /// Binding that controls whether this shortcut is active.
    @Binding var isEnabled: Bool

    var body: some View {
        HStack {
            Toggle(label, isOn: $isEnabled)
                .accessibilityLabel(label)
                .accessibilityValue(isEnabled ? "Enabled" : "Disabled")

            Spacer()

            KeyboardShortcuts.Recorder("", name: name)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1.0 : 0.5)
                .accessibilityLabel("Keyboard shortcut for \(label)")
                .accessibilityHint(isEnabled ? "Click to record a new shortcut" : "Enable the toggle first to change this shortcut")
        }
    }
}
