import AppKit
import Combine
import SwiftUI
import os
import KeyboardShortcuts

// MARK: - Menu Bar Icon State

/// Tracks the visual state of the menu bar icon so the delegate can
/// coordinate animations and icon swaps without race conditions.
private enum MenuBarIconState: Equatable {
    case unconfigured
    case idle
    case uploading
    case success
    case error
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Status Bar

    private var statusItem: NSStatusItem!
    private var dragDestinationView: DragDestinationView!
    private var menu: NSMenu!

    // MARK: - Windows

    private var setupWizardWindow: NSWindow?
    private var preferencesWindow: NSWindow?

    // MARK: - Icon Animation

    private var iconState: MenuBarIconState = .idle
    private var uploadAnimationTimer: Timer?
    private var uploadAnimationFrame: Int = 0
    private var iconRevertWorkItem: DispatchWorkItem?

    // MARK: - Service References

    private let uploadManager = UploadManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let historyService = HistoryService.shared
    private let notificationService = NotificationService.shared
    private let permissionService = PermissionService.shared

    // MARK: - Observation

    private var isUploadingObservation: AnyCancellable?

    // MARK: - Logger

    private let logger = Logger(subsystem: "com.dropshot", category: "AppDelegate")

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("DropShot launching")

        setupStatusItem()
        buildMenu()
        setupNotifications()
        setupKeyboardShortcuts()
        startServices()
        observeUploadState()
        observeAppNotifications()

        // Initialize the transport on the upload manager.
        let transport = SystemSFTPTransport()
        uploadManager.setTransport(transport)

        // Show setup wizard on first launch.
        if !AppSettings.shared.hasCompletedSetup {
            logger.info("First launch detected, showing setup wizard")
            showSetupWizard()
        } else {
            updateIconForCurrentState()
        }

