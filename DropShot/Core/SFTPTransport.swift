import Foundation

// MARK: - Upload Progress

/// Progress callback: bytesUploaded, totalBytes
typealias UploadProgressHandler = (Int64, Int64) -> Void

// MARK: - Upload Result

/// Result of a successful upload operation.
struct UploadResult: Sendable {
    let remoteFilePath: String
    let fileSize: Int64
    let duration: TimeInterval
}

// MARK: - SFTP Errors

/// Errors specific to SFTP operations.
enum SFTPError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case permissionDenied(String)
    case hostUnreachable(String)
    case hostKeyMismatch(oldKey: String, newKey: String)
    case hostKeyUnknown(fingerprint: String)
    case sftpSubsystemFailed
    case transferInterrupted(progress: Double)
    case diskFull
    case pathNotFound(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail):
            return "Connection failed: \(detail)"
        case .authenticationFailed(let detail):
            return "Authentication failed: \(detail)"
        case .permissionDenied(let detail):
            return "Permission denied: \(detail)"
        case .hostUnreachable(let host):
            return "Host unreachable: \(host)"
        case .hostKeyMismatch(let oldKey, let newKey):
            return "Host key mismatch. Previous key: \(oldKey), new key: \(newKey)"
        case .hostKeyUnknown(let fingerprint):
            return "Unknown host key with fingerprint: \(fingerprint)"
        case .sftpSubsystemFailed:
            return "The SFTP subsystem failed to start on the remote server."
        case .transferInterrupted(let progress):
            let percent = Int(progress * 100)
            return "File transfer was interrupted at \(percent)% completion."
        case .diskFull:
            return "The remote disk is full."
        case .pathNotFound(let path):
            return "Remote path not found: \(path)"
        case .timeout:
            return "The connection timed out."
        case .cancelled:
            return "The operation was cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .connectionFailed:
            return "Check that the server address and port are correct, and that the server is running."
        case .authenticationFailed:
            return "Verify your username and credentials. If using an SSH key, ensure it is valid and the public key is authorized on the server."
        case .permissionDenied:
            return "Check that your user account has write permission to the remote directory."
        case .hostUnreachable:
            return "Verify the hostname or IP address. Check your network connection and firewall settings."
        case .hostKeyMismatch:
            return "This may indicate a man-in-the-middle attack, or the server was reinstalled. Verify the new key with your server administrator before accepting it."
        case .hostKeyUnknown:
            return "Verify this fingerprint with your server administrator. If it matches, accept the key to continue."
        case .sftpSubsystemFailed:
            return "Ensure the SFTP subsystem is enabled in the server's SSH configuration (usually /etc/ssh/sshd_config)."
        case .transferInterrupted:
            return "Check your network connection and try uploading again. The partial file may need to be removed from the server."
        case .diskFull:
            return "Free up space on the remote server or choose a different upload directory."
        case .pathNotFound:
            return "Verify the remote path exists and is spelled correctly. You may need to create the directory first."
        case .timeout:
            return "Check your network connection. The server may be slow to respond or behind a firewall. Try increasing the timeout in settings."
        case .cancelled:
            return nil
        }
    }
}

// MARK: - SFTP Transport Protocol

/// Protocol for SFTP transport implementations.
///
/// Conforming types must be actors to ensure thread-safe access to connection state.
protocol SFTPTransport: Actor {
    /// Establishes a connection to the server using the given configuration.
    func connect(config: ServerConfiguration) async throws

    /// Uploads a local file to the remote server.
    ///
    /// - Parameters:
    ///   - localPath: URL of the local file to upload.
    ///   - remotePath: Full remote destination path including filename.
    ///   - progress: Optional callback invoked with bytes uploaded and total bytes.
    /// - Returns: An ``UploadResult`` describing the completed transfer.
    func upload(localPath: URL, remotePath: String, progress: UploadProgressHandler?) async throws -> UploadResult

    /// Checks whether a file exists at the given remote path.
    func fileExists(remotePath: String) async throws -> Bool

    /// Removes a file at the given remote path.
    func removeFile(remotePath: String) async throws

    /// Disconnects from the remote server.
    func disconnect() async

    /// Cancels any in-flight upload by terminating the underlying process.
    func cancelUpload() async

    /// Whether the transport is currently connected.
    var isConnected: Bool { get }

    /// Tests the connection with the given configuration and returns a server info string.
    func testConnection(config: ServerConfiguration) async throws -> String
}
