import XCTest
@testable import DropShot

/// Integration tests specifically for Unicode filename handling through the full SFTP pipeline.
///
/// These tests verify that filenames with various Unicode characters survive the
/// round trip: local file system -> SFTP upload -> remote file system -> verification.
///
/// Requires `docker-compose.test.yml` to be running and `DROPSHOT_INTEGRATION_TESTS=1`.
final class UnicodeRoundTripTests: XCTestCase {

    // MARK: - Properties

    private static let testConfig = ServerConfiguration(
        name: "Unicode Test Server",
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
            .appendingPathComponent("UnicodeRoundTripTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        try await transport.connect(config: Self.testConfig)
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

    /// Uploads a file with the given name, verifies it exists on the server, then cleans up.
    /// Returns true if the full round trip succeeded.
    @discardableResult
    private func uploadAndVerify(filename: String, content: String = "test content") async throws -> Bool {
        let localFile = tempDirectory.appendingPathComponent(filename)
        try Data(content.utf8).write(to: localFile)

        let remotePath = Self.testConfig.remotePathWithTrailingSlash + filename

        let result = try await transport.upload(localPath: localFile, remotePath: remotePath, progress: nil)
        XCTAssertEqual(result.remoteFilePath, remotePath)
        XCTAssertGreaterThan(result.fileSize, 0)

        let exists = try await transport.fileExists(remotePath: remotePath)
        XCTAssertTrue(exists, "File '\(filename)' should exist on server after upload")

        // Clean up the remote file
        try await transport.removeFile(remotePath: remotePath)

        // Verify removal
        let existsAfterRemove = try await transport.fileExists(remotePath: remotePath)
        XCTAssertFalse(existsAfterRemove, "File '\(filename)' should be removed after cleanup")

        return exists
    }

    // MARK: - Czech Diacritics

    func testCzechDiacritics() async throws {
        try await uploadAndVerify(filename: "pr\u{016F}vodce m\u{011B}stem.pdf")
    }

    func testAllCzechCharacters() async throws {
        // All Czech-specific diacritical characters in a single filename
        try await uploadAndVerify(filename: "\u{0159}\u{017E}\u{010D}\u{011B}\u{0161}\u{010F}\u{0165}\u{0148}\u{016F}\u{00FA}\u{00ED}\u{00E1}\u{00E9}\u{00FD}\u{00F3}.txt")
    }

    func testCzechUpperAndLowerCase() async throws {
        try await uploadAndVerify(filename: "\u{0158}\u{017D}\u{010C}\u{011A}\u{0160}_\u{0159}\u{017E}\u{010D}\u{011B}\u{0161}.txt")
    }

    // MARK: - CJK Characters

    func testJapaneseCharacters() async throws {
        try await uploadAndVerify(filename: "\u{30B9}\u{30AF}\u{30EA}\u{30FC}\u{30F3}.png")
    }

    func testChineseCharacters() async throws {
        try await uploadAndVerify(filename: "\u{6587}\u{4EF6}\u{4E0A}\u{4F20}.txt")
    }

    func testKoreanCharacters() async throws {
        try await uploadAndVerify(filename: "\u{D30C}\u{C77C}\u{C5C5}\u{B85C}\u{B4DC}.png")
    }

    // MARK: - Emoji

    func testEmojiFilename() async throws {
        try await uploadAndVerify(filename: "photo \u{1F389}.png")
    }

    func testMultipleEmojis() async throws {
        try await uploadAndVerify(filename: "\u{1F4F8}\u{1F30D}\u{2728}.jpg")
    }

    // MARK: - Mixed Scripts

    func testMixedScripts() async throws {
        try await uploadAndVerify(filename: "report 2026 \u{2014} shrnut\u{00ED}.pdf")
    }

    func testLatinAndCJKMixed() async throws {
        try await uploadAndVerify(filename: "report_\u{5831}\u{544A}_2026.pdf")
    }

    // MARK: - Parentheses and Special Characters

    func testParentheses() async throws {
        try await uploadAndVerify(filename: "foto (1).jpg")
    }

    func testParenthesesWithSpaces() async throws {
        try await uploadAndVerify(filename: "my photo (copy 2).png")
    }

    func testSquareBrackets() async throws {
        try await uploadAndVerify(filename: "file [2026].txt")
    }

    func testHyphenAndUnderscore() async throws {
        try await uploadAndVerify(filename: "file-name_v2.txt")
    }

    // MARK: - NFC Normalization Round Trip

    func testNFCNormalization() async throws {
        // Create a file with the NFC (precomposed) form
        let nfcFilename = "pr\u{016F}vodce.txt" // u with ring above (precomposed)

        // Verify that FileProcessor normalizes to NFC
        let sanitized = FileProcessor.sanitize(nfcFilename)
        let normalized = FileProcessor.normalizeToNFC(sanitized)
        XCTAssertEqual(sanitized, normalized, "Sanitized filename should already be in NFC form")

        // Upload with the NFC form
        try await uploadAndVerify(filename: nfcFilename)
    }

    func testDecomposedInputNormalizesToNFC() async throws {
        // NFD (decomposed) form: u + combining ring above
        let nfdFilename = "pr\u{0075}\u{030A}vodce.txt"

        // Sanitize should normalize to NFC
        let sanitized = FileProcessor.sanitize(nfdFilename)
        let expectedNFC = FileProcessor.normalizeToNFC(nfdFilename)
        XCTAssertEqual(sanitized, expectedNFC, "Sanitized NFD input should produce NFC output")

        // Upload the NFC-normalized version
        try await uploadAndVerify(filename: sanitized)
    }

    // MARK: - Edge Cases

    func testFilenameWithOnlyUnicodeCharacters() async throws {
        try await uploadAndVerify(filename: "\u{00E9}\u{00E8}\u{00EA}.txt")
    }

    func testLongUnicodeFilename() async throws {
        // Create a filename with many multi-byte characters, within the 200-byte limit
        let base = String(repeating: "\u{016F}", count: 50) // 50 * 2 = 100 UTF-8 bytes
        let filename = base + ".txt"
        XCTAssertLessThanOrEqual(filename.utf8.count, FileProcessor.maxFilenameBytes)

        try await uploadAndVerify(filename: filename)
    }
}
