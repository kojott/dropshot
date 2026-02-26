import XCTest
@testable import DropShot

final class HistoryServiceTests: XCTestCase {

    // MARK: - Properties

    private var tempDirectory: URL!
    private var historyFileURL: URL!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryServiceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        historyFileURL = tempDirectory.appendingPathComponent("history.json")
    }

    override func tearDown() {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService() -> HistoryService {
        HistoryService(fileURL: historyFileURL)
    }

    private let serverConfigId = UUID()

    private func makeRecord(
        filename: String = "test.png",
        timestamp: Date = Date(),
        fileSize: Int64 = 1024,
        status: UploadStatus = .completed
    ) -> UploadRecord {
        UploadRecord(
            filename: filename,
            serverPath: "/srv/uploads/\(filename)",
            publicURL: nil,
            clipboardText: "/srv/uploads/\(filename)",
            timestamp: timestamp,
            fileSize: fileSize,
            status: status,
            serverConfigId: serverConfigId
        )
    }

    // MARK: - Add and Retrieve

    func testAddAndRetrieveRecord() async {
        let service = makeService()
        let record = makeRecord(filename: "photo.png")

        await service.addRecord(record)

        let records = await service.recentRecords(limit: 10)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.filename, "photo.png")
        XCTAssertEqual(records.first?.id, record.id)
    }

    func testAddMultipleRecords() async {
        let service = makeService()

        for i in 0..<5 {
            let record = makeRecord(
                filename: "file\(i).png",
                timestamp: Date().addingTimeInterval(Double(i))
            )
            await service.addRecord(record)
        }

        let records = await service.recentRecords(limit: 10)
        XCTAssertEqual(records.count, 5)
    }

    // MARK: - Recent Records Ordering

    func testRecentRecordsOrdering() async {
        let service = makeService()

        let oldest = makeRecord(filename: "oldest.png", timestamp: Date().addingTimeInterval(-100))
        let middle = makeRecord(filename: "middle.png", timestamp: Date().addingTimeInterval(-50))
        let newest = makeRecord(filename: "newest.png", timestamp: Date())

        // Add in non-chronological order
        await service.addRecord(middle)
        await service.addRecord(oldest)
        await service.addRecord(newest)

        let records = await service.recentRecords(limit: 10)
        XCTAssertEqual(records.count, 3)
        // Records are inserted at index 0, so the last inserted is first
        // The addRecord always inserts at index 0, so order is: newest, oldest, middle
        XCTAssertEqual(records[0].filename, "newest.png")
    }

    // MARK: - Recent Records Limit

    func testRecentRecordsLimit() async {
        let service = makeService()

        for i in 0..<10 {
            let record = makeRecord(
                filename: "file\(i).png",
                timestamp: Date().addingTimeInterval(Double(i))
            )
            await service.addRecord(record)
        }

        let limited = await service.recentRecords(limit: 3)
        XCTAssertEqual(limited.count, 3)
    }

    func testRecentRecordsLimitLargerThanCount() async {
        let service = makeService()
        await service.addRecord(makeRecord(filename: "only.png"))

        let records = await service.recentRecords(limit: 100)
        XCTAssertEqual(records.count, 1)
    }

    func testRecentRecordsLimitZero() async {
        let service = makeService()
        await service.addRecord(makeRecord())

        let records = await service.recentRecords(limit: 0)
        XCTAssertEqual(records.count, 0)
    }

    // MARK: - Search

    func testSearchByFilename() async {
        let service = makeService()

        await service.addRecord(makeRecord(filename: "screenshot.png"))
        await service.addRecord(makeRecord(filename: "photo.jpg"))
        await service.addRecord(makeRecord(filename: "screenshot_2.png"))

        let results = await service.search(query: "screenshot")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.filename.contains("screenshot") })
    }

    func testSearchCaseInsensitive() async {
        let service = makeService()

        await service.addRecord(makeRecord(filename: "Screenshot.PNG"))
        await service.addRecord(makeRecord(filename: "other.jpg"))

        let results = await service.search(query: "screenshot")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.filename, "Screenshot.PNG")
    }

    func testSearchEmptyQuery() async {
        let service = makeService()

        await service.addRecord(makeRecord(filename: "a.png"))
        await service.addRecord(makeRecord(filename: "b.png"))

        let results = await service.search(query: "")
        XCTAssertEqual(results.count, 2, "Empty query should return all records")
    }

    func testSearchNoResults() async {
        let service = makeService()

        await service.addRecord(makeRecord(filename: "photo.png"))

        let results = await service.search(query: "nonexistent")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Update Record

    func testUpdateRecord() async {
        let service = makeService()
        let record = makeRecord(filename: "uploading.png", status: .uploading)

        await service.addRecord(record)

        // Create a completed version with the same ID
        let completed = record.completed(duration: 2.0, publicURL: "https://cdn.example.com/uploading.png")
        await service.updateRecord(completed)

        let records = await service.recentRecords(limit: 10)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.status, .completed)
        XCTAssertEqual(records.first?.publicURL, "https://cdn.example.com/uploading.png")
        XCTAssertEqual(records.first?.uploadDuration, 2.0)
    }

    func testUpdateNonExistentRecordIsIgnored() async {
        let service = makeService()
        await service.addRecord(makeRecord(filename: "existing.png"))

        let phantom = makeRecord(filename: "phantom.png")
        await service.updateRecord(phantom)

        let count = await service.recordCount()
        XCTAssertEqual(count, 1, "Updating a non-existent record should not add it")
    }

    // MARK: - Delete Record

    func testDeleteRecord() async {
        let service = makeService()
        let record = makeRecord(filename: "to-delete.png")

        await service.addRecord(record)
        let countBefore = await service.recordCount()
        XCTAssertEqual(countBefore, 1)

        await service.deleteRecord(id: record.id)

        let countAfter = await service.recordCount()
        XCTAssertEqual(countAfter, 0)
    }

    func testDeleteNonExistentRecordNoOp() async {
        let service = makeService()
        await service.addRecord(makeRecord(filename: "safe.png"))

        await service.deleteRecord(id: UUID())

        let count = await service.recordCount()
        XCTAssertEqual(count, 1, "Deleting a non-existent ID should not affect existing records")
    }

    // MARK: - Clear All

    func testClearAll() async {
        let service = makeService()

        for i in 0..<5 {
            await service.addRecord(makeRecord(filename: "file\(i).png"))
        }

        let countBefore = await service.recordCount()
        XCTAssertEqual(countBefore, 5)

        await service.clearAll()

        let countAfter = await service.recordCount()
        XCTAssertEqual(countAfter, 0)

        let records = await service.recentRecords(limit: 100)
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - Persistence

    func testPersistence() async throws {
        // Create a service, add a record, and let it save
        let service1 = makeService()
        let record = makeRecord(filename: "persisted.png", fileSize: 9999)
        await service1.addRecord(record)

        // Verify the file was written
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyFileURL.path),
                       "History file should be written to disk")

        // Create a NEW service instance pointing to the same file
        let service2 = HistoryService(fileURL: historyFileURL)

        // Load explicitly
        try await service2.load()

        let records = await service2.recentRecords(limit: 10)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.filename, "persisted.png")
        XCTAssertEqual(records.first?.fileSize, 9999)
        XCTAssertEqual(records.first?.id, record.id)
    }

    func testPersistenceAfterClearAll() async throws {
        let service1 = makeService()
        await service1.addRecord(makeRecord(filename: "gone.png"))
        await service1.clearAll()

        let service2 = HistoryService(fileURL: historyFileURL)
        try await service2.load()

        let count = await service2.recordCount()
        XCTAssertEqual(count, 0, "Cleared state should persist")
    }

    // MARK: - Max Records Trimming

    func testMaxRecordsTrimming() async {
        let service = makeService()

        // The maxRecords is 500; add 510 records
        for i in 0..<510 {
            let record = makeRecord(
                filename: "file\(i).png",
                timestamp: Date().addingTimeInterval(Double(i))
            )
            await service.addRecord(record)
        }

        let count = await service.recordCount()
        XCTAssertLessThanOrEqual(count, 500,
                                  "Record count should not exceed maxRecords (500)")
    }

    // MARK: - Record Count

    func testRecordCount() async {
        let service = makeService()

        let emptyCount = await service.recordCount()
        XCTAssertEqual(emptyCount, 0)

        await service.addRecord(makeRecord(filename: "a.png"))
        await service.addRecord(makeRecord(filename: "b.png"))

        let count = await service.recordCount()
        XCTAssertEqual(count, 2)
    }

    // MARK: - Records for Server Config

    func testRecordsForServerConfigId() async {
        let service = makeService()
        let otherConfigId = UUID()

        let record1 = UploadRecord(
            filename: "mine.png",
            serverPath: "/p/mine.png",
            clipboardText: "/p/mine.png",
            timestamp: Date(),
            fileSize: 100,
            serverConfigId: serverConfigId
        )
        let record2 = UploadRecord(
            filename: "theirs.png",
            serverPath: "/p/theirs.png",
            clipboardText: "/p/theirs.png",
            timestamp: Date(),
            fileSize: 200,
            serverConfigId: otherConfigId
        )

        await service.addRecord(record1)
        await service.addRecord(record2)

        let myRecords = await service.records(forServerConfigId: serverConfigId)
        XCTAssertEqual(myRecords.count, 1)
        XCTAssertEqual(myRecords.first?.filename, "mine.png")

        let theirRecords = await service.records(forServerConfigId: otherConfigId)
        XCTAssertEqual(theirRecords.count, 1)
        XCTAssertEqual(theirRecords.first?.filename, "theirs.png")
    }

    // MARK: - Load from Empty State

    func testLoadWithNoExistingFile() async throws {
        let service = makeService()
        // No file exists yet
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyFileURL.path))

        try await service.load()

        let count = await service.recordCount()
        XCTAssertEqual(count, 0)
    }

    func testLoadCreatesDirectoryIfNeeded() async throws {
        // Use a file URL inside a non-existent subdirectory
        let nestedDir = tempDirectory.appendingPathComponent("nested/deep", isDirectory: true)
        let nestedFile = nestedDir.appendingPathComponent("history.json")
        let service = HistoryService(fileURL: nestedFile)

        try await service.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedDir.path),
                       "load() should create the directory structure if missing")
    }
}
