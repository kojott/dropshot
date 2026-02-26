import Foundation
import CryptoKit

// MARK: - File Validation Result

/// Outcome of validating a local file before upload.
enum FileValidationResult: Equatable {
    case valid(fileSize: Int64)
    case notFound
    case isDirectory
    case notReadable
    case empty
    case tooLarge(size: Int64, limit: Int64)
}

// MARK: - File Processor

/// Stateless utility for sanitizing filenames and validating files before upload.
struct FileProcessor {

    /// Maximum allowed filename length in UTF-8 bytes.
    static let maxFilenameBytes = 200

    /// Default maximum file size: 2 GB.
    static let defaultMaxFileSize: Int64 = 2 * 1024 * 1024 * 1024

    // MARK: - Filename Sanitization

    /// Sanitizes a filename for safe use on a remote server.
    ///
    /// - Strips path traversal components (`../`, `./`, leading `/`)
    /// - Removes null bytes
    /// - Normalizes Unicode to NFC
    /// - Truncates to ``maxFilenameBytes`` UTF-8 bytes while preserving the file extension
    /// - Falls back to `"unnamed"` if the result is empty
    static func sanitize(_ filename: String) -> String {
        var name = filename

        // Remove null bytes
        name = name.replacingOccurrences(of: "\0", with: "")

        // Strip path traversal: split on separators and take last non-traversal component
        let components = name.components(separatedBy: "/")
        name = components
            .last { component in
                !component.isEmpty && component != "." && component != ".."
            } ?? ""

        // Remove any remaining leading dots that form traversal patterns
        while name.hasPrefix("../") || name.hasPrefix("./") {
            if name.hasPrefix("../") {
                name = String(name.dropFirst(3))
            } else if name.hasPrefix("./") {
                name = String(name.dropFirst(2))
            }
        }

        // Strip leading slashes
        while name.hasPrefix("/") {
            name = String(name.dropFirst())
        }

        // NFC normalize
        name = normalizeToNFC(name)

        // Trim whitespace
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fallback for empty result
        if name.isEmpty {
            return "unnamed"
        }

        // Truncate to maxFilenameBytes while preserving extension
        name = truncateToByteLimit(name, maxBytes: maxFilenameBytes)

        return name
    }

    // MARK: - Filename Resolution

    /// Resolves a final filename from the original name, a naming pattern, and an extension.
    ///
    /// - Parameters:
    ///   - original: The original (unsanitized) filename.
    ///   - pattern: The ``FilenamePattern`` to apply.
    ///   - ext: The file extension (without leading dot). If empty, no extension is appended.
    /// - Returns: The resolved filename, sanitized and ready for upload.
    static func resolveFilename(original: String, pattern: FilenamePattern, extension ext: String) -> String {
        let sanitizedOriginal = sanitize(original)

        switch pattern {
        case .original:
            return sanitizedOriginal

        case .dateTimeOriginal:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            let datePrefix = formatter.string(from: Date())
            // Strip extension from sanitized original to avoid double extension
            let baseName = stripExtension(from: sanitizedOriginal)
            let result = ext.isEmpty ? "\(datePrefix)_\(baseName)" : "\(datePrefix)_\(baseName).\(ext)"
            return sanitize(result)

        case .uuid:
            let uuidString = UUID().uuidString.lowercased()
            return ext.isEmpty ? uuidString : "\(uuidString).\(ext)"

        case .hash:
            let input = original + String(Date().timeIntervalSince1970)
            let digest = SHA256.hash(data: Data(input.utf8))
            let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
            let truncatedHash = String(hashString.prefix(12))
            return ext.isEmpty ? truncatedHash : "\(truncatedHash).\(ext)"
        }
    }

    // MARK: - Suffix Appending

