import XCTest
@testable import MarkdownQuickLookCore

final class MarkdownDocumentTests: XCTestCase {
    func testDecodesUTF8() {
        let data = Data("# Rubrik med å ä ö".utf8)
        XCTAssertEqual(MarkdownDocument.decodeText(data), "# Rubrik med å ä ö")
    }

    func testStripsByteOrderMark() {
        let data = Data("\u{FEFF}# Title".utf8)
        XCTAssertEqual(MarkdownDocument.decodeText(data), "# Title")
    }

    func testDecodesUTF16WithBOM() {
        let data = "# Title".data(using: .utf16)!
        XCTAssertEqual(MarkdownDocument.decodeText(data), "# Title")
    }

    func testDecodesLatin1WhenNotValidUTF8() {
        // 0xE5 is "å" in Latin-1 and an invalid lead byte in UTF-8.
        let data = Data([0x68, 0xE5, 0x72])
        let text = MarkdownDocument.decodeText(data)
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains("\u{FFFD}"))
    }

    func testEmptyDataDecodesToEmptyString() {
        XCTAssertEqual(MarkdownDocument.decodeText(Data()), "")
    }

    func testLoadReadsFileAndKeepsDirectory() throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("note.md")
        try Data("hello".utf8).write(to: file)

        let document = try MarkdownDocument.load(contentsOf: file)
        XCTAssertEqual(document.text, "hello")
        XCTAssertEqual(document.title, "note.md")
        XCTAssertFalse(document.truncated)
        XCTAssertEqual(document.directory.standardizedFileURL.path, directory.standardizedFileURL.path)
    }

    func testLoadTruncatesOversizedFile() throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("big.md")
        let line = String(repeating: "x", count: 1023) + "\n"
        try Data(String(repeating: line, count: 5000).utf8).write(to: file)

        let document = try MarkdownDocument.load(contentsOf: file)
        XCTAssertTrue(document.truncated)
        XCTAssertTrue(document.text.hasSuffix("Preview truncated at 4 MB.\n"))
        XCTAssertLessThan(document.text.utf8.count, MarkdownDocument.byteLimit + 200)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mdql-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
