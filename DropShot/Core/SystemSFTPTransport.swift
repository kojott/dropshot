import Foundation
import os

// MARK: - System SFTP Transport

/// SFTP transport implementation using the system `/usr/bin/sftp` and `/usr/bin/ssh` binaries
/// via Foundation's `Process`. Uses SSH ControlMaster for connection reuse across operations.
actor SystemSFTPTransport: SFTPTransport {

    // MARK: - Properties

    private var config: ServerConfiguration?
    private var controlPath: String?
    private(set) var isConnected: Bool = false

    private let logger = Logger(subsystem: "com.dropshot", category: "SFTPTransport")

    /// Threshold in bytes above which progress estimation is enabled during uploads.
    private let progressEstimationThreshold: Int64 = 1_048_576 // 1 MB

    /// Interval between synthetic progress updates during upload.
    private let progressUpdateInterval: TimeInterval = 0.25

    // MARK: - Connection

    func connect(config: ServerConfiguration) async throws {
        // If already connected to this host, check if the socket is still alive.
        if isConnected, let existingPath = controlPath, self.config == config {
            let checkResult = try await runProcess(
                "/usr/bin/ssh",
                arguments: ["-O", "check"] + buildSSHArguments(for: config, controlPath: existingPath) + ["\(config.username)@\(config.host)"],
                input: nil
            )
            if checkResult.exitCode == 0 {
                logger.debug("Existing ControlMaster connection still alive")
                return
            }
            // Socket is stale; clean up and reconnect.
            logger.info("Stale ControlMaster socket, reconnecting")
            await disconnect()
        } else if isConnected {
            await disconnect()
        }

        self.config = config
        let socketPath = controlSocketPath(for: config)
        self.controlPath = socketPath

        // Remove stale socket file if it exists.
        let expandedSocket = expandTilde(socketPath)
        if FileManager.default.fileExists(atPath: expandedSocket) {
            try? FileManager.default.removeItem(atPath: expandedSocket)
        }

        // Ensure the ~/.ssh directory exists.
        let sshDir = expandTilde("~/.ssh")
        if !FileManager.default.fileExists(atPath: sshDir) {
            try FileManager.default.createDirectory(atPath: sshDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        // Check if a ControlMaster is already running (possibly from another session).
        let checkArgs = ["-O", "check"] + buildSSHArguments(for: config, controlPath: socketPath) + ["\(config.username)@\(config.host)"]
        let checkResult = try await runProcess("/usr/bin/ssh", arguments: checkArgs, input: nil)

        if checkResult.exitCode == 0 {
            logger.info("Reusing existing ControlMaster for \(config.host)")
            isConnected = true
            return
        }

        // Establish a new ControlMaster connection in background mode.
        var args = ["-fN"]  // fork to background, no remote command
        args += buildSSHArguments(for: config, controlPath: socketPath)
        args += ["-o", "ControlMaster=yes"]
        args.append("\(config.username)@\(config.host)")

        logger.info("Establishing ControlMaster to \(config.host):\(config.port)")

        let result = try await runProcess("/usr/bin/ssh", arguments: args, input: nil)

        if result.exitCode != 0 {
            let error = parseSSHError(result.stderr, exitCode: result.exitCode)
            logger.error("ControlMaster failed: \(result.stderr)")
            throw error
        }

        // Verify the socket was created.
        // Give ssh a moment to create the socket file since it forks to background.
        var verified = false
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            let verifyResult = try await runProcess(
                "/usr/bin/ssh",
                arguments: ["-O", "check"] + buildSSHArguments(for: config, controlPath: socketPath) + ["\(config.username)@\(config.host)"],
                input: nil
            )
            if verifyResult.exitCode == 0 {
                verified = true
                break
            }
        }

        guard verified else {
            logger.error("ControlMaster socket never became available")
            throw SFTPError.connectionFailed("SSH connection was established but control socket is not responding")
        }

        isConnected = true
        logger.info("ControlMaster established for \(config.username)@\(config.host):\(config.port)")
    }

    // MARK: - Upload

    func upload(localPath: URL, remotePath: String, progress: UploadProgressHandler?) async throws -> UploadResult {
        guard let config = config, let controlPath = controlPath, isConnected else {
            throw SFTPError.connectionFailed("Not connected. Call connect() first.")
        }

        let filePath = localPath.path

        // Verify local file exists and get its size.
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SFTPError.pathNotFound(filePath)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw SFTPError.connectionFailed("Unable to determine file size for \(filePath)")
        }

        // Report initial progress.
        progress?(0, fileSize)

        let startTime = Date()

        // Build the sftp batch command.
        // The remotePath parameter is the FULL remote file path (directory + filename already combined).
        let batchCommand = "put \"\(escapeSFTPPath(filePath))\" \"\(escapeSFTPPath(remotePath))\""

        var sftpArgs = buildSFTPArguments(for: config, controlPath: controlPath)
        sftpArgs += ["-b", "-"]  // batch mode, read commands from stdin
        sftpArgs.append("\(config.username)@\(config.host)")

        logger.info("Uploading \(filePath) -> \(remotePath) (\(fileSize) bytes)")

        // For large files, run the upload with progress estimation in a concurrent task.
        if fileSize > progressEstimationThreshold, let progress = progress {
            let result = try await uploadWithProgress(
                sftpArgs: sftpArgs,
                batchCommand: batchCommand,
                fileSize: fileSize,
                progress: progress
            )

            let duration = Date().timeIntervalSince(startTime)

            if result.exitCode != 0 {
                let error = parseSFTPUploadError(result.stderr, exitCode: result.exitCode, remotePath: remotePath)
                logger.error("Upload failed: \(result.stderr)")
                throw error
            }

            // Final progress callback.
            progress(fileSize, fileSize)

            logger.info("Upload complete in \(String(format: "%.2f", duration))s")

            return UploadResult(
                remoteFilePath: remotePath,
                fileSize: fileSize,
                duration: duration
            )
        } else {
            // Small file or no progress handler: run synchronously.
            let result = try await runProcess("/usr/bin/sftp", arguments: sftpArgs, input: batchCommand)
            let duration = Date().timeIntervalSince(startTime)

            if result.exitCode != 0 {
                let error = parseSFTPUploadError(result.stderr, exitCode: result.exitCode, remotePath: remotePath)
                logger.error("Upload failed: \(result.stderr)")
                throw error
            }

            progress?(fileSize, fileSize)

            logger.info("Upload complete in \(String(format: "%.2f", duration))s")

            return UploadResult(
                remoteFilePath: remotePath,
                fileSize: fileSize,
                duration: duration
            )
        }
    }

    // MARK: - File Exists

    func fileExists(remotePath: String) async throws -> Bool {
        guard let config = config, let controlPath = controlPath, isConnected else {
            throw SFTPError.connectionFailed("Not connected. Call connect() first.")
        }

        let batchCommand = "ls -la \"\(escapeSFTPPath(remotePath))\""

        var sftpArgs = buildSFTPArguments(for: config, controlPath: controlPath)
        sftpArgs += ["-b", "-"]
        sftpArgs.append("\(config.username)@\(config.host)")

        let result = try await runProcess("/usr/bin/sftp", arguments: sftpArgs, input: batchCommand)

        // sftp returns exit code 0 if ls succeeds, non-zero if the file does not exist.
        if result.exitCode == 0 {
            // Also check that stderr does not contain "not found" or "No such file"
            let stderrLower = result.stderr.lowercased()
            if stderrLower.contains("not found") || stderrLower.contains("no such file") {
                return false
            }
            return true
        }

        // Check if the failure is specifically "file not found" vs a real error.
        let stderrLower = result.stderr.lowercased()
        if stderrLower.contains("not found") || stderrLower.contains("no such file") || stderrLower.contains("doesn't exist") {
            return false
        }

        // If it is some other error (connection lost, permission, etc.) propagate it.
        if stderrLower.contains("permission denied") {
            throw SFTPError.permissionDenied(remotePath)
        }
        if stderrLower.contains("connection") && (stderrLower.contains("closed") || stderrLower.contains("lost") || stderrLower.contains("reset")) {
            isConnected = false
            throw SFTPError.connectionFailed("Connection lost while checking file existence")
        }

        // Ambiguous failure: treat as not found for non-critical check.
        return false
    }

    // MARK: - Remove File

    func removeFile(remotePath: String) async throws {
        guard let config = config, let controlPath = controlPath, isConnected else {
            throw SFTPError.connectionFailed("Not connected. Call connect() first.")
        }

        let batchCommand = "rm \"\(escapeSFTPPath(remotePath))\""

        var sftpArgs = buildSFTPArguments(for: config, controlPath: controlPath)
        sftpArgs += ["-b", "-"]
        sftpArgs.append("\(config.username)@\(config.host)")

        logger.info("Removing remote file: \(remotePath)")

        let result = try await runProcess("/usr/bin/sftp", arguments: sftpArgs, input: batchCommand)

        if result.exitCode != 0 {
            let stderrLower = result.stderr.lowercased()
            if stderrLower.contains("no such file") || stderrLower.contains("not found") {
                throw SFTPError.pathNotFound(remotePath)
            }
            if stderrLower.contains("permission denied") {
                throw SFTPError.permissionDenied(remotePath)
            }
            logger.error("Failed to remove file: \(result.stderr)")
            throw SFTPError.connectionFailed("Failed to remove remote file: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        logger.info("Removed remote file: \(remotePath)")
    }

    // MARK: - Disconnect

    func disconnect() async {
        guard let config = config, let controlPath = controlPath else {
            isConnected = false
            return
        }

        logger.info("Closing ControlMaster for \(config.host)")

        let args = ["-O", "exit"] + buildSSHArguments(for: config, controlPath: controlPath) + ["\(config.username)@\(config.host)"]

        do {
            _ = try await runProcess("/usr/bin/ssh", arguments: args, input: nil)
        } catch {
            logger.warning("Error closing ControlMaster: \(error.localizedDescription)")
        }

        // Clean up the socket file.
        let expandedSocket = expandTilde(controlPath)
        if FileManager.default.fileExists(atPath: expandedSocket) {
            try? FileManager.default.removeItem(atPath: expandedSocket)
        }

        isConnected = false
        self.config = nil
        self.controlPath = nil

        logger.info("Disconnected")
    }

    // MARK: - Test Connection

    func testConnection(config: ServerConfiguration) async throws -> String {
        // Establish a fresh connection.
        try await connect(config: config)

        defer {
            // Schedule disconnect after test completes.
            Task { [weak self] in
                await self?.disconnect()
            }
        }

        let probeFilename = ".dropshot-probe-\(UUID().uuidString.prefix(8))"
        let probePath = "\(config.remotePathWithTrailingSlash)\(probeFilename)"

        // Write a 1-byte probe file to verify write access.
        let tempDir = FileManager.default.temporaryDirectory
        let localProbe = tempDir.appendingPathComponent(probeFilename)

        defer {
            try? FileManager.default.removeItem(at: localProbe)
        }

        try Data([0x00]).write(to: localProbe)

        // Upload the probe file.
        let batchCommands = "put \"\(escapeSFTPPath(localProbe.path))\" \"\(escapeSFTPPath(probePath))\""

        guard let controlPath = controlPath else {
            throw SFTPError.connectionFailed("Control path not available")
        }

        var sftpArgs = buildSFTPArguments(for: config, controlPath: controlPath)
        sftpArgs += ["-b", "-"]
        sftpArgs.append("\(config.username)@\(config.host)")

        let uploadResult = try await runProcess("/usr/bin/sftp", arguments: sftpArgs, input: batchCommands)

        if uploadResult.exitCode != 0 {
            let stderrLower = uploadResult.stderr.lowercased()
            if stderrLower.contains("no such file") || stderrLower.contains("not found") {
                throw SFTPError.pathNotFound(config.remotePath)
            }
            if stderrLower.contains("permission denied") {
                throw SFTPError.permissionDenied(config.remotePath)
            }
            if stderrLower.contains("disk quota") || stderrLower.contains("no space left") {
                throw SFTPError.diskFull
            }
            throw SFTPError.connectionFailed("Probe upload failed: \(uploadResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // Verify the probe file exists.
        let exists = try await fileExists(remotePath: probePath)
        guard exists else {
            throw SFTPError.connectionFailed("Probe file was uploaded but could not be verified on the server")
        }

        // Delete the probe file.
        try await removeFile(remotePath: probePath)

        logger.info("Connection test passed for \(config.username)@\(config.host)")
        return "Connected to \(config.host) as \(config.username)"
    }

    // MARK: - SSH Argument Building

    /// Builds common SSH arguments shared across ssh and sftp invocations.
    private func buildSSHArguments(for config: ServerConfiguration, controlPath: String) -> [String] {
        var args: [String] = []

        // Port
        args += ["-o", "Port=\(config.port)"]

        // ControlMaster socket
        args += ["-o", "ControlPath=\(controlPath)"]
        args += ["-o", "ControlMaster=auto"]
        args += ["-o", "ControlPersist=300"]

        // Host key and timeout settings
        args += ["-o", "StrictHostKeyChecking=accept-new"]
        args += ["-o", "ConnectTimeout=10"]

        // Disable password prompt on stdin for non-interactive use when using key auth.
        args += ["-o", "BatchMode=yes"]

        // SSH key authentication
        if config.authMethod == .sshKey, let keyPath = config.sshKeyPath, !keyPath.isEmpty {
            args += ["-i", expandTilde(keyPath)]
        }

        return args
    }

    /// Builds sftp-specific arguments (wraps common SSH args into -o flags for sftp).
    private func buildSFTPArguments(for config: ServerConfiguration, controlPath: String) -> [String] {
        var args: [String] = []

        // Port (sftp uses -P, not -p)
        args += ["-P", "\(config.port)"]

        // Pass SSH options through -o
        args += ["-o", "ControlPath=\(controlPath)"]
        args += ["-o", "ControlMaster=auto"]
        args += ["-o", "ControlPersist=300"]
        args += ["-o", "StrictHostKeyChecking=accept-new"]
        args += ["-o", "ConnectTimeout=10"]
        args += ["-o", "BatchMode=yes"]

        // SSH key
        if config.authMethod == .sshKey, let keyPath = config.sshKeyPath, !keyPath.isEmpty {
            args += ["-i", expandTilde(keyPath)]
        }

        return args
    }

    // MARK: - Process Execution

    /// Runs a system process and captures its stdout, stderr, and exit code.
    ///
    /// - Parameters:
    ///   - executable: Absolute path to the executable (e.g. `/usr/bin/ssh`).
    ///   - arguments: Command-line arguments.
    ///   - input: Optional string to write to the process's stdin.
    /// - Returns: Tuple of stdout, stderr, and exit code.
    private func runProcess(
        _ executable: String,
        arguments: [String],
        input: String?
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let input = input {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe

            // Write input data after launch.
            let inputData = Data(input.utf8)
            // We need to write and close after launching.
            process.standardInput = stdinPipe

            try process.run()

            // Write to stdin on a background queue to avoid blocking.
            stdinPipe.fileHandleForWriting.write(inputData)
            stdinPipe.fileHandleForWriting.closeFile()
        } else {
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }

        // Read stdout and stderr concurrently.
        return await withCheckedContinuation { continuation in
            let group = DispatchGroup()
            var stdoutData = Data()
            var stderrData = Data()

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                group.leave()
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                continuation.resume(returning: (stdout: stdout, stderr: stderr, exitCode: process.terminationStatus))
            }
        }
    }

    // MARK: - Upload With Progress Estimation

    /// Runs the sftp upload in a background task while periodically reporting estimated progress.
    ///
    /// Since the system sftp binary in batch mode does not report per-byte progress,
    /// we estimate progress based on elapsed time and a conservative transfer rate assumption.
    /// The progress is capped at 95% until the process completes, then jumps to 100%.
    private func uploadWithProgress(
        sftpArgs: [String],
        batchCommand: String,
        fileSize: Int64,
        progress: @escaping UploadProgressHandler
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let startTime = Date()

        // Start the actual upload.
        async let uploadTask = runProcess("/usr/bin/sftp", arguments: sftpArgs, input: batchCommand)

        // Run a progress estimation loop concurrently.
        let progressTask = Task {
            // Conservative estimate: 5 MB/s baseline. Progress will never exceed 95%
            // until the upload actually completes.
            let estimatedRate: Double = 5_000_000 // bytes per second
            let maxEstimatedProgress: Double = 0.95

            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: UInt64(progressUpdateInterval * 1_000_000_000))

                let elapsed = Date().timeIntervalSince(startTime)
                let estimatedBytes = Int64(elapsed * estimatedRate)
                let clampedBytes = min(estimatedBytes, Int64(Double(fileSize) * maxEstimatedProgress))

                progress(clampedBytes, fileSize)
            }
        }

        let result = try await uploadTask
        progressTask.cancel()

        return result
    }

    // MARK: - Error Parsing

    /// Parses SSH stderr output and maps it to the appropriate `SFTPError`.
    private func parseSSHError(_ stderr: String, exitCode: Int32) -> SFTPError {
        let lower = stderr.lowercased()

        if lower.contains("permission denied") {
            return .authenticationFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if lower.contains("no route to host") || lower.contains("could not resolve hostname") {
            let host = config?.host ?? "unknown"
            return .hostUnreachable(host)
        }

        if lower.contains("connection refused") {
            let host = config?.host ?? "unknown"
            return .hostUnreachable(host)
        }

        if lower.contains("host key verification failed") {
            return .hostKeyMismatch(oldKey: "stored", newKey: "received")
        }

        if lower.contains("no such file or directory") {
            return .pathNotFound(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if lower.contains("disk quota exceeded") || lower.contains("no space left") {
            return .diskFull
        }

        if lower.contains("connection timed out") || lower.contains("timed out") {
            return .timeout
        }

        if lower.contains("connection closed") || lower.contains("connection reset") || lower.contains("broken pipe") {
            return .connectionFailed("Connection lost: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if lower.contains("subsystem request failed") || lower.contains("sftp") && lower.contains("not available") {
            return .sftpSubsystemFailed
        }

        // Generic fallback.
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .connectionFailed(detail.isEmpty ? "SSH process exited with code \(exitCode)" : detail)
    }

    /// Parses sftp upload-specific errors, with additional handling for transfer-related failures.
    private func parseSFTPUploadError(_ stderr: String, exitCode: Int32, remotePath: String) -> SFTPError {
        let lower = stderr.lowercased()

        // Upload-specific errors checked first.
        if lower.contains("no such file or directory") {
            // Could be the remote directory not existing.
            return .pathNotFound(remotePath)
        }

        if lower.contains("permission denied") {
            return .permissionDenied(remotePath)
        }

        if lower.contains("disk quota exceeded") || lower.contains("no space left") {
            return .diskFull
        }

        if lower.contains("connection closed") || lower.contains("connection reset") || lower.contains("broken pipe") || lower.contains("connection lost") {
            isConnected = false
            return .transferInterrupted(progress: 0)
        }

        // Fall through to generic SSH error parsing.
        return parseSSHError(stderr, exitCode: exitCode)
    }

    // MARK: - Path and String Helpers

    /// Generates a deterministic control socket path for the given configuration.
    ///
    /// Uses a fixed path pattern so that multiple `SystemSFTPTransport` instances
    /// targeting the same server can share the ControlMaster connection.
    private func controlSocketPath(for config: ServerConfiguration) -> String {
        return "~/.ssh/dropshot-control-\(config.username)@\(config.host):\(config.port)"
    }

    /// Expands a leading `~` in a path to the user's home directory.
    private func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return (path as NSString).expandingTildeInPath
    }

    /// Escapes a path string for use in sftp batch commands.
    ///
    /// Handles backslashes and double-quote characters that would otherwise
    /// break the quoted string sent to sftp.
    private func escapeSFTPPath(_ path: String) -> String {
        var escaped = path
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }
}
