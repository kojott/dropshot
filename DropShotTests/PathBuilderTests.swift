import XCTest
@testable import DropShot

final class PathBuilderTests: XCTestCase {

    // MARK: - Server Path Mode (no base URL)

    func testBasicServerPath() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "hello.png",
            baseURL: nil
        )
        XCTAssertEqual(result, "/srv/uploads/hello.png")
    }

    func testServerPathWithSpaces() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "my file.png",
            baseURL: nil
        )
        XCTAssertEqual(result, "/srv/uploads/my file.png")
    }

    func testServerPathWithCzechChars() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "pr\u{016F}vodce m\u{011B}stem.pdf",
            baseURL: nil
        )
        // Server path mode: no encoding, raw Unicode preserved
        XCTAssertEqual(result, "/srv/uploads/pr\u{016F}vodce m\u{011B}stem.pdf")
    }

    func testServerPathWithCJK() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "\u{30B9}\u{30AF}\u{30EA}\u{30FC}\u{30F3}.png",
            baseURL: nil
        )
        XCTAssertEqual(result, "/srv/uploads/\u{30B9}\u{30AF}\u{30EA}\u{30FC}\u{30F3}.png")
    }

    func testServerPathWithEmoji() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "photo \u{1F389}.png",
            baseURL: nil
        )
        XCTAssertEqual(result, "/srv/uploads/photo \u{1F389}.png")
    }

    func testServerPathTrailingSlashPresent() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "file.txt",
            baseURL: nil
        )
        XCTAssertEqual(result, "/srv/uploads/file.txt")
    }

    func testServerPathTrailingSlashAbsent() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads",
            filename: "file.txt",
            baseURL: nil
        )
        XCTAssertEqual(result, "/srv/uploads/file.txt")
    }

    func testServerPathEmptyFilename() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "",
            baseURL: nil
        )
        // joinPath trims trailing slash from dir, empty filename -> returns dir
        XCTAssertEqual(result, "/srv/uploads")
    }

    func testServerPathEmptyRemotePath() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "",
            filename: "hello.png",
            baseURL: nil
        )
        XCTAssertEqual(result, "hello.png")
    }

    func testServerPathBothEmpty() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "",
            filename: "",
            baseURL: nil
        )
        // joinPath: both trimmed are empty -> "/"? No: trimmedDir is empty ->
        // returns trimmedFile which is also empty -> returns empty string actually
        // Based on the code: trimmedDir.isEmpty && trimmedFile.isEmpty -> trimmedFile = ""
        XCTAssertEqual(result, "")
    }

    func testServerPathDoubleSlashNormalization() {
        // remotePath ends with /, filename starts with /
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "/file.txt",
            baseURL: nil
        )
        // joinPath trims trailing slash from dir and leading slash from file
        XCTAssertEqual(result, "/srv/uploads/file.txt")
    }

    // MARK: - URL Mode (with base URL)

    func testURLModeBasicFile() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "hello.png",
            baseURL: "https://example.com/uploads/"
        )
        XCTAssertEqual(result, "https://example.com/uploads/hello.png")
    }

    func testURLModeWithSpaces() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "my file.png",
            baseURL: "https://example.com/uploads/"
        )
        XCTAssertEqual(result, "https://example.com/uploads/my%20file.png")
    }

    func testURLModeWithCzechChars() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "pr\u{016F}vodce.pdf",
            baseURL: "https://example.com/uploads/"
        )
        // Diacritics must be percent-encoded per RFC 3986
        let encoded = PathBuilder.percentEncode("pr\u{016F}vodce.pdf")
        XCTAssertEqual(result, "https://example.com/uploads/" + encoded)
        // The encoded result should NOT contain raw non-ASCII characters
        XCTAssertFalse(result.contains("\u{016F}"))
    }

    func testURLModeWithCJK() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "\u{30B9}\u{30AF}\u{30EA}\u{30FC}\u{30F3}.png",
            baseURL: "https://example.com/uploads/"
        )
        // CJK characters should be percent-encoded
        XCTAssertFalse(result.contains("\u{30B9}"))
        XCTAssertTrue(result.hasPrefix("https://example.com/uploads/"))
        XCTAssertTrue(result.hasSuffix(".png"))
    }

    func testURLModeBaseURLTrailingSlash() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "test.png",
            baseURL: "https://example.com/uploads/"
        )
        XCTAssertEqual(result, "https://example.com/uploads/test.png")
        // Should not double slash
        XCTAssertFalse(result.contains("uploads//"))
    }

    func testURLModeBaseURLNoTrailingSlash() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "test.png",
            baseURL: "https://example.com/uploads"
        )
        XCTAssertEqual(result, "https://example.com/uploads/test.png")
    }

    func testURLModeEmptyBaseURL() {
        // Empty base URL should fall through to server path mode
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "hello.png",
            baseURL: ""
        )
        XCTAssertEqual(result, "/srv/uploads/hello.png")
    }

    func testURLModeWithEmoji() {
        let result = PathBuilder.buildClipboardText(
            remotePath: "/srv/uploads/",
            filename: "photo \u{1F389}.png",
            baseURL: "https://example.com/uploads/"
        )
        // Emoji should be percent-encoded
        XCTAssertFalse(result.contains("\u{1F389}"))
        XCTAssertTrue(result.hasPrefix("https://example.com/uploads/"))
    }

    // MARK: - Percent Encoding

    func testPercentEncodePreservesUnreservedChars() {
        let input = "ABCxyz0123456789-._~"
        let result = PathBuilder.percentEncode(input)
        XCTAssertEqual(result, input, "Unreserved characters must not be encoded")
    }

    func testPercentEncodeEncodesSpace() {
        let result = PathBuilder.percentEncode("hello world")
        XCTAssertEqual(result, "hello%20world")
    }

    func testPercentEncodeEncodesParentheses() {
        let result = PathBuilder.percentEncode("photo (1).jpg")
        XCTAssertTrue(result.contains("%28"), "Open parenthesis should be encoded")
        XCTAssertTrue(result.contains("%29"), "Close parenthesis should be encoded")
    }

    func testPercentEncodeMultibyteUTF8() {
        // Czech u with ring above: U+016F -> 2 UTF-8 bytes: C5 AF
        let result = PathBuilder.percentEncode("\u{016F}")
        XCTAssertEqual(result, "%C5%AF")
    }

    // MARK: - Markdown

    func testMarkdownLink() {
        let result = PathBuilder.buildMarkdownLink(
            filename: "screenshot.png",
            clipboardText: "https://example.com/uploads/screenshot.png"
        )
        XCTAssertEqual(result, "![screenshot.png](https://example.com/uploads/screenshot.png)")
    }

    func testMarkdownLinkWithServerPath() {
        let result = PathBuilder.buildMarkdownLink(
            filename: "photo.jpg",
            clipboardText: "/srv/uploads/photo.jpg"
        )
        XCTAssertEqual(result, "![photo.jpg](/srv/uploads/photo.jpg)")
    }

    // MARK: - Multiple Files

    func testMultipleClipboardServerPaths() {
        let items: [(remotePath: String, filename: String)] = [
            ("/srv/uploads/", "file1.png"),
            ("/srv/uploads/", "file2.jpg"),
            ("/srv/uploads/", "file3.pdf")
        ]
        let result = PathBuilder.buildMultipleClipboardText(items: items, baseURL: nil)
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "/srv/uploads/file1.png")
        XCTAssertEqual(lines[1], "/srv/uploads/file2.jpg")
        XCTAssertEqual(lines[2], "/srv/uploads/file3.pdf")
    }

    func testMultipleClipboardURLs() {
        let items: [(remotePath: String, filename: String)] = [
            ("/srv/uploads/", "file1.png"),
            ("/srv/uploads/", "file 2.jpg")
        ]
        let result = PathBuilder.buildMultipleClipboardText(
            items: items,
            baseURL: "https://cdn.example.com/"
        )
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "https://cdn.example.com/file1.png")
        XCTAssertEqual(lines[1], "https://cdn.example.com/file%202.jpg")
    }

    func testEmptyMultiple() {
        let items: [(remotePath: String, filename: String)] = []
        let result = PathBuilder.buildMultipleClipboardText(items: items, baseURL: nil)
        XCTAssertEqual(result, "")
    }

    func testSingleItemMultiple() {
        let items: [(remotePath: String, filename: String)] = [
            ("/srv/uploads/", "only.png")
        ]
        let result = PathBuilder.buildMultipleClipboardText(items: items, baseURL: nil)
        XCTAssertEqual(result, "/srv/uploads/only.png")
        // Should not have a trailing newline
        XCTAssertFalse(result.hasSuffix("\n"))
    }
}
