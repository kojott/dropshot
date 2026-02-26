import Foundation
import AppKit
import os

// MARK: - Upload Manager

/// Central upload orchestrator responsible for enqueueing files, processing
/// uploads through the SFTP transport, managing clipboard output, and
/// coordinating with history and notification services.
///
/// Implemented as a `@MainActor` class (rather than a Swift actor) because it
/// publishes state that SwiftUI views observe via `@Published`.  The actual
/// SFTP work runs in structured `Task` blocks so the main thread is never
/// blocked.
@MainActor
final class UploadManager: ObservableObject {

    // MARK: - Singleton

    static let shared = UploadManager()

    // MARK: - Published State

    /// The record currently being uploaded, or `nil` when idle.
    @Published var currentUpload: UploadRecord?

    /// Records queued or in-flight for the current batch.
    @Published var uploadQueue: [UploadRecord] = []

    /// Whether an upload batch is currently being processed.
    @Published var isUploading: Bool = false

    /// Aggregate progress across the current batch (0.0 ... 1.0).
    @Published var overallProgress: Double = 0.0

    // MARK: - Configuration

    private let maxQueueSize = 50
    private let maxRetries = 2
    private let retryDelays: [UInt64] = [1_000_000_000, 3_000_000_000] // 1s, 3s in nanoseconds

    // MARK: - Internal State

    private var transport: (any SFTPTransport)?
    private var pendingFiles: [(url: URL, recordID: UUID)] = []
    private var isCancelled = false
    private var processingTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.dropshot", category: "UploadManager")

    // MARK: - Dependency Injection

    private let historyService: HistoryService
    private let notificationService: NotificationService

    // MARK: - Init

    init(
        transport: (any SFTPTransport)? = nil,
        historyService: HistoryService = .shared,
        notificationService: NotificationService = .shared
    ) {
        self.transport = transport
        self.historyService = historyService
        self.notificationService = notificationService
    }

    // MARK: - Public API

    /// Replaces the SFTP transport.  Primarily used for testing / dependency injection.
    func setTransport(_ transport: any SFTPTransport) {
        self.transport = transport
    }

