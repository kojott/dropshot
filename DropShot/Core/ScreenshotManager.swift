import Foundation
import AppKit
import os

// MARK: - Screenshot Manager

/// Manages macOS screenshot capture using the system `screencapture` CLI tool
/// and feeds the resulting images into the upload pipeline.
///
/// All public methods run on `@MainActor` because they interact with UI state
/// (permission dialogs) and ultimately feed into `UploadManager` which is also
/// `@MainActor`-isolated.
@MainActor
final class ScreenshotManager {

    // MARK: - Singleton

    static let shared = ScreenshotManager()

    // MARK: - Dependencies

    private let uploadManager: UploadManager
    private let logger = Logger(subsystem: "com.dropshot", category: "ScreenshotManager")

    // MARK: - Init

    init(uploadManager: UploadManager = .shared) {
        self.uploadManager = uploadManager
    }

    // MARK: - Public API

    /// Captures an interactive region screenshot (crosshair selection).
    ///
    /// The user draws a rectangle on screen.  If they press Escape the
    /// operation is silently cancelled.  A successful capture is automatically
    /// enqueued for upload.
    func captureRegion() async {
        guard checkScreenRecordingPermission() else { return }

        let tempURL = makeTempFileURL()
        logger.info("Starting region capture to \(tempURL.path)")

        do {
            let created = try await runScreencapture(arguments: ["-i", "-x", tempURL.path])
            if created {
                logger.info("Region capture saved to \(tempURL.path)")
                uploadManager.enqueueFiles([tempURL])
            } else {
                logger.info("Region capture cancelled by user.")
                // Clean up the temp file path (it may not exist if user cancelled).
                cleanUpTempFile(at: tempURL)
            }
        } catch {
            logger.error("Region capture failed: \(error.localizedDescription)")
            cleanUpTempFile(at: tempURL)
        }
    }

    /// Captures the entire screen (all displays).
    ///
    /// The capture happens immediately without user interaction.  The resulting
    /// image is automatically enqueued for upload.
    func captureFullScreen() async {
        guard checkScreenRecordingPermission() else { return }

        let tempURL = makeTempFileURL()
        logger.info("Starting full-screen capture to \(tempURL.path)")

        do {
            let created = try await runScreencapture(arguments: ["-x", tempURL.path])
            if created {
                logger.info("Full-screen capture saved to \(tempURL.path)")
                uploadManager.enqueueFiles([tempURL])
            } else {
                logger.error("Full-screen capture produced no file.")
                cleanUpTempFile(at: tempURL)
            }
        } catch {
            logger.error("Full-screen capture failed: \(error.localizedDescription)")
            cleanUpTempFile(at: tempURL)
        }
    }

    // MARK: - screencapture Subprocess

    /// Runs `/usr/sbin/screencapture` with the given arguments and returns
    /// `true` if the output file was created on disk.
    ///
    /// The method launches the process asynchronously and waits for it to
    /// terminate without blocking the main thread.
    ///
    /// - Parameter arguments: Command-line flags and the output file path.
    /// - Returns: `true` if the expected output file exists after the process
    ///   exits; `false` if the user cancelled or the file was not created.
    /// - Throws: If the process cannot be launched.
    private func runScreencapture(arguments: [String]) async throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments

        // Suppress stdout/stderr to avoid polluting the console.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] terminatedProcess in
                let exitCode = terminatedProcess.terminationStatus
                self?.logger.info("screencapture exited with code \(exitCode)")

                // Determine whether the file was created.  screencapture
                // returns exit code 0 even when the user cancels (presses
                // Escape) during interactive capture, so the only reliable
                // signal is whether the output file exists.
                guard let outputPath = arguments.last else {
                    continuation.resume(returning: false)
                    return
                }

                let fileExists = FileManager.default.fileExists(atPath: outputPath)
                continuation.resume(returning: fileExists)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Permission Check

    /// Checks whether the app has screen recording permission.
    ///
    /// On macOS 10.15+ a screen recording consent dialog is triggered by
    /// attempting to capture screen contents via `CGWindowListCreateImage`.
    /// If the app lacks permission the system returns a 1x1 image or nil.
    ///
    /// When permission is missing this method shows a guidance dialog
    /// directing the user to System Settings and returns `false`.
    private func checkScreenRecordingPermission() -> Bool {
        // Attempt a minimal screen capture to probe permission status.
        // CGWindowListCreateImage returns nil or a tiny fallback image
        // when the app is not authorized.
        let testImage = CGWindowListCreateImage(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            .optionOnScreenOnly,
            kCGNullWindowID,
            .nominalResolution
        )

        if let image = testImage, image.width > 0, image.height > 0 {
            return true
        }

        logger.warning("Screen recording permission not granted.")
        showPermissionGuidanceDialog()
        return false
    }

    /// Presents a modal alert explaining that screen recording permission is
    /// required and offers to open System Settings.
    private func showPermissionGuidanceDialog() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
            DropShot needs screen recording permission to capture screenshots.

            Please open System Settings > Privacy & Security > Screen Recording \
            and enable DropShot.

            You may need to restart the app after granting permission.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Open the Screen Recording pane in System Settings.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Temp File Management

    /// Creates a unique temporary file URL for a screenshot.
    ///
    /// Format: `{tempDir}/dropshot-{uuid}.png`
    private func makeTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "dropshot-\(UUID().uuidString).png"
        return tempDir.appendingPathComponent(filename)
    }

    /// Removes a temporary file if it exists.  Failures are logged but not thrown.
    private func cleanUpTempFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            logger.info("Cleaned up temp file: \(url.path)")
        } catch {
            logger.warning("Failed to clean up temp file \(url.path): \(error.localizedDescription)")
        }
    }
}
