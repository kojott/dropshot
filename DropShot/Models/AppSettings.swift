import Foundation

// MARK: - Filename Pattern

enum FilenamePattern: String, Codable, CaseIterable {
    case original = "original"
    case dateTimeOriginal = "dateTimeOriginal"
    case uuid = "uuid"
    case hash = "hash"

    var displayName: String {
        switch self {
        case .original: return "Original Filename"
        case .dateTimeOriginal: return "Date-Time + Original"
        case .uuid: return "UUID"
        case .hash: return "Content Hash"
        }
    }

    var description: String {
        switch self {
        case .original: return "screenshot.png"
        case .dateTimeOriginal: return "2026-02-26_143052_screenshot.png"
        case .uuid: return "a1b2c3d4-e5f6-7890.png"
        case .hash: return "8f14e45f.png"
        }
    }
}

// MARK: - Duplicate Handling

enum DuplicateHandling: String, Codable, CaseIterable {
    case appendSuffix = "appendSuffix"
    case overwrite = "overwrite"

    var displayName: String {
        switch self {
        case .appendSuffix: return "Append Suffix (-1, -2, ...)"
        case .overwrite: return "Overwrite Existing"
        }
    }
}

// MARK: - Remote File TTL

enum RemoteFileTTL: String, Codable, CaseIterable {
    case oneHour = "1h"
    case sixHours = "6h"
    case twelveHours = "12h"
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"

    var displayName: String {
        switch self {
        case .oneHour: return "1 Hour"
        case .sixHours: return "6 Hours"
        case .twelveHours: return "12 Hours"
        case .oneDay: return "1 Day"
        case .sevenDays: return "7 Days"
        case .thirtyDays: return "30 Days"
        case .ninetyDays: return "90 Days"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .sixHours: return 21600
        case .twelveHours: return 43200
        case .oneDay: return 86400
        case .sevenDays: return 604800
        case .thirtyDays: return 2592000
        case .ninetyDays: return 7776000
        }
    }
}

// MARK: - App Settings

struct AppSettings: Codable, Equatable {

    // File handling
    var filenamePattern: FilenamePattern
    var maxFileSizeMB: Int
    var duplicateHandling: DuplicateHandling

    // App behavior
    var launchAtLogin: Bool
    var showNotifications: Bool
    var playSound: Bool

    // Shortcuts
    var screenshotShortcutEnabled: Bool
    var clipboardUploadShortcutEnabled: Bool

    // Cleanup
    var deleteLocalAfterUpload: Bool
    var autoDeleteRemoteFiles: Bool
    var remoteFileTTL: RemoteFileTTL

    // Onboarding
    var hasCompletedSetup: Bool

    init(
        filenamePattern: FilenamePattern = .original,
        maxFileSizeMB: Int = 100,
        duplicateHandling: DuplicateHandling = .appendSuffix,
        launchAtLogin: Bool = false,
        showNotifications: Bool = true,
        playSound: Bool = false,
        screenshotShortcutEnabled: Bool = true,
        clipboardUploadShortcutEnabled: Bool = false,
        deleteLocalAfterUpload: Bool = true,
        autoDeleteRemoteFiles: Bool = false,
        remoteFileTTL: RemoteFileTTL = .sevenDays,
        hasCompletedSetup: Bool = false
    ) {
        self.filenamePattern = filenamePattern
        self.maxFileSizeMB = maxFileSizeMB
        self.duplicateHandling = duplicateHandling
        self.launchAtLogin = launchAtLogin
        self.showNotifications = showNotifications
        self.playSound = playSound
        self.screenshotShortcutEnabled = screenshotShortcutEnabled
        self.clipboardUploadShortcutEnabled = clipboardUploadShortcutEnabled
        self.deleteLocalAfterUpload = deleteLocalAfterUpload
        self.autoDeleteRemoteFiles = autoDeleteRemoteFiles
        self.remoteFileTTL = remoteFileTTL
        self.hasCompletedSetup = hasCompletedSetup
    }

    // MARK: - Computed Properties

    /// Maximum file size in bytes. Returns Int64.max when unlimited (0).
    var maxFileSizeBytes: Int64 {
        maxFileSizeMB == 0 ? Int64.max : Int64(maxFileSizeMB) * 1_048_576
    }

    /// Whether file size limiting is enabled.
    var hasFileSizeLimit: Bool {
        maxFileSizeMB > 0
    }

    // MARK: - UserDefaults Persistence

    private static let userDefaultsKey = "com.dropshot.appSettings"

    /// Shared singleton that auto-loads from UserDefaults.
    /// Mutations must be explicitly saved via `save()`.
    static var shared: AppSettings = {
        return AppSettings.load()
    }()

    /// Loads settings from UserDefaults, returning defaults if nothing is stored.
    private static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return AppSettings()
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            // If decoding fails (e.g. schema changed), reset to defaults
            return AppSettings()
        }
    }

    /// Persists current settings to UserDefaults.
    func save() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            UserDefaults.standard.set(data, forKey: AppSettings.userDefaultsKey)
            AppSettings.shared = self
        } catch {
            assertionFailure("Failed to encode AppSettings: \(error)")
        }
    }

    /// Resets all settings to their defaults and persists.
    static func resetToDefaults() {
        let defaults = AppSettings()
        defaults.save()
    }
}
