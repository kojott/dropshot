import Foundation

// MARK: - Upload Status

enum UploadStatus: String, Codable, CaseIterable {
    case uploading = "uploading"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .uploading: return "Uploading"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

// MARK: - Upload Record

struct UploadRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String
    let serverPath: String
    let publicURL: String?
    let clipboardText: String
    let timestamp: Date
    let fileSize: Int64
    let uploadDuration: TimeInterval
    var status: UploadStatus
    var errorMessage: String?
    let serverConfigId: UUID

    init(
        id: UUID = UUID(),
        filename: String,
        serverPath: String,
        publicURL: String? = nil,
        clipboardText: String,
        timestamp: Date = Date(),
        fileSize: Int64,
        uploadDuration: TimeInterval = 0,
        status: UploadStatus = .uploading,
        errorMessage: String? = nil,
        serverConfigId: UUID
    ) {
        self.id = id
        self.filename = filename
        self.serverPath = serverPath
        self.publicURL = publicURL
        self.clipboardText = clipboardText
        self.timestamp = timestamp
        self.fileSize = fileSize
        self.uploadDuration = uploadDuration
        self.status = status
        self.errorMessage = errorMessage
        self.serverConfigId = serverConfigId
    }

    // MARK: - Computed Properties

    /// Returns the public URL if available, otherwise the server path.
    var copyableText: String {
        publicURL ?? serverPath
    }

    /// Human-readable file size (e.g. "1.2 MB", "340 KB").
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// Relative timestamp (e.g. "2 min ago", "yesterday", "Feb 14").
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    // MARK: - Factory Helpers

    /// Creates a new record marked as completed, filling in duration and final URL.
    func completed(duration: TimeInterval, publicURL: String? = nil) -> UploadRecord {
        var record = self
        record.status = .completed
        // Update duration and publicURL via a new instance since lets can't be mutated
        return UploadRecord(
            id: id,
            filename: filename,
            serverPath: serverPath,
            publicURL: publicURL ?? self.publicURL,
            clipboardText: publicURL ?? self.clipboardText,
            timestamp: timestamp,
            fileSize: fileSize,
            uploadDuration: duration,
            status: .completed,
            errorMessage: nil,
            serverConfigId: serverConfigId
        )
    }

    /// Creates a new record marked as failed with an error message.
    func failed(error: String, duration: TimeInterval = 0) -> UploadRecord {
        return UploadRecord(
            id: id,
            filename: filename,
            serverPath: serverPath,
            publicURL: publicURL,
            clipboardText: clipboardText,
            timestamp: timestamp,
            fileSize: fileSize,
            uploadDuration: duration,
            status: .failed,
            errorMessage: error,
            serverConfigId: serverConfigId
        )
    }
}
