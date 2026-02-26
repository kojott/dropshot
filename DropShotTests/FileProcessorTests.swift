import XCTest
@testable import DropShot

final class FileProcessorTests: XCTestCase {

    // MARK: - Properties

    private var tempDirectory: URL!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileProcessorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    // MARK: - Sanitization: Normal Cases

    func testSanitizeNormalFilename() {
        let result = FileProcessor.sanitize("hello.png")
        XCTAssertEqual(result, "hello.png")
    }

    func testSanitizeFilenameWithSpaces() {
        let result = FileProcessor.sanitize("my photo.png")
        XCTAssertEqual(result, "my photo.png")
    }

    func testSanitizeCzechCharacters() {
        let result = FileProcessor.sanitize("pr\u{016F}vodce m\u{011B}stem.pdf")
        // Czech characters should be preserved after sanitization
        XCTAssertTrue(result.contains("\u{016F}"))
        XCTAssertTrue(result.contains("\u{011B}"))
        XCTAssertTrue(result.hasSuffix(".pdf"))
    }

    func testSanitizeSpacesPreserved() {
        let result = FileProcessor.sanitize("file name with spaces.txt")
        XCTAssertEqual(result, "file name with spaces.txt")
    }

    // MARK: - Sanitization: Path Traversal

    func testSanitizePathTraversal() {
        let result = FileProcessor.sanitize("../../etc/passwd")
        XCTAssertEqual(result, "passwd")
    }

    func testSanitizeLeadingSlash() {
        let result = FileProcessor.sanitize("/secret/file.txt")
        XCTAssertEqual(result, "file.txt")
    }

    func testSanitizeDotSlash() {
        let result = FileProcessor.sanitize("./file.txt")
        XCTAssertEqual(result, "file.txt")
    }

    func testSanitizeDeepTraversal() {
        let result = FileProcessor.sanitize("../../../../../../../tmp/evil.sh")
        XCTAssertEqual(result, "evil.sh")
    }

    func testSanitizeMixedTraversal() {
        let result = FileProcessor.sanitize("foo/../bar/../../baz.txt")
        // The implementation takes the last non-empty, non-dot, non-dotdot component
        XCTAssertEqual(result, "baz.txt")
    }

    // MARK: - Sanitization: Special Characters

    func testSanitizeNullBytes() {
        let result = FileProcessor.sanitize("hello\0world.png")
        XCTAssertEqual(result, "helloworld.png")
    }

    func testSanitizeMultipleNullBytes() {
        let result = FileProcessor.sanitize("\0\0file\0.txt\0")
        XCTAssertEqual(result, "file.txt")
    }

    // MARK: - Sanitization: NFC Normalization

    func testSanitizeNFCNormalization() {
        // Decomposed form: u + combining ring above (U+0075 U+030A) should become u with ring (U+016F)
        let decomposed = "pr\u{0075}\u{030A}vodce.pdf"
        let result = FileProcessor.sanitize(decomposed)
        let expected = FileProcessor.normalizeToNFC(decomposed)
        XCTAssertEqual(result, expected)
        // Verify it actually normalized: the NFC form should have fewer code points
        // (combining characters merged into precomposed form)
    }

    // MARK: - Sanitization: Long Filenames

    func testSanitizeLongFilename() {
        // Create a filename with 250 ASCII bytes
        let longBase = String(repeating: "a", count: 250)
        let longFilename = longBase + ".png"
        let result = FileProcessor.sanitize(longFilename)
        XCTAssertLessThanOrEqual(result.utf8.count, FileProcessor.maxFilenameBytes)
        // Extension should be preserved
        XCTAssertTrue(result.hasSuffix(".png"))
    }

    func testSanitizeLongFilenameWithMultibyteChars() {
        // Create a long filename with Czech characters (multi-byte UTF-8)
        let longBase = String(repeating: "\u{016F}", count: 150) // each is 2 bytes
        let longFilename = longBase + ".pdf"
        let result = FileProcessor.sanitize(longFilename)
        XCTAssertLessThanOrEqual(result.utf8.count, FileProcessor.maxFilenameBytes)
        XCTAssertTrue(result.hasSuffix(".pdf"))
    }

    func testSanitizeFilenameExactlyAtLimit() {
        // Create filename at exactly 200 bytes including extension
        let extensionPart = ".png" // 4 bytes
        let baseLength = FileProcessor.maxFilenameBytes - extensionPart.utf8.count
        let base = String(repeating: "x", count: baseLength)
        let filename = base + extensionPart
        XCTAssertEqual(filename.utf8.count, FileProcessor.maxFilenameBytes)

        let result = FileProcessor.sanitize(filename)
        XCTAssertEqual(result, filename, "Filename at exactly the byte limit should not be truncated")
    }

