import XCTest
@testable import DropShot

/// Integration tests for SFTP upload operations using a Docker SSH server.
///
/// These tests require `docker-compose.test.yml` to be running:
///
///     docker compose -f docker-compose.test.yml up -d
///
/// Set the environment variable `DROPSHOT_INTEGRATION_TESTS=1` to enable these tests.
/// They connect to localhost:2222 with testuser:testpass.
final class SFTPUploadTests: XCTestCase {

    // MARK: - Properties

    static let testConfig = ServerConfiguration(
        name: "Test Docker Server",
        host: "localhost",
        port: 2222,
        username: "testuser",
        authMethod: .password,
        sshKeyPath: nil,
        remotePath: "/home/testuser/uploads/",
        baseURL: nil
    )

    private var transport: SystemSFTPTransport!
    private var tempDirectory: URL!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()

        guard ProcessInfo.processInfo.environment["DROPSHOT_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Integration tests are disabled. Set DROPSHOT_INTEGRATION_TESTS=1 to enable.")
        }

        transport = SystemSFTPTransport()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SFTPUploadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let transport = transport {
            await transport.disconnect()
        }
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a temporary file with the given name and content, returns the file URL.
    private func createTempFile(name: String, content: Data) throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(name)
        try content.write(to: fileURL)
        return fileURL
    }

    /// Creates a temporary file with the given name and size filled with random-ish bytes.
    private func createTempFile(name: String, sizeBytes: Int) throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(name)
        let data = Data(repeating: 0xAB, count: sizeBytes)
        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Connection

    func testConnectionToDockerServer() async throws {
        try await transport.connect(config: Self.testConfig)

        let isConnected = await transport.isConnected
        XCTAssertTrue(isConnected, "Should be connected after connect()")
    }

    func testTestConnection() async throws {
        let result = try await transport.testConnection(config: Self.testConfig)
        XCTAssertTrue(result.contains("localhost"), "Result should mention the host")
        XCTAssertTrue(result.contains("testuser"), "Result should mention the username")
    }

    // MARK: - Upload

    func testUploadBasicFile() async throws {
        try await transport.connect(config: Self.testConfig)

        let localFile = try createTempFile(name: "basic-test.txt", content: Data("Hello SFTP!".utf8))
        let remotePath = Self.testConfig.remotePathWithTrailingSlash + "basic-test.txt"

        let result = try await transport.upload(localPath: localFile, remotePath: remotePath, progress: nil)

        XCTAssertEqual(result.remoteFilePath, remotePath)
        XCTAssertGreaterThan(result.fileSize, 0)
        XCTAssertGreaterThanOrEqual(result.duration, 0)

        // Verify file exists on server
        let exists = try await transport.fileExists(remotePath: remotePath)
        XCTAssertTrue(exists)

        // Cleanup
        try await transport.removeFile(remotePath: remotePath)
    }

    func testUploadCzechFilename() async throws {
        try await transport.connect(config: Self.testConfig)

        let filename = "pr\u{016F}vodce m\u{011B}stem.txt"
        let localFile = try createTempFile(name: filename, content: Data("Czech content".utf8))
        let remotePath = Self.testConfig.remotePathWithTrailingSlash + filename

        let result = try await transport.upload(localPath: localFile, remotePath: remotePath, progress: nil)
        XCTAssertEqual(result.remoteFilePath, remotePath)

        let exists = try await transport.fileExists(remotePath: remotePath)
        XCTAssertTrue(exists, "File with Czech diacritics should exist on server")

        // Cleanup
        try await transport.removeFile(remotePath: remotePath)
    }

    func testUploadFileWithSpaces() async throws {
        try await transport.connect(config: Self.testConfig)

        let filename = "my uploaded file.txt"
        let localFile = try createTempFile(name: filename, content: Data("Spaced content".utf8))
        let remotePath = Self.testConfig.remotePathWithTrailingSlash + filename

        let result = try await transport.upload(localPath: localFile, remotePath: remotePath, progress: nil)
        XCTAssertEqual(result.remoteFilePath, remotePath)

        let exists = try await transport.fileExists(remotePath: remotePath)
        XCTAssertTrue(exists, "File with spaces in name should exist on server")

        try await transport.removeFile(remotePath: remotePath)
    }

    func testUploadLargeFile() async throws {
        try await transport.connect(config: Self.testConfig)

        // Create a 10MB temp file
        let tenMB = 10 * 1024 * 1024
        let localFile = try createTempFile(name: "large-test.bin", sizeBytes: tenMB)
        let remotePath = Self.testConfig.remotePathWithTrailingSlash + "large-test.bin"

        var progressCalled = false
        let result = try await transport.upload(localPath: localFile, remotePath: remotePath) { bytesUploaded, totalBytes in
            progressCalled = true
            XCTAssertEqual(totalBytes, Int64(tenMB))
            XCTAssertGreaterThanOrEqual(bytesUploaded, 0)
            XCTAssertLessThanOrEqual(bytesUploaded, totalBytes)
        }

        XCTAssertEqual(result.fileSize, Int64(tenMB))
        XCTAssertGreaterThan(result.duration, 0, "10MB upload should take measurable time")
        XCTAssertTrue(progressCalled, "Progress handler should be called for large files")

        let exists = try await transport.fileExists(remotePath: remotePath)
        XCTAssertTrue(exists)

        try await transport.removeFile(remotePath: remotePath)
    }

    // MARK: - File Exists

    func testFileExistsCheck() async throws {
        try await transport.connect(config: Self.testConfig)

        let localFile = try createTempFile(name: "exists-check.txt", content: Data("probe".utf8))
        let remotePath = Self.testConfig.remotePathWithTrailingSlash + "exists-check.txt"

        // Should not exist before upload
        let beforeUpload = try await transport.fileExists(remotePath: remotePath)
        XCTAssertFalse(beforeUpload)

        // Upload
        _ = try await transport.upload(localPath: localFile, remotePath: remotePath, progress: nil)

        // Should exist after upload
        let afterUpload = try await transport.fileExists(remotePath: remotePath)
        XCTAssertTrue(afterUpload)

        // Cleanup
        try await transport.removeFile(remotePath: remotePath)
    }

    func testFileExistsNonExistentFile() async throws {
        try await transport.connect(config: Self.testConfig)

        let exists = try await transport.fileExists(remotePath: "/home/testuser/uploads/definitely-not-here-\(UUID().uuidString).txt")
        XCTAssertFalse(exists)
    }

    // MARK: - Remove File

    func testRemoveFile() async throws {
        try await transport.connect(config: Self.testConfig)

        let localFile = try createTempFile(name: "to-remove.txt", content: Data("delete me".utf8))
        let remotePath = Self.testConfig.remotePathWithTrailingSlash + "to-remove.txt"

        _ = try await transport.upload(localPath: localFile, remotePath: remotePath, progress: nil)

        // File should exist
        let existsBefore = try await transport.fileExists(remotePath: remotePath)
        XCTAssertTrue(existsBefore)

        // Remove it
        try await transport.removeFile(remotePath: remotePath)

        // File should no longer exist
        let existsAfter = try await transport.fileExists(remotePath: remotePath)
        XCTAssertFalse(existsAfter)
    }

    // MARK: - Error Cases

    func testUploadToNonExistentPath() async throws {
        try await transport.connect(config: Self.testConfig)

        let localFile = try createTempFile(name: "orphan.txt", content: Data("lost".utf8))
        let remotePath = "/home/testuser/nonexistent-dir-\(UUID().uuidString)/orphan.txt"

        do {
            _ = try await transport.upload(localPath: localFile, remotePath: remotePath, progress: nil)
            XCTFail("Upload to non-existent directory should throw an error")
        } catch {
            // Expected: should be a path not found or permission error
            XCTAssertTrue(error is SFTPError, "Expected SFTPError, got \(type(of: error)): \(error)")
        }
    }

    // MARK: - Disconnect and Reconnect

    func testDisconnectAndReconnect() async throws {
        // First connection
        try await transport.connect(config: Self.testConfig)
        let connectedFirst = await transport.isConnected
        XCTAssertTrue(connectedFirst)

        // Disconnect
        await transport.disconnect()
        let disconnected = await transport.isConnected
        XCTAssertFalse(disconnected)

        // Reconnect
        try await transport.connect(config: Self.testConfig)
        let connectedAgain = await transport.isConnected
        XCTAssertTrue(connectedAgain)

        // Verify we can still upload after reconnect
        let localFile = try createTempFile(name: "reconnect-test.txt", content: Data("reconnected".utf8))
        let remotePath = Self.testConfig.remotePathWithTrailingSlash + "reconnect-test.txt"

        let result = try await transport.upload(localPath: localFile, remotePath: remotePath, progress: nil)
        XCTAssertEqual(result.remoteFilePath, remotePath)

        try await transport.removeFile(remotePath: remotePath)
    }

    // MARK: - Upload Without Connection

    func testUploadWithoutConnectionThrows() async throws {
        // Do NOT connect
        let localFile = try createTempFile(name: "no-conn.txt", content: Data("no connection".utf8))

        do {
            _ = try await transport.upload(
                localPath: localFile,
                remotePath: "/home/testuser/uploads/no-conn.txt",
                progress: nil
            )
            XCTFail("Upload without connection should throw")
        } catch let error as SFTPError {
            if case .connectionFailed = error {
                // Expected
            } else {
                XCTFail("Expected connectionFailed, got \(error)")
            }
        }
    }
}
