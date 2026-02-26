import XCTest
@testable import DropShot

final class UploadRecordTests: XCTestCase {

    // MARK: - Helpers

    private let serverConfigId = UUID()

    private func makeRecord(
        filename: String = "test.png",
        serverPath: String = "/srv/uploads/test.png",
        publicURL: String? = nil,
        clipboardText: String = "/srv/uploads/test.png",
        timestamp: Date = Date(),
        fileSize: Int64 = 1024,
        uploadDuration: TimeInterval = 0,
        status: UploadStatus = .uploading,
        errorMessage: String? = nil
    ) -> UploadRecord {
        UploadRecord(
            filename: filename,
            serverPath: serverPath,
            publicURL: publicURL,
            clipboardText: clipboardText,
            timestamp: timestamp,
            fileSize: fileSize,
            uploadDuration: uploadDuration,
            status: status,
            errorMessage: errorMessage,
            serverConfigId: serverConfigId
        )
    }

    // MARK: - Copyable Text

    func testCopyableTextWithoutPublicURL() {
        let record = makeRecord(
            serverPath: "/srv/uploads/photo.png",
            publicURL: nil
        )
        XCTAssertEqual(record.copyableText, "/srv/uploads/photo.png")
    }

    func testCopyableTextWithPublicURL() {
        let record = makeRecord(
            serverPath: "/srv/uploads/photo.png",
            publicURL: "https://example.com/uploads/photo.png"
        )
        XCTAssertEqual(record.copyableText, "https://example.com/uploads/photo.png")
    }

    func testCopyableTextPrefersPublicURL() {
        let record = makeRecord(
            serverPath: "/different/path.png",
            publicURL: "https://cdn.example.com/path.png"
        )
        XCTAssertEqual(record.copyableText, "https://cdn.example.com/path.png",
                       "copyableText should prefer publicURL over serverPath")
    }

    // MARK: - Formatted File Size

    func testFormattedFileSizeBytes() {
        let record = makeRecord(fileSize: 500)
        let formatted = record.formattedFileSize
        // ByteCountFormatter with .file style: 500 bytes
        XCTAssertTrue(formatted.contains("500"), "Expected '500' in formatted size, got: \(formatted)")
    }

    func testFormattedFileSizeKilobytes() {
        let record = makeRecord(fileSize: 15_000)
        let formatted = record.formattedFileSize
        // Should show something like "15 KB"
        XCTAssertTrue(formatted.contains("KB") || formatted.contains("kB"),
                       "Expected KB unit for 15000 bytes, got: \(formatted)")
    }

    func testFormattedFileSizeMegabytes() {
        let record = makeRecord(fileSize: 5_242_880) // 5 MB
        let formatted = record.formattedFileSize
        XCTAssertTrue(formatted.contains("MB"),
                       "Expected MB unit for ~5MB, got: \(formatted)")
    }

    func testFormattedFileSizeGigabytes() {
        let record = makeRecord(fileSize: 1_500_000_000) // ~1.5 GB
        let formatted = record.formattedFileSize
        XCTAssertTrue(formatted.contains("GB"),
                       "Expected GB unit for ~1.5GB, got: \(formatted)")
    }

    func testFormattedFileSizeZero() {
        let record = makeRecord(fileSize: 0)
        let formatted = record.formattedFileSize
        // ByteCountFormatter should produce something like "Zero KB" or "0 bytes"
        XCTAssertFalse(formatted.isEmpty, "Formatted size should not be empty for 0 bytes")
    }

    // MARK: - Formatted Timestamp

    func testFormattedTimestampRecent() {
        // A timestamp from just now should produce a relative string
        let record = makeRecord(timestamp: Date())
        let formatted = record.formattedTimestamp
        XCTAssertFalse(formatted.isEmpty, "Formatted timestamp should not be empty")
        // RelativeDateTimeFormatter for "now" typically produces "in 0 sec." or "now" or "0 sec. ago"
    }

    func testFormattedTimestampOlder() {
        // A timestamp from 1 hour ago
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let record = makeRecord(timestamp: oneHourAgo)
        let formatted = record.formattedTimestamp
        XCTAssertFalse(formatted.isEmpty, "Formatted timestamp should not be empty for 1h ago")
        // Should contain "hr" or "hour" depending on locale
    }

    // MARK: - Codable Round Trip

    func testCodableRoundTrip() throws {
        let original = makeRecord(
            filename: "photo.png",
            serverPath: "/srv/uploads/photo.png",
            publicURL: "https://example.com/uploads/photo.png",
            clipboardText: "https://example.com/uploads/photo.png",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            fileSize: 2_048_000,
            uploadDuration: 3.5,
            status: .completed
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UploadRecord.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.filename, original.filename)
        XCTAssertEqual(decoded.serverPath, original.serverPath)
        XCTAssertEqual(decoded.publicURL, original.publicURL)
        XCTAssertEqual(decoded.clipboardText, original.clipboardText)
        XCTAssertEqual(decoded.fileSize, original.fileSize)
        XCTAssertEqual(decoded.uploadDuration, original.uploadDuration)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.errorMessage, original.errorMessage)
        XCTAssertEqual(decoded.serverConfigId, original.serverConfigId)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTripWithOptionalNils() throws {
        let original = makeRecord(
            publicURL: nil,
            status: .uploading,
            errorMessage: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UploadRecord.self, from: data)

        XCTAssertNil(decoded.publicURL)
        XCTAssertNil(decoded.errorMessage)
        XCTAssertEqual(decoded.status, .uploading)
    }