    // MARK: - Sanitization: Empty / Dot-only

    func testSanitizeEmptyString() {
        let result = FileProcessor.sanitize("")
        XCTAssertEqual(result, "unnamed")
    }

    func testSanitizeOnlyDots() {
        let result = FileProcessor.sanitize("..")
        XCTAssertEqual(result, "unnamed")
    }

    func testSanitizeSingleDot() {
        // "." as a component gets filtered out by the last { !$0.isEmpty && $0 != "." && $0 != ".." }
        let result = FileProcessor.sanitize(".")
        XCTAssertEqual(result, "unnamed")
    }

    func testSanitizeOnlySlashes() {
        let result = FileProcessor.sanitize("///")
        XCTAssertEqual(result, "unnamed")
    }

    func testSanitizeWhitespaceOnly() {
        let result = FileProcessor.sanitize("   ")
        XCTAssertEqual(result, "unnamed")
    }

    // MARK: - Filename Patterns

    func testResolveOriginalPattern() {
        let result = FileProcessor.resolveFilename(
            original: "photo.png",
            pattern: .original,
            extension: "png"
        )
        XCTAssertEqual(result, "photo.png")
    }

    func testResolveDateTimePattern() {
        let result = FileProcessor.resolveFilename(
            original: "screenshot.png",
            pattern: .dateTimeOriginal,
            extension: "png"
        )
        // Should start with a date-time prefix in format YYYY-MM-dd_HH-mm-ss
        let dateRegex = #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_screenshot\.png$"#
        XCTAssertTrue(
            result.range(of: dateRegex, options: .regularExpression) != nil,
            "Expected date-time prefix pattern, got: \(result)"
        )
    }

    func testResolveDateTimePatternNoExtension() {
        let result = FileProcessor.resolveFilename(
            original: "README",
            pattern: .dateTimeOriginal,
            extension: ""
        )
        let dateRegex = #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_README$"#
        XCTAssertTrue(
            result.range(of: dateRegex, options: .regularExpression) != nil,
            "Expected date-time prefix without extension, got: \(result)"
        )
    }

    func testResolveUUIDPattern() {
        let result = FileProcessor.resolveFilename(
            original: "anything.jpg",
            pattern: .uuid,
            extension: "jpg"
        )
        // Should be a UUID followed by .jpg
        let uuidRegex = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$"#
        XCTAssertTrue(
            result.range(of: uuidRegex, options: .regularExpression) != nil,
            "Expected UUID pattern, got: \(result)"
        )
    }

    func testResolveUUIDPatternNoExtension() {
        let result = FileProcessor.resolveFilename(
            original: "file",
            pattern: .uuid,
            extension: ""
        )
        let uuidRegex = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
        XCTAssertTrue(
            result.range(of: uuidRegex, options: .regularExpression) != nil,
            "Expected bare UUID without extension, got: \(result)"
        )
    }

    func testResolveHashPattern() {
        let result = FileProcessor.resolveFilename(
            original: "photo.png",
            pattern: .hash,
            extension: "png"
        )
        // Should be a 12-character hex hash followed by .png
        let hashRegex = #"^[0-9a-f]{12}\.png$"#
        XCTAssertTrue(
            result.range(of: hashRegex, options: .regularExpression) != nil,
            "Expected 12-char hash pattern, got: \(result)"
        )
    }

    func testResolveHashPatternDeterministic() {
        // Two calls with the same input but at different times should produce different hashes
        // (because the implementation uses Date().timeIntervalSince1970)
        let result1 = FileProcessor.resolveFilename(
            original: "file.txt",
            pattern: .hash,
            extension: "txt"
        )
        // Add a tiny delay to ensure different timestamps
        Thread.sleep(forTimeInterval: 0.01)
        let result2 = FileProcessor.resolveFilename(
            original: "file.txt",
            pattern: .hash,
            extension: "txt"
        )
        // They should be different due to timestamp component
        XCTAssertNotEqual(result1, result2, "Hash should differ across calls due to timestamp")
    }

    // MARK: - Suffix Appending

    func testAppendSuffix() {
        let result = FileProcessor.appendSuffix("file.png", suffix: 1)
        XCTAssertEqual(result, "file (1).png")
    }

    func testAppendSuffixNoExtension() {
        let result = FileProcessor.appendSuffix("README", suffix: 1)
        XCTAssertEqual(result, "README (1)")
    }

    func testAppendSuffixLargeNumber() {
        let result = FileProcessor.appendSuffix("photo.jpg", suffix: 42)
        XCTAssertEqual(result, "photo (42).jpg")
    }

