import Foundation

// MARK: - Path Builder

/// Stateless utility for building clipboard text and URLs from upload results.
struct PathBuilder {

    // MARK: - Clipboard Text

    /// Builds the text to copy to the clipboard after an upload.
    ///
    /// - Parameters:
    ///   - remotePath: The remote directory path (e.g. `/srv/uploads/`).
    ///   - filename: The uploaded filename.
    ///   - baseURL: Optional public base URL (e.g. `https://example.com/uploads/`).
    /// - Returns: A public URL if `baseURL` is provided, otherwise the absolute server path.
    static func buildClipboardText(remotePath: String, filename: String, baseURL: String?) -> String {
        if let baseURL = baseURL, !baseURL.isEmpty {
            let normalizedBase = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
            let encoded = percentEncode(filename)
            return normalizedBase + encoded
        }
        return joinPath(remotePath, filename)
    }

    /// Percent-encodes a filename for use in a URL per RFC 3986.
    ///
    /// Preserves unreserved characters (A-Z, a-z, 0-9, `-`, `.`, `_`, `~`) and
    /// encodes everything else including spaces and non-ASCII characters.
    static func percentEncode(_ filename: String) -> String {
        // RFC 3986 unreserved characters that are safe in a path segment.
        // We intentionally exclude `/` since we are encoding a single filename, not a path.
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? filename
    }

    /// Builds a Markdown image link.
    ///
    /// - Parameters:
    ///   - filename: Display name for the link.
    ///   - clipboardText: The URL or path to use as the link target.
    /// - Returns: A Markdown image reference, e.g. `![filename](url)`.
    static func buildMarkdownLink(filename: String, clipboardText: String) -> String {
        "![\(filename)](\(clipboardText))"
    }

    /// Builds multi-line clipboard text for multiple uploaded files.
    ///
    /// Each item appears on its own line.
    ///
    /// - Parameters:
    ///   - items: Array of tuples with remote path and filename for each upload.
    ///   - baseURL: Optional public base URL applied to all items.
    /// - Returns: Newline-separated clipboard entries.
    static func buildMultipleClipboardText(
        items: [(remotePath: String, filename: String)],
        baseURL: String?
    ) -> String {
        items
            .map { buildClipboardText(remotePath: $0.remotePath, filename: $0.filename, baseURL: baseURL) }
            .joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Joins a directory path and filename, ensuring exactly one `/` separator.
    private static func joinPath(_ directory: String, _ filename: String) -> String {
        let trimmedDir = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        let trimmedFile = filename.hasPrefix("/") ? String(filename.dropFirst()) : filename

        if trimmedDir.isEmpty {
            return trimmedFile
        }
        if trimmedFile.isEmpty {
            return trimmedDir
        }
        return trimmedDir + "/" + trimmedFile
    }
}