    // MARK: - Factory Methods: completed()

    func testCompletedFactory() {
        let uploading = makeRecord(
            filename: "doc.pdf",
            serverPath: "/srv/uploads/doc.pdf",
            clipboardText: "/srv/uploads/doc.pdf",
            fileSize: 50_000,
            status: .uploading
        )

        let completed = uploading.completed(duration: 2.5, publicURL: "https://cdn.example.com/doc.pdf")

        XCTAssertEqual(completed.id, uploading.id, "ID should be preserved")
        XCTAssertEqual(completed.filename, uploading.filename)
        XCTAssertEqual(completed.serverPath, uploading.serverPath)
        XCTAssertEqual(completed.publicURL, "https://cdn.example.com/doc.pdf")
        XCTAssertEqual(completed.clipboardText, "https://cdn.example.com/doc.pdf")
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.uploadDuration, 2.5)
        XCTAssertNil(completed.errorMessage)
        XCTAssertEqual(completed.fileSize, uploading.fileSize)
        XCTAssertEqual(completed.timestamp, uploading.timestamp)
    }

    func testCompletedFactoryWithoutPublicURL() {
        let uploading = makeRecord(
            serverPath: "/srv/uploads/file.txt",
            publicURL: "https://original.com/file.txt",
            clipboardText: "https://original.com/file.txt"
        )

        let completed = uploading.completed(duration: 1.0)

        XCTAssertEqual(completed.publicURL, "https://original.com/file.txt",
                       "Should preserve original publicURL when none provided")
        XCTAssertEqual(completed.status, .completed)
    }

    // MARK: - Factory Methods: failed()

    func testFailedFactory() {
        let uploading = makeRecord(
            filename: "photo.jpg",
            status: .uploading
        )

        let failed = uploading.failed(error: "Connection reset by peer", duration: 0.5)

        XCTAssertEqual(failed.id, uploading.id, "ID should be preserved")
        XCTAssertEqual(failed.filename, uploading.filename)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.errorMessage, "Connection reset by peer")
        XCTAssertEqual(failed.uploadDuration, 0.5)
    }

    func testFailedFactoryDefaultDuration() {
        let uploading = makeRecord()
        let failed = uploading.failed(error: "Timeout")

        XCTAssertEqual(failed.uploadDuration, 0)
        XCTAssertEqual(failed.status, .failed)
    }

    // MARK: - Upload Status

    func testUploadStatusIsTerminal() {
        XCTAssertTrue(UploadStatus.completed.isTerminal)
        XCTAssertTrue(UploadStatus.failed.isTerminal)
        XCTAssertTrue(UploadStatus.cancelled.isTerminal)
        XCTAssertFalse(UploadStatus.uploading.isTerminal)
    }

    func testUploadStatusDisplayNames() {
        XCTAssertEqual(UploadStatus.uploading.displayName, "Uploading")
        XCTAssertEqual(UploadStatus.completed.displayName, "Completed")
        XCTAssertEqual(UploadStatus.failed.displayName, "Failed")
        XCTAssertEqual(UploadStatus.cancelled.displayName, "Cancelled")
    }

    func testUploadStatusRawValues() {
        XCTAssertEqual(UploadStatus.uploading.rawValue, "uploading")
        XCTAssertEqual(UploadStatus.completed.rawValue, "completed")
        XCTAssertEqual(UploadStatus.failed.rawValue, "failed")
        XCTAssertEqual(UploadStatus.cancelled.rawValue, "cancelled")
    }

    func testUploadStatusCodable() throws {
        for status in UploadStatus.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(status)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(UploadStatus.self, from: data)

            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: - Identifiable / Equatable

    func testRecordIdentifiable() {
        let record = makeRecord()
        XCTAssertNotNil(record.id)
    }

    func testRecordEquatable() {
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let record1 = UploadRecord(
            id: id,
            filename: "a.png",
            serverPath: "/p/a.png",
            clipboardText: "/p/a.png",
            timestamp: timestamp,
            fileSize: 100,
            status: .completed,
            serverConfigId: serverConfigId
        )
        let record2 = UploadRecord(
            id: id,
            filename: "a.png",
            serverPath: "/p/a.png",
            clipboardText: "/p/a.png",
            timestamp: timestamp,
            fileSize: 100,
            status: .completed,
            serverConfigId: serverConfigId
        )
        XCTAssertEqual(record1, record2)
    }
}