        logger.info("DropShot launch complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("DropShot terminating")
        uploadAnimationTimer?.invalidate()
        uploadAnimationTimer = nil
        networkMonitor.stopMonitoring()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Status Item Setup

    /// Creates the NSStatusItem with a custom drag-destination view overlaid
    /// on the standard button so the user can drop files directly onto the
    /// menu bar icon.
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else {
            logger.error("Failed to obtain status item button")
            return
        }

        // Set the default icon.
        let image = NSImage(
            systemSymbolName: "square.and.arrow.up",
            accessibilityDescription: "DropShot"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly

        // Overlay the drag-destination view on top of the button so it
        // intercepts drag events while still allowing normal clicks through
        // to the menu.
        dragDestinationView = DragDestinationView(frame: button.bounds)
        dragDestinationView.autoresizingMask = [.width, .height]
        dragDestinationView.onDragEntered = { [weak self] in
            self?.handleDragEntered()
        }
        dragDestinationView.onDragExited = { [weak self] in
            self?.handleDragExited()
        }
        dragDestinationView.onFilesDropped = { [weak self] urls in
            self?.handleFileDrop(urls)
        }
        button.addSubview(dragDestinationView)
    }

    // MARK: - Menu Building

    /// Constructs the dropdown menu. The menu is rebuilt every time it opens
    /// via the NSMenuDelegate callback to reflect live state.
    private func buildMenu() {
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuildMenuItems()
    }

    /// Tears down and rebuilds every item in the menu from scratch.
    /// Called by `menuWillOpen(_:)` so the contents are always fresh.
    private func rebuildMenuItems() {
        menu.removeAllItems()

        // -- Server status --
        let statusItem = buildServerStatusItem()
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // -- Upload progress (if uploading) --
        if uploadManager.isUploading, let current = uploadManager.currentUpload {
            let progressItem = buildUploadProgressItem(for: current)
            menu.addItem(progressItem)
            menu.addItem(NSMenuItem.separator())
        }

        // -- Recent uploads --
        let recentItems = buildRecentUploadItems()
        if recentItems.isEmpty {
            let emptyItem = NSMenuItem(
                title: "No recent uploads",
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false

            let hintItem = NSMenuItem(
                title: "Drop a file on this icon to upload",
                action: nil,
                keyEquivalent: ""
            )
            hintItem.isEnabled = false
            hintItem.indentationLevel = 1

            menu.addItem(emptyItem)
            menu.addItem(hintItem)
        } else {
            let headerItem = NSMenuItem(
                title: "Recent Uploads",
                action: nil,
                keyEquivalent: ""
            )
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            for item in recentItems {
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // -- Screenshot capture --
        let screenshotItem = NSMenuItem(
            title: "Capture Screenshot...",
            action: #selector(captureScreenshot),
            keyEquivalent: ""
        )
        screenshotItem.target = self
        screenshotItem.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        menu.addItem(screenshotItem)

        // -- Upload from clipboard --
        let clipboardItem = NSMenuItem(
            title: "Upload from Clipboard",
            action: #selector(uploadFromClipboard),
            keyEquivalent: ""
        )
        clipboardItem.target = self
        clipboardItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        // Disable if clipboard has no files or images.
        clipboardItem.isEnabled = clipboardHasUploadableContent()
        menu.addItem(clipboardItem)

        menu.addItem(NSMenuItem.separator())

        // -- Preferences --
        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showPreferencesAction),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        preferencesItem.keyEquivalentModifierMask = .command
        menu.addItem(preferencesItem)

        // -- About --
        let aboutItem = NSMenuItem(
            title: "About DropShot",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // -- Quit --
        let quitItem = NSMenuItem(
            title: "Quit DropShot",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
    }

    // MARK: - Menu Item Builders

    /// Builds the server connection status menu item. Shows whether the app
    /// is configured, connected, and the network state.
    private func buildServerStatusItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false

        guard AppSettings.shared.hasCompletedSetup else {
            item.title = "Not Configured"
            item.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
            return item
        }

        guard let config = uploadManager.getActiveServerConfig() else {
            item.title = "No Server Selected"
            item.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
            return item
        }

        if !networkMonitor.isConnected {
            item.title = "\(config.name) -- Offline"
            item.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: nil)
            return item
        }

        item.title = "\(config.name) -- Ready"
        item.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        return item
    }

    /// Builds a menu item showing the current upload's progress using an
    /// embedded SwiftUI view via NSHostingView.
    private func buildUploadProgressItem(for record: UploadRecord) -> NSMenuItem {
        let item = NSMenuItem()

        let progressView = UploadProgressMenuView(
            filename: record.filename,
            progress: uploadManager.overallProgress,
            onCancel: { [weak self] in
                Task { @MainActor in
                    await self?.uploadManager.cancelCurrentUpload()
                }
            }
        )

        let hostingView = NSHostingView(rootView: progressView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 52)
        item.view = hostingView

        return item
    }

    /// Builds menu items for the most recent uploads from history.
    /// Each item copies the public URL or path when clicked.
    private func buildRecentUploadItems() -> [NSMenuItem] {
        // HistoryService is an actor, so we need to use a cached snapshot.
        // We refresh this cache each time the menu opens.
        return cachedRecentRecords.map { record in
            let item = NSMenuItem(
                title: record.filename,
                action: #selector(copyUploadURL(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = record.clipboardText
            item.indentationLevel = 1

            // Icon based on status.
            switch record.status {
            case .completed:
                item.image = NSImage(
                    systemSymbolName: "checkmark.circle",
                    accessibilityDescription: "Completed"
                )
            case .failed:
                item.image = NSImage(
                    systemSymbolName: "xmark.circle",
                    accessibilityDescription: "Failed"
                )
            case .uploading:
                item.image = NSImage(
                    systemSymbolName: "arrow.up.circle",
                    accessibilityDescription: "Uploading"
                )
            case .cancelled:
                item.image = NSImage(
                    systemSymbolName: "minus.circle",
                    accessibilityDescription: "Cancelled"
                )
            }

            // Subtitle with relative timestamp and file size.
            item.toolTip = "\(record.formattedFileSize) -- \(record.formattedTimestamp)\n\(record.copyableText)"

            return item
        }
    }

    // MARK: - Recent Records Cache

    /// A snapshot of recent records fetched from the actor-isolated
    /// HistoryService before the menu opens. Refreshed in `menuWillOpen(_:)`.
    private var cachedRecentRecords: [UploadRecord] = []

    /// Asynchronously refreshes the cached recent records from the
    /// HistoryService actor.
    private func refreshRecentRecordsCache() async {
        cachedRecentRecords = await historyService.recentRecords(limit: 10)
    }

    // MARK: - Menu Actions

    @objc private func copyUploadURL(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        logger.info("Copied URL to clipboard: \(urlString)")

        // Brief visual feedback on the icon.
        flashIcon(state: .success)
    }

    @objc private func captureScreenshot() {
        logger.info("Screenshot capture requested from menu")
        Task {
            await ScreenshotManager.shared.captureRegion()
        }
    }

    @objc private func uploadFromClipboard() {
        logger.info("Upload from clipboard requested")
        handleClipboardUpload()
    }

    @objc func showPreferencesAction() {
        showPreferences()
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        logger.info("Quit requested by user")
        NSApp.terminate(nil)
    }

    // MARK: - File Drop Handling

    /// Validates and enqueues dropped file URLs for upload.
    func handleFileDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        logger.info("Received \(urls.count) file(s) via drag-and-drop")

        guard AppSettings.shared.hasCompletedSetup else {
            logger.warning("Cannot upload: setup not completed")
            notificationService.showInfo(
                title: "Setup Required",
                body: "Please complete the setup wizard before uploading files."
            )
            showSetupWizard()
            return
        }

        guard networkMonitor.isConnected else {
            logger.warning("Cannot upload: no network connection")
            notificationService.showInfo(
                title: "No Network Connection",
                body: "Cannot upload files while offline. Please check your network connection."
            )
            return
        }

        guard uploadManager.getActiveServerConfig() != nil else {
            logger.warning("Cannot upload: no active server configuration")
            notificationService.showInfo(
                title: "No Server Configured",
                body: "Please configure a server in Preferences before uploading."
            )
            showPreferences()
            return
        }

        // Resolve security-scoped bookmarks if necessary (for sandboxed access).
        let resolvedURLs = urls.compactMap { url -> URL? in
            guard url.isFileURL else {
                logger.warning("Ignoring non-file URL: \(url.absoluteString)")
                return nil
            }
            return url
        }

        guard !resolvedURLs.isEmpty else {
            logger.warning("No valid file URLs after filtering")
            return
        }

        uploadManager.enqueueFiles(resolvedURLs)
    }

    // MARK: - Clipboard Upload

    /// Checks whether the system clipboard contains file URLs or image data
    /// that can be uploaded.
    private func clipboardHasUploadableContent() -> Bool {
        let pasteboard = NSPasteboard.general

        // Check for file URLs.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            return true
        }

        // Check for image data (PNG, TIFF, JPEG).
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in imageTypes {
            if pasteboard.data(forType: type) != nil {
                return true
            }
        }

        return false
    }

    /// Extracts uploadable content from the clipboard and enqueues it.
    private func handleClipboardUpload() {
        let pasteboard = NSPasteboard.general

        // Attempt to read file URLs first.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            handleFileDrop(urls)
            return
        }

        // Attempt to read image data from the clipboard.
        if let pngData = pasteboard.data(forType: .png) {
            uploadClipboardImage(data: pngData, extension: "png")
            return
        }
        if let tiffData = pasteboard.data(forType: .tiff) {
            // Convert TIFF to PNG for smaller file size and broader compatibility.
            if let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                uploadClipboardImage(data: pngData, extension: "png")
                return
            }
        }

        logger.info("No uploadable content found on clipboard")
        notificationService.showInfo(
            title: "Nothing to Upload",
            body: "The clipboard does not contain any files or images."
        )
    }