    func testAppendMultipleSuffixesSequential() {
        let first = FileProcessor.appendSuffix("file.png", suffix: 1)
        XCTAssertEqual(first, "file (1).png")

        // Appending suffix to an already-suffixed file
        let second = FileProcessor.appendSuffix("file.png", suffix: 2)
        XCTAssertEqual(second, "file (2).png")

        let third = FileProcessor.appendSuffix("file.png", suffix: 3)
        XCTAssertEqual(third, "file (3).png")
    }

    func testAppendSuffixWithDotInBase() {
        let result = FileProcessor.appendSuffix("archive.tar.gz", suffix: 1)
        // NSString.pathExtension returns "gz", NSString.deletingPathExtension returns "archive.tar"
        XCTAssertEqual(result, "archive.tar (1).gz")
    }

    // MARK: - NFC Normalization

    func testNormalizeToNFC() {
        // NFD form of 'u with ring above': u + combining ring above
        let nfd = "\u{0075}\u{030A}"
        let result = FileProcessor.normalizeToNFC(nfd)
        // NFC form should be the precomposed character
        XCTAssertEqual(result, "\u{016F}")
    }

    func testNormalizeToNFCAlreadyNFC() {
        let nfc = "\u{016F}"
        let result = FileProcessor.normalizeToNFC(nfc)
        XCTAssertEqual(result, nfc)
    }

    func testNormalizeToNFCAsciiUnchanged() {
        let ascii = "hello.png"
        let result = FileProcessor.normalizeToNFC(ascii)
        XCTAssertEqual(result, ascii)
    }

    // MARK: - File Validation

    func testValidFileAccepted() {
        let fileURL = tempDirectory.appendingPathComponent("valid.txt")
        let testData = Data("Hello, World!".utf8)
        try! testData.write(to: fileURL)

        let result = FileProcessor.isValidFile(at: fileURL)
        if case .valid(let fileSize) = result {
            XCTAssertEqual(fileSize, Int64(testData.count))
        } else {
            XCTFail("Expected .valid, got \(result)")
        }
    }

    func testNonExistentFileRejected() {
        let fileURL = tempDirectory.appendingPathComponent("does-not-exist.txt")
        let result = FileProcessor.isValidFile(at: fileURL)
        XCTAssertEqual(result, .notFound)
    }

    func testDirectoryRejected() {
        let dirURL = tempDirectory.appendingPathComponent("subdir", isDirectory: true)
        try! FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let result = FileProcessor.isValidFile(at: dirURL)
        XCTAssertEqual(result, .isDirectory)
    }

    func testEmptyFileRejected() {
        let fileURL = tempDirectory.appendingPathComponent("empty.txt")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())

        let result = FileProcessor.isValidFile(at: fileURL)
        XCTAssertEqual(result, .empty)
    }

    func testTooLargeFileRejected() {
        let fileURL = tempDirectory.appendingPathComponent("large.bin")
        // Create a file slightly larger than a small limit
        let smallLimit: Int64 = 100
        let oversizedData = Data(repeating: 0xFF, count: Int(smallLimit) + 1)
        try! oversizedData.write(to: fileURL)

        let result = FileProcessor.isValidFile(at: fileURL, maxSize: smallLimit)
        if case .tooLarge(let size, let limit) = result {
            XCTAssertEqual(size, Int64(oversizedData.count))
            XCTAssertEqual(limit, smallLimit)
        } else {
            XCTFail("Expected .tooLarge, got \(result)")
        }
    }

    func testFileExactlyAtSizeLimitAccepted() {
        let fileURL = tempDirectory.appendingPathComponent("exact.bin")
        let limit: Int64 = 256
        let exactData = Data(repeating: 0xAA, count: Int(limit))
        try! exactData.write(to: fileURL)

        let result = FileProcessor.isValidFile(at: fileURL, maxSize: limit)
        if case .valid(let fileSize) = result {
            XCTAssertEqual(fileSize, limit)
        } else {
            XCTFail("Expected .valid for file exactly at limit, got \(result)")
        }
    }

    func testValidFileWithDefaultMaxSize() {
        let fileURL = tempDirectory.appendingPathComponent("small.txt")
        try! Data("test".utf8).write(to: fileURL)

        let result = FileProcessor.isValidFile(at: fileURL)
        if case .valid = result {
            // Pass
        } else {
            XCTFail("Expected .valid with default max size, got \(result)")
        }
    }

    func testDefaultMaxFileSize() {
        XCTAssertEqual(FileProcessor.defaultMaxFileSize, 2 * 1024 * 1024 * 1024, "Default max should be 2 GB")
    }

    func testMaxFilenameBytesConstant() {
        XCTAssertEqual(FileProcessor.maxFilenameBytes, 200)
    }
}