    /// Loads the active server configuration from UserDefaults.
    ///
    /// The configuration is stored as JSON under the key
    /// `com.dropshot.serverConfig`.
    func getActiveServerConfig() -> ServerConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: "com.dropshot.serverConfig") else {
            logger.warning("No active server configuration found in UserDefaults.")
            return nil
        }
        do {
            let config = try JSONDecoder().decode(ServerConfiguration.self, from: data)
            return config
        } catch {
            logger.error("Failed to decode active server configuration: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Enqueue

    /// Validates each file, creates upload records, and starts queue processing.
    ///
    /// Files that fail validation (not found, too large, etc.) are rejected with
    /// an informational notification.  Processing begins automatically if not
    /// already running.
    func enqueueFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let settings = AppSettings.shared

        // Reject entire batch if it would exceed the maximum queue size.
        if pendingFiles.count + urls.count > maxQueueSize {
            logger.warning("Queue limit exceeded. Pending: \(self.pendingFiles.count), incoming: \(urls.count), max: \(self.maxQueueSize)")
            notificationService.showInfo(
                title: "Queue Full",
                body: "Cannot add \(urls.count) file(s). The upload queue is limited to \(maxQueueSize) items."
            )
            return
        }

        for url in urls {
            let validation = FileProcessor.isValidFile(at: url, maxSize: settings.maxFileSizeBytes)

            switch validation {
            case .valid(let fileSize):
                let originalFilename = url.lastPathComponent
                let ext = url.pathExtension
                let resolvedFilename = FileProcessor.resolveFilename(
                    original: originalFilename,
                    pattern: settings.filenamePattern,
                    extension: ext
                )
                let sanitizedFilename = FileProcessor.sanitize(resolvedFilename)

                guard let config = getActiveServerConfig() else {
                    logger.error("No active server configuration. Cannot enqueue \(originalFilename).")
                    notificationService.showInfo(
                        title: "No Server Configured",
                        body: "Please configure a server before uploading files."
                    )
                    return
                }

                let remotePath = config.remotePathWithTrailingSlash + sanitizedFilename
                let clipboardText = PathBuilder.buildClipboardText(
                    remotePath: config.remotePathWithTrailingSlash,
                    filename: sanitizedFilename,
                    baseURL: config.baseURL
                )

                let record = UploadRecord(
                    filename: sanitizedFilename,
                    serverPath: remotePath,
                    publicURL: config.baseURL != nil ? clipboardText : nil,
                    clipboardText: clipboardText,
                    fileSize: fileSize,
                    status: .uploading,
                    serverConfigId: config.id
                )

                pendingFiles.append((url: url, recordID: record.id))
                uploadQueue.append(record)
                logger.info("Enqueued \(sanitizedFilename) (\(fileSize) bytes)")

            case .notFound:
                logger.warning("File not found: \(url.path)")
                notificationService.showUploadFailure(
                    filename: url.lastPathComponent,
                    error: NSError(domain: "com.dropshot", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "File not found."
                    ])
                )

            case .isDirectory:
                logger.warning("Cannot upload directory: \(url.path)")
                notificationService.showInfo(
                    title: "Cannot Upload Directory",
                    body: "\(url.lastPathComponent) is a directory."
                )

            case .notReadable:
                logger.warning("File not readable: \(url.path)")
                notificationService.showUploadFailure(
                    filename: url.lastPathComponent,
                    error: NSError(domain: "com.dropshot", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "File is not readable."
                    ])
                )

            case .empty:
                logger.warning("File is empty: \(url.path)")
                notificationService.showInfo(
                    title: "Empty File",
                    body: "\(url.lastPathComponent) is empty and cannot be uploaded."
                )

            case .tooLarge(let size, let limit):
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let sizeStr = formatter.string(fromByteCount: size)
                let limitStr = formatter.string(fromByteCount: limit)
                logger.warning("File too large: \(url.lastPathComponent) (\(sizeStr), limit \(limitStr))")
                notificationService.showInfo(
                    title: "File Too Large",
                    body: "\(url.lastPathComponent) is \(sizeStr) (limit: \(limitStr))."
                )
            }
        }

        // Start processing if not already running.
        if !isUploading {
            startProcessing()
        }
    }

    // MARK: - Cancel

    /// Cancels the upload currently in progress.
    ///
    /// Attempts to remove any partially-uploaded remote file and marks the
    /// record as cancelled.
    func cancelCurrentUpload() async {
        isCancelled = true
        logger.info("Cancel requested for current upload.")

        guard let record = currentUpload, let transport = transport else { return }

        // Attempt to clean up the partial remote file.
        do {
            let exists = try await transport.fileExists(remotePath: record.serverPath)
            if exists {
                try await transport.removeFile(remotePath: record.serverPath)
                logger.info("Removed partial remote file: \(record.serverPath)")
            }
        } catch {
            logger.warning("Failed to remove partial remote file: \(error.localizedDescription)")
        }

        // Mark the record as cancelled.
        let cancelledRecord = UploadRecord(
            id: record.id,
            filename: record.filename,
            serverPath: record.serverPath,
            publicURL: record.publicURL,
            clipboardText: record.clipboardText,
            timestamp: record.timestamp,
            fileSize: record.fileSize,
            uploadDuration: 0,
            status: .cancelled,
            errorMessage: "Upload cancelled by user.",
            serverConfigId: record.serverConfigId
        )
        updateQueueRecord(cancelledRecord)
        currentUpload = cancelledRecord
        await historyService.updateRecord(cancelledRecord)
    }

    /// Cancels the current upload and clears the entire pending queue.
    func cancelAll() async {
        logger.info("Cancel all requested. Pending: \(self.pendingFiles.count)")
        await cancelCurrentUpload()

        // Mark all remaining queued records as cancelled.
        for i in uploadQueue.indices where uploadQueue[i].status == .uploading {
            uploadQueue[i].status = .cancelled
            uploadQueue[i].errorMessage = "Upload cancelled by user."
            await historyService.updateRecord(uploadQueue[i])
        }

        pendingFiles.removeAll()
        processingTask?.cancel()
        processingTask = nil
        isUploading = false
        overallProgress = 0.0
        currentUpload = nil
    }

    // MARK: - Queue Processing

    /// Kicks off a `Task` that drains `pendingFiles` one at a time.
    private func startProcessing() {
        guard !pendingFiles.isEmpty else { return }

        isUploading = true
        isCancelled = false
        overallProgress = 0.0

        processingTask = Task { [weak self] in
            await self?.processQueue()
        }
    }

    /// Sequentially processes every file in the pending queue.
    ///
    /// After all files are processed, copies the aggregated clipboard text and
    /// shows a batch notification when more than one file was uploaded.
    private func processQueue() async {
        let totalFiles = pendingFiles.count
        var completedCount = 0
        var successfulClipboardTexts: [String] = []

        while !pendingFiles.isEmpty {
            guard !isCancelled, !Task.isCancelled else {
                logger.info("Queue processing cancelled.")
                break
            }

            let (localURL, recordID) = pendingFiles.removeFirst()

            guard let recordIndex = uploadQueue.firstIndex(where: { $0.id == recordID }) else {
                logger.warning("Record \(recordID.uuidString) not found in queue; skipping.")
                completedCount += 1
                continue
            }

            let record = uploadQueue[recordIndex]
            currentUpload = record

            let result = await uploadSingleFile(
                localURL: localURL,
                record: record
            )

            switch result {
            case .success(let completedRecord):
                updateQueueRecord(completedRecord)
                currentUpload = completedRecord
                await historyService.addRecord(completedRecord)
                successfulClipboardTexts.append(completedRecord.clipboardText)
                logger.info("Upload succeeded: \(completedRecord.filename)")

                // For single-file batches, copy immediately and notify.
                if totalFiles == 1 {
                    copyToClipboard(completedRecord.clipboardText)
                    notificationService.showUploadSuccess(
                        filename: completedRecord.filename,
                        clipboardText: completedRecord.clipboardText
                    )
                }

            case .failure(let failedRecord):
                updateQueueRecord(failedRecord)
                currentUpload = failedRecord
                await historyService.addRecord(failedRecord)
                logger.error("Upload failed: \(failedRecord.filename) - \(failedRecord.errorMessage ?? "unknown")")

                // For single-file batches, notify immediately.
                if totalFiles == 1 {
                    let error = NSError(domain: "com.dropshot", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: failedRecord.errorMessage ?? "Upload failed."
                    ])
                    notificationService.showUploadFailure(
                        filename: failedRecord.filename,
                        error: error
                    )
                }
            }

            completedCount += 1
            overallProgress = Double(completedCount) / Double(totalFiles)
        }

        // Batch completion: copy all successful paths and show batch notification.
        if totalFiles > 1 {
            if !successfulClipboardTexts.isEmpty {
                copyMultipleToClipboard(successfulClipboardTexts)
            }
            notificationService.showBatchUploadSuccess(count: successfulClipboardTexts.count)
        }

        // Reset state.
        isUploading = false
        currentUpload = nil
        overallProgress = 1.0
        processingTask = nil
    }

    // MARK: - Single File Upload (with retry)

    /// Uploads a single file, retrying up to `maxRetries` times for connection
    /// errors with exponential backoff.
    ///
    /// - Returns: `.success` with the completed record, or `.failure` with the
    ///   failed record.
    private func uploadSingleFile(
        localURL: URL,
        record: UploadRecord
    ) async -> Result<UploadRecord, UploadRecord> {
        var lastError: Error?

        for attempt in 0...maxRetries {
            guard !isCancelled, !Task.isCancelled else {
                let cancelled = UploadRecord(
                    id: record.id,
                    filename: record.filename,
                    serverPath: record.serverPath,
                    publicURL: record.publicURL,
                    clipboardText: record.clipboardText,
                    timestamp: record.timestamp,
                    fileSize: record.fileSize,
                    uploadDuration: 0,
                    status: .cancelled,
                    errorMessage: "Upload cancelled by user.",
                    serverConfigId: record.serverConfigId
                )
                return .failure(cancelled)
            }

            // Wait before retrying (skip delay on first attempt).
            if attempt > 0 {
                let delayIndex = min(attempt - 1, retryDelays.count - 1)
                let delay = retryDelays[delayIndex]
                logger.info("Retrying upload of \(record.filename) (attempt \(attempt + 1)/\(self.maxRetries + 1)) after \(delay / 1_000_000_000)s")
                try? await Task.sleep(nanoseconds: delay)
            }

            do {
                let completedRecord = try await performUpload(
                    localURL: localURL,
                    record: record
                )
                return .success(completedRecord)
            } catch {
                lastError = error
                logger.error("Upload attempt \(attempt + 1) failed for \(record.filename): \(error.localizedDescription)")

                // Only retry on connection-related errors.
                if !isRetryableError(error) {
                    break
                }
            }
        }

        // All attempts exhausted.
        let errorMessage = lastError?.localizedDescription ?? "Unknown error"
        let failedRecord = record.failed(error: errorMessage)
        return .failure(failedRecord)
    }

    /// Executes the actual SFTP upload for a single file.
    ///
    /// Steps:
    /// 1. Ensure the transport is connected.
    /// 2. Handle duplicates on the remote server per settings.
    /// 3. Upload the file with progress tracking.
    /// 4. Verify the uploaded file exists on the server.
    /// 5. Build and return the completed record.
    private func performUpload(
        localURL: URL,
        record: UploadRecord
    ) async throws -> UploadRecord {
        guard let config = getActiveServerConfig() else {
            throw SFTPError.connectionFailed("No active server configuration.")
        }

        // Ensure we have a transport.
        guard let transport = transport else {
            throw SFTPError.connectionFailed("SFTP transport not initialized.")
        }

        // Connect if needed.
        let connected = await transport.isConnected
        if !connected {
            logger.info("Connecting to \(config.host):\(config.port)...")
            try await transport.connect(config: config)
            logger.info("Connected to \(config.host).")
        }

        // Determine the final remote path, handling duplicates.
        let settings = AppSettings.shared
        var finalRemotePath = record.serverPath
        var finalFilename = record.filename

        if settings.duplicateHandling == .appendSuffix {
            var suffix = 0
            while try await transport.fileExists(remotePath: finalRemotePath) {
                suffix += 1
                finalFilename = FileProcessor.appendSuffix(record.filename, suffix: suffix)
                finalRemotePath = config.remotePathWithTrailingSlash + finalFilename
                logger.info("Duplicate found; trying \(finalFilename)")

                // Safety valve to prevent infinite loop.
                if suffix > 999 {
                    throw SFTPError.permissionDenied("Could not find a unique filename after 999 attempts.")
                }
            }
        }

        // Upload.
        let startTime = CFAbsoluteTimeGetCurrent()

        let uploadResult = try await transport.upload(
            localPath: localURL,
            remotePath: finalRemotePath,
            progress: { [weak self] bytesUploaded, totalBytes in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    guard self != nil else { return }
                    // Per-file progress is not published separately; overall
                    // progress is updated at the batch level in processQueue.
                }
            }
        )

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // Verify the file was uploaded successfully.
        let exists = try await transport.fileExists(remotePath: finalRemotePath)
        if !exists {
            throw SFTPError.transferInterrupted(progress: 1.0)
        }

        logger.info("Verified remote file exists: \(finalRemotePath)")

        // Build final clipboard text using the (possibly deduplicated) filename.
        let clipboardText = PathBuilder.buildClipboardText(
            remotePath: config.remotePathWithTrailingSlash,
            filename: finalFilename,
            baseURL: config.baseURL
        )

        // Build the completed record.
        let completedRecord = UploadRecord(
            id: record.id,
            filename: finalFilename,
            serverPath: finalRemotePath,
            publicURL: config.baseURL != nil ? clipboardText : nil,
            clipboardText: clipboardText,
            timestamp: record.timestamp,
            fileSize: uploadResult.fileSize,
            uploadDuration: duration,
            status: .completed,
            errorMessage: nil,
            serverConfigId: record.serverConfigId
        )

        return completedRecord
    }

    // MARK: - Retry Logic

    /// Determines whether an error warrants an automatic retry.
    ///
    /// Connection, timeout, and transfer-interrupted errors are retryable.
    /// Authentication, permission, and disk-full errors are not.
    private func isRetryableError(_ error: Error) -> Bool {
        guard let sftpError = error as? SFTPError else {
            // Unknown errors are retried optimistically.
            return true
        }
        switch sftpError {
        case .connectionFailed, .hostUnreachable, .timeout, .transferInterrupted, .sftpSubsystemFailed:
            return true
        case .authenticationFailed, .permissionDenied, .hostKeyMismatch, .hostKeyUnknown,
             .diskFull, .pathNotFound, .cancelled:
            return false
        }
    }

    // MARK: - Clipboard

    /// Copies a single string to the system pasteboard.
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("Copied to clipboard: \(text)")
    }

    /// Copies multiple strings to the system pasteboard, joined by newlines.
    private func copyMultipleToClipboard(_ texts: [String]) {
        let joined = texts.joined(separator: "\n")
        copyToClipboard(joined)
    }

    // MARK: - Queue Record Helpers

    /// Updates a record inside `uploadQueue` in place.
    private func updateQueueRecord(_ record: UploadRecord) {
        guard let index = uploadQueue.firstIndex(where: { $0.id == record.id }) else {
            return
        }
        uploadQueue[index] = record
    }
}