    /// Writes clipboard image data to a temporary file and enqueues it for upload.
    private func uploadClipboardImage(data: Data, extension ext: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "clipboard-\(ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withFullTime])).\(ext)"
            .replacingOccurrences(of: ":", with: "-")
        let tempURL = tempDir.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL, options: .atomic)
            logger.info("Wrote clipboard image to temp file: \(tempURL.path)")
            handleFileDrop([tempURL])
        } catch {
            logger.error("Failed to write clipboard image to temp file: \(error.localizedDescription)")
            notificationService.showInfo(
                title: "Clipboard Error",
                body: "Failed to process clipboard image: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Notifications Setup

    /// Sets up notification categories and requests permission.
    private func setupNotifications() {
        notificationService.setupNotificationCategories()
        Task {
            await notificationService.requestPermission()
        }
    }

    // MARK: - Keyboard Shortcuts

    /// Registers global keyboard shortcuts for screenshot capture and
    /// clipboard upload.
    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .captureScreenshot) { [weak self] in
            Task { @MainActor [weak self] in
                self?.captureScreenshot()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .uploadClipboard) { [weak self] in
            Task { @MainActor [weak self] in
                self?.uploadFromClipboard()
            }
        }
    }

    // MARK: - Service Startup

    /// Initializes long-running services that should start at launch.
    private func startServices() {
        networkMonitor.startMonitoring()
        logger.info("Network monitoring started")

        Task {
            do {
                try await historyService.load()
                logger.info("Upload history loaded")
            } catch {
                logger.error("Failed to load upload history: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Upload State Observation

    /// Subscribes to the UploadManager's `isUploading` publisher so the
    /// menu bar icon animates while an upload is in progress and flashes
    /// on completion.
    private func observeUploadState() {
        isUploadingObservation = uploadManager.$isUploading
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.uploadStateDidChange()
            }
    }

    /// Called when UploadManager's isUploading state changes to start or
    /// stop the icon animation.
    private func uploadStateDidChange() {
        if uploadManager.isUploading {
            startUploadAnimation()
        } else {
            stopUploadAnimation()

            // Check if the last upload succeeded or failed to flash the
            // appropriate icon.
            if let lastRecord = uploadManager.uploadQueue.last {
                switch lastRecord.status {
                case .completed:
                    flashIcon(state: .success)
                case .failed:
                    flashIcon(state: .error)
                default:
                    setIcon(for: .idle)
                }
            } else {
                setIcon(for: .idle)
            }
        }
    }

    // MARK: - App Notification Observers

    /// Subscribes to internal NSNotification events posted by other services
    /// (e.g., NotificationService action handlers).
    private func observeAppNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPreferencesNotification),
            name: .dropShotOpenPreferences,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRetryUploadNotification),
            name: .dropShotRetryUpload,
            object: nil
        )
    }

    @objc private func handleOpenPreferencesNotification() {
        showPreferences()
    }

    @objc private func handleRetryUploadNotification() {
        logger.info("Retry upload requested via notification action")
        // Re-enqueue the most recent failed upload if available.
        Task {
            let recent = await historyService.recentRecords(limit: 1)
            if let lastRecord = recent.first,
               lastRecord.status == .failed {
                logger.info("Retrying upload for: \(lastRecord.filename)")
                // Note: retry from server path is not directly possible since
                // we need the local file. Show preferences so the user can
                // re-upload manually.
                showPreferences()
            }
        }
    }

    // MARK: - Menu Bar Icon States

    /// Updates the menu bar icon to reflect the current app state.
    private func updateIconForCurrentState() {
        if !AppSettings.shared.hasCompletedSetup {
            setIcon(for: .unconfigured)
        } else if uploadManager.isUploading {
            startUploadAnimation()
        } else {
            setIcon(for: .idle)
        }
    }

    /// Sets the menu bar icon image based on the given state.
    private func setIcon(for state: MenuBarIconState) {
        guard let button = statusItem?.button else { return }
        iconState = state

        let symbolName: String
        let alpha: CGFloat

        switch state {
        case .unconfigured:
            symbolName = "square.and.arrow.up"
            alpha = 0.5
        case .idle:
            symbolName = "square.and.arrow.up"
            alpha = 1.0
        case .uploading:
            symbolName = "arrow.up.circle"
            alpha = 1.0
        case .success:
            symbolName = "checkmark.circle.fill"
            alpha = 1.0
        case .error:
            symbolName = "exclamationmark.circle.fill"
            alpha = 1.0
        }

        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "DropShot"
        )
        image?.isTemplate = true
        button.image = image
        button.alphaValue = alpha
        button.appearsDisabled = (state == .unconfigured)
    }

    /// Starts a repeating timer that cycles the icon between upload animation
    /// frames while files are being uploaded.
    private func startUploadAnimation() {
        guard uploadAnimationTimer == nil else { return }
        iconState = .uploading
        uploadAnimationFrame = 0

        // If Reduce Motion is enabled, show a static upload icon instead of cycling.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setIcon(for: .uploading)
            return
        }

        let uploadSymbols = [
            "arrow.up.circle",
            "arrow.up.circle.fill",
            "icloud.and.arrow.up",
            "icloud.and.arrow.up.fill"
        ]

        uploadAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let button = self.statusItem?.button else { return }
                let symbolName = uploadSymbols[self.uploadAnimationFrame % uploadSymbols.count]
                let image = NSImage(
                    systemSymbolName: symbolName,
                    accessibilityDescription: "Uploading"
                )
                image?.isTemplate = true
                button.image = image
                button.alphaValue = 1.0
                self.uploadAnimationFrame += 1
            }
        }
    }

    /// Stops the upload animation timer and reverts the icon.
    private func stopUploadAnimation() {
        uploadAnimationTimer?.invalidate()
        uploadAnimationTimer = nil
        uploadAnimationFrame = 0
    }

    /// Briefly flashes the icon to a success or error state, then reverts to idle.
    private func flashIcon(state: MenuBarIconState) {
        // Cancel any pending revert.
        iconRevertWorkItem?.cancel()

        setIcon(for: state)

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.setIcon(for: .idle)
            }
        }
        iconRevertWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    // MARK: - Drag Feedback

    /// Called when a drag operation enters the status item's bounds.
    private func handleDragEntered() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(
            systemSymbolName: "arrow.down.circle.fill",
            accessibilityDescription: "Drop to upload"
        )
        image?.isTemplate = true
        button.image = image
    }

    /// Called when a drag operation exits the status item's bounds.
    private func handleDragExited() {
        updateIconForCurrentState()
    }

    // MARK: - Window Management

    /// Opens the Preferences window. If already visible, brings it to front.
    func showPreferences() {
        if let existing = preferencesWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DropShot Preferences"
        window.contentView = NSHostingView(rootView: PreferencesView())
        window.contentMinSize = NSSize(width: 480, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        preferencesWindow = window
    }

    /// Opens the setup wizard window. If already visible, brings it to front.
    func showSetupWizard() {
        if let existing = setupWizardWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onComplete: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.setupWizardWindow?.close()
            self.setupWizardWindow = nil
            self.updateIconForCurrentState()
            self.logger.info("Setup wizard completed")
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to DropShot"
        window.contentView = NSHostingView(rootView: SetupWizardView(onComplete: onComplete))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupWizardWindow = window
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Refresh the upload state for the icon (in case Combine observation
        // missed an edge case).
        uploadStateDidChange()

        // Refresh the recent records cache asynchronously, then rebuild.
        // Since menuWillOpen is synchronous, we use the last cached records
        // for this opening and trigger a refresh for next time.
        Task {
            await refreshRecentRecordsCache()
        }

        // Rebuild menu items synchronously with whatever we have cached.
        rebuildMenuItems()
    }

    func menuDidClose(_ menu: NSMenu) {
        // No-op; included for completeness.
    }
}

// MARK: - Drag Destination View

/// A transparent NSView that registers for file URL drags and forwards
/// accepted drops to its closure callbacks. Overlaid on the NSStatusItem
/// button to add drag-and-drop support to the menu bar icon.
final class DragDestinationView: NSView {

    // MARK: - Callbacks

    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?

    // MARK: - State

    private var isDragHighlighted = false

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(in: sender) else {
            return []
        }
        isDragHighlighted = true
        onDragEntered?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(in: sender) else {
            return []
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
        onDragExited?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return hasFileURLs(in: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false
        onDragExited?()

        guard let urls = extractFileURLs(from: sender), !urls.isEmpty else {
            return false
        }

        onFilesDropped?(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
    }

    // MARK: - Hit Testing

    /// Allow clicks to pass through to the underlying button so the menu
    /// still opens on normal clicks. Only intercept drag operations.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil for mouse clicks so they fall through to the
        // NSStatusBarButton underneath. Drag operations use the
        // NSDraggingDestination protocol methods directly and do not
        // rely on hitTest.
        return nil
    }

    // MARK: - Helpers

    /// Checks whether the dragging pasteboard contains at least one file URL.
    private func hasFileURLs(in info: NSDraggingInfo) -> Bool {
        let pasteboard = info.draggingPasteboard
        guard let types = pasteboard.types, types.contains(.fileURL) else {
            return false
        }
        return true
    }

    /// Extracts all file URLs from the dragging pasteboard.
    private func extractFileURLs(from info: NSDraggingInfo) -> [URL]? {
        let pasteboard = info.draggingPasteboard

        guard let items = pasteboard.pasteboardItems else {
            return nil
        }

        var urls: [URL] = []
        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString),
               url.isFileURL {
                urls.append(url)
            }
        }

        return urls.isEmpty ? nil : urls
    }
}

// MARK: - Upload Progress Menu View

/// A small SwiftUI view embedded in the NSMenu via NSHostingView that shows
/// the current upload filename, a progress bar, and a cancel button.
private struct UploadProgressMenuView: View {
    let filename: String
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
                Text(filename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Cancel upload")
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text("\(Int(progress * 100))% uploaded")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 280)
    }
}

