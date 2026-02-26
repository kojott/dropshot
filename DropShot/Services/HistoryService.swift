import Foundation

// MARK: - History Service Errors

enum HistoryServiceError: LocalizedError {
    case directoryCreationFailed(Error)
    case saveFailed(Error)
    case loadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "Failed to create history storage directory: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save upload history: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load upload history: \(error.localizedDescription)"
        }
    }
}

// MARK: - History Service

actor HistoryService {
    static let shared = HistoryService()

    private let maxRecords = 500
    private var records: [UploadRecord] = []
    private let fileURL: URL
    private var isLoaded = false

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dropShotDir = appSupport.appendingPathComponent("DropShot", isDirectory: true)
        self.fileURL = dropShotDir.appendingPathComponent("history.json")
    }

    /// Internal initializer for testing with a custom storage location.
    /// Accessible via `@testable import DropShot`.
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Public API

    /// Adds a new upload record and persists to disk.
    func addRecord(_ record: UploadRecord) {
        ensureLoaded()
        records.insert(record, at: 0)
        trimExcessRecords()
        saveSilently()
    }

    /// Returns the most recent upload records, sorted by date descending.
    func recentRecords(limit: Int = 10) -> [UploadRecord] {
        ensureLoaded()
        let clampedLimit = max(0, min(limit, records.count))
        return Array(records.prefix(clampedLimit))
    }

    /// Searches records by filename using a case-insensitive substring match.
    func search(query: String) -> [UploadRecord] {
        ensureLoaded()
        guard !query.isEmpty else { return records }
        let lowercasedQuery = query.lowercased()
        return records.filter { record in
            record.filename.lowercased().contains(lowercasedQuery)
        }
    }

    /// Updates an existing record in place (e.g., when upload completes or fails).
    /// Matches by record ID. If no matching record is found, the update is ignored.
    func updateRecord(_ record: UploadRecord) {
        ensureLoaded()
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            return
        }
        records[index] = record
        saveSilently()
    }

    /// Deletes a specific record by its UUID.
    func deleteRecord(id: UUID) {
        ensureLoaded()
        records.removeAll { $0.id == id }
        saveSilently()
    }

    /// Removes all upload history and persists the empty state.
    func clearAll() {
        records.removeAll()
        saveSilently()
    }

    /// Loads records from the JSON file on disk. Safe to call multiple times;
    /// subsequent calls reload from disk (useful if the file was modified externally).
    func load() throws {
        let fileManager = FileManager.default

        // Ensure the Application Support/DropShot directory exists.
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw HistoryServiceError.directoryCreationFailed(error)
            }
        }

        // If the history file doesn't exist yet, start with an empty array.
        guard fileManager.fileExists(atPath: fileURL.path) else {
            records = []
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([UploadRecord].self, from: data)
            // Ensure records are sorted newest first.
            records.sort { $0.timestamp > $1.timestamp }
            isLoaded = true
        } catch {
            throw HistoryServiceError.loadFailed(error)
        }
    }

    /// Returns the total number of stored records.
    func recordCount() -> Int {
        ensureLoaded()
        return records.count
    }

    /// Returns all records associated with a specific server configuration.
    func records(forServerConfigId configId: UUID) -> [UploadRecord] {
        ensureLoaded()
        return records.filter { $0.serverConfigId == configId }
    }

    // MARK: - Private Helpers

    /// Persists the current records array to disk as pretty-printed JSON.
    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw HistoryServiceError.directoryCreationFailed(error)
            }
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw HistoryServiceError.saveFailed(error)
        }
    }

    /// Saves to disk, printing errors to the console rather than throwing.
    /// Used by mutating methods that should not force callers to handle I/O errors.
    private func saveSilently() {
        do {
            try save()
        } catch {
            print("[HistoryService] \(error.localizedDescription)")
        }
    }

    /// Lazily loads records from disk on first access if not already loaded.
    private func ensureLoaded() {
        guard !isLoaded else { return }
        do {
            try load()
        } catch {
            print("[HistoryService] Failed to load history on first access: \(error.localizedDescription)")
            records = []
            isLoaded = true
        }
    }

    /// Trims the oldest records if the total count exceeds the maximum.
    private func trimExcessRecords() {
        guard records.count > maxRecords else { return }
        records = Array(records.prefix(maxRecords))
    }
}
