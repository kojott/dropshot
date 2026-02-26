import SwiftUI
import AppKit

// MARK: - Unknown Host View

/// Dialog presented when connecting to a server for the first time.
/// Displays the server's SSH host key fingerprint and asks the user
/// whether to trust it.
struct UnknownHostView: View {
    /// The hostname or IP address of the server.
    let hostname: String

    /// The SSH host key fingerprint (e.g., SHA256:...).
    let fingerprint: String

    /// Called with `true` if the user chooses to trust the key, `false` if cancelled.
    let onComplete: (Bool) -> Void

    @State private var showExplanation: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            // Warning icon
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
                .accessibilityHidden(true)

            // Title
            Text("Unknown Server")
                .font(.title2)
                .fontWeight(.semibold)

            // Description
            VStack(spacing: 8) {
                Text("DropShot has not connected to this server before.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Server hostname
                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(hostname)
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)
            }

            // Fingerprint display
            VStack(alignment: .leading, spacing: 4) {
                Text("Server fingerprint:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(fingerprint)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .accessibilityLabel("Server fingerprint: \(fingerprint)")
            }
            .padding(.horizontal, 8)

            // Explanation toggle
            DisclosureGroup("What is this?", isExpanded: $showExplanation) {
                Text("An SSH fingerprint uniquely identifies a server. When you connect for the first time, you should verify this fingerprint matches the one provided by your server administrator. This protects against connecting to the wrong server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }
            .font(.caption)
            .foregroundColor(.accentColor)
            .padding(.horizontal, 8)

            Spacer(minLength: 8)

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onComplete(false)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel connection")
                .accessibilityHint("Does not trust the server and cancels the connection")

                Spacer()

                Button("Trust") {
                    onComplete(true)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Trust this server")
                .accessibilityHint("Saves the server fingerprint and allows the connection to proceed")
            }
        }
        .padding(24)
        .frame(width: 400, height: 360)
    }
}

// MARK: - Host Key Changed View

/// Dialog presented when a server's SSH host key has changed since the last
/// connection. This is a potential security concern (MITM attack) and requires
/// explicit user acknowledgement.
struct HostKeyChangedView: View {
    /// The hostname or IP address of the server.
    let hostname: String

    /// The previously trusted fingerprint.
    let oldFingerprint: String

    /// The new fingerprint presented by the server.
    let newFingerprint: String

    /// Called with `true` if the user accepts the new key, `false` to disconnect.
    let onComplete: (Bool) -> Void

    @State private var showExplanation: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            // Danger icon
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 44))
                .foregroundColor(.red)
                .accessibilityHidden(true)

            // Title
            Text("Server Key Changed")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.red)

            // Warning description
            VStack(spacing: 8) {
                Text("The SSH key for this server has changed since your last connection.")
                    .font(.body)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(hostname)
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)
                }

                Text("This could indicate a security threat (man-in-the-middle attack) or that the server was reinstalled.")
                    .font(.callout)
                    .foregroundColor(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fontWeight(.medium)
                    .padding(.top, 2)
            }

            // Fingerprint comparison
            VStack(alignment: .leading, spacing: 10) {
                fingerprintRow(label: "Previous fingerprint:", fingerprint: oldFingerprint, color: .secondary)
                fingerprintRow(label: "New fingerprint:", fingerprint: newFingerprint, color: .red)
            }
            .padding(.horizontal, 8)

            // Explanation toggle
            DisclosureGroup("What does this mean?", isExpanded: $showExplanation) {
                Text("A changed host key means the server is presenting a different identity than before. This is expected if the server was reinstalled or its SSH keys were rotated. However, it can also indicate that someone is intercepting your connection. Contact your server administrator to verify the new key before accepting it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }
            .font(.caption)
            .foregroundColor(.accentColor)
            .padding(.horizontal, 8)

            Spacer(minLength: 8)

            // Buttons
            HStack(spacing: 12) {
                Button("Disconnect") {
                    onComplete(false)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Disconnect from server")
                .accessibilityHint("Rejects the new key and closes the connection")

                Spacer()

                Button("Accept New Key") {
                    onComplete(true)
                }
                .foregroundColor(.red)
                .accessibilityLabel("Accept the new server key")
                .accessibilityHint("Trusts the new fingerprint and allows the connection to proceed. Use with caution.")
            }
        }
        .padding(24)
        .frame(width: 420, height: 420)
    }

    // MARK: - Helpers

    private func fingerprintRow(label: String, fingerprint: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(fingerprint)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
                .accessibilityLabel("\(label) \(fingerprint)")
        }
    }
}

// MARK: - Async Continuation Helpers

extension UnknownHostView {
    /// Presents the unknown host prompt and suspends until the user responds.
    /// Returns `true` if the user chose to trust the server, `false` otherwise.
    @MainActor
    static func prompt(hostname: String, fingerprint: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let view = UnknownHostView(
                hostname: hostname,
                fingerprint: fingerprint,
                onComplete: { trusted in
                    continuation.resume(returning: trusted)
                }
            )

            let hostingController = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Unknown Server"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            window.level = .modalPanel

            let delegate = SheetWindowDelegate {
                continuation.resume(returning: false)
            }
            window.delegate = delegate

            // Keep the delegate alive by associating it with the window.
            objc_setAssociatedObject(window, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            NSApp.runModal(for: window)
            window.close()
        }
    }
}

extension HostKeyChangedView {
    /// Presents the host key changed prompt and suspends until the user responds.
    /// Returns `true` if the user accepted the new key, `false` otherwise.
    @MainActor
    static func prompt(hostname: String, oldFingerprint: String, newFingerprint: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let view = HostKeyChangedView(
                hostname: hostname,
                oldFingerprint: oldFingerprint,
                newFingerprint: newFingerprint,
                onComplete: { accepted in
                    continuation.resume(returning: accepted)
                }
            )

            let hostingController = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Server Key Changed"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            window.level = .modalPanel

            let delegate = SheetWindowDelegate {
                continuation.resume(returning: false)
            }
            window.delegate = delegate

            objc_setAssociatedObject(window, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            NSApp.runModal(for: window)
            window.close()
        }
    }
}

// MARK: - Sheet Window Delegate

/// NSWindowDelegate that invokes a closure when the user closes the window
/// via the title bar close button, and stops the modal session.
private final class SheetWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    private var hasFired = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
        guard !hasFired else { return }
        hasFired = true
        onClose()
    }
}