    /// Appends a numeric suffix to a filename for deduplication.
    ///
    /// Examples:
    /// - `appendSuffix("photo.png", suffix: 1)` returns `"photo (1).png"`
    /// - `appendSuffix("photo.png", suffix: 2)` returns `"photo (2).png"`
    /// - `appendSuffix("readme", suffix: 3)` returns `"readme (3)"`
    static func appendSuffix(_ filename: String, suffix: Int) -> String {
        let ext = fileExtension(from: filename)
        let base = stripExtension(from: filename)

        if ext.isEmpty {
            return "\(base) (\(suffix))"
        }
        return "\(base) (\(suffix)).\(ext)"
    }

    // MARK: - Unicode Normalization

    /// Normalizes a string to Unicode NFC (Canonical Composition).
    static func normalizeToNFC(_ string: String) -> String {
        (string as NSString).precomposedStringWithCanonicalMapping
    }

    // MARK: - File Validation

    /// Validates that a local file is suitable for upload.
    ///
    /// - Parameters:
    ///   - url: The file URL to validate.
    ///   - maxSize: Maximum allowed file size in bytes. Defaults to ``defaultMaxFileSize``.
    /// - Returns: A ``FileValidationResult`` describing the outcome.
    static func isValidFile(at url: URL, maxSize: Int64 = defaultMaxFileSize) -> FileValidationResult {
        let fileManager = FileManager.default
        let path = url.path

        // Check existence
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .notFound
        }

        // Check it is not a directory, symlink to directory, or bundle
        if isDirectory.boolValue {
            return .isDirectory
        }

        // Check readable
        guard fileManager.isReadableFile(atPath: path) else {
            return .notReadable
        }

        // Get file attributes
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? Int64 else {
            return .notReadable
        }

        // Check non-empty
        if fileSize == 0 {
            return .empty
        }

        // Check size limit
        if fileSize > maxSize {
            return .tooLarge(size: fileSize, limit: maxSize)
        }

        return .valid(fileSize: fileSize)
    }

    // MARK: - Private Helpers

    /// Extracts the file extension from a filename (without the leading dot).
    private static func fileExtension(from filename: String) -> String {
        let nsName = filename as NSString
        let ext = nsName.pathExtension
        return ext
    }

    /// Strips the file extension from a filename.
    private static func stripExtension(from filename: String) -> String {
        let nsName = filename as NSString
        let ext = nsName.pathExtension
        if ext.isEmpty {
            return filename
        }
        return nsName.deletingPathExtension
    }

    /// Truncates a filename to fit within a UTF-8 byte limit while preserving the file extension.
    private static func truncateToByteLimit(_ filename: String, maxBytes: Int) -> String {
        guard filename.utf8.count > maxBytes else {
            return filename
        }

        let ext = fileExtension(from: filename)
        let base = stripExtension(from: filename)

        // Account for the dot separator if there is an extension
        let extensionBytes = ext.isEmpty ? 0 : ext.utf8.count + 1 // +1 for the dot
        let availableBytes = maxBytes - extensionBytes

        guard availableBytes > 0 else {
            // Extension itself exceeds the limit; truncate at byte boundary
            var result = ""
            for scalar in filename.unicodeScalars {
                let candidate = result + String(scalar)
                if candidate.utf8.count > maxBytes { break }
                result = candidate
            }
            return result
        }

        // Truncate base at a unicode scalar boundary that fits within availableBytes
        var truncatedBase = ""
        for scalar in base.unicodeScalars {
            let candidate = truncatedBase + String(scalar)
            if candidate.utf8.count > availableBytes {
                break
            }
            truncatedBase = candidate
        }

        // Edge case: if truncation removed everything
        if truncatedBase.isEmpty {
            truncatedBase = "unnamed"
            // If even "unnamed" + extension is too long, just return what fits
            let result = ext.isEmpty ? truncatedBase : "\(truncatedBase).\(ext)"
            if result.utf8.count > maxBytes {
                return String(result.prefix(maxBytes))
            }
            return result
        }

        return ext.isEmpty ? truncatedBase : "\(truncatedBase).\(ext)"
    }
}
