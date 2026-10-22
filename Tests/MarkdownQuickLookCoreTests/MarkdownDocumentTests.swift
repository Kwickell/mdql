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
        // 0xE5, 0xE4 and 0xF6 are å, ä and ö in Latin-1 and invalid UTF-8.
        let data = "# Rubrik med å ä ö\n".data(using: .isoLatin1)!
        XCTAssertEqual(MarkdownDocument.decodeText(data), "# Rubrik med å ä ö\n")
    }

    func testDecodesWindows1252Punctuation() {
        // 0x92 is a right single quote in Windows-1252 and undefined in Latin-1.
        let data = Data([0x69, 0x74, 0x92, 0x73])
        XCTAssertEqual(MarkdownDocument.decodeText(data), "it\u{2019}s")
    }

    func testDecodesUTF16LittleEndianWithBOM() {
        let data = Data([0xFF, 0xFE]) + "# Title".data(using: .utf16LittleEndian)!
        XCTAssertEqual(MarkdownDocument.decodeText(data), "# Title")
    }

    func testDecodesUTF16BigEndianWithBOM() {
        let data = Data([0xFE, 0xFF]) + "# Title".data(using: .utf16BigEndian)!
        XCTAssertEqual(MarkdownDocument.decodeText(data), "# Title")
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
        let line = String(repeating: "x", count: 1023) + "\n"
        let file = try write(String(repeating: line, count: 5000), to: "big.md")

        let document = try MarkdownDocument.load(contentsOf: file)
        XCTAssertTrue(document.truncated)
        XCTAssertTrue(document.text.hasSuffix("Preview truncated at 4 MB.\n"))
        XCTAssertLessThan(document.text.utf8.count, MarkdownDocument.byteLimit + 200)
    }

    func testTruncationDoesNotCorruptMultiByteCharacters() throws {
        // One long run of three-byte characters, so the byte limit cannot help
        // but land inside one of them.
        let file = try write(String(repeating: "あ", count: MarkdownDocument.byteLimit / 3 + 2048), to: "wide.md")

        let document = try MarkdownDocument.load(contentsOf: file)
        XCTAssertTrue(document.truncated)
        XCTAssertTrue(document.text.hasPrefix("あああ"))
        XCTAssertFalse(document.text.contains("\u{FFFD}"))
    }

    func testTruncationCutsAtALineBoundaryWithCRLF() throws {
        let line = String(repeating: "A", count: 64)
        var text = ""
        while text.utf8.count < MarkdownDocument.byteLimit + 4096 { text += line + "\r\n" }
        let file = try write(text, to: "crlf.md")

        let document = try MarkdownDocument.load(contentsOf: file)
        let body = document.text.components(separatedBy: "\n\n> [!NOTE]")[0]
        XCTAssertTrue(document.truncated)
        XCTAssertTrue(body.hasSuffix(line), "truncation should land on a whole line")
    }

    func testTruncationClosesAnOpenCodeFence() throws {
        var text = "# Big\n\n```swift\n"
        while text.utf8.count < MarkdownDocument.byteLimit + 4096 { text += "let value = 1\n" }
        let file = try write(text, to: "fenced.md")

        let document = try MarkdownDocument.load(contentsOf: file)
        let beforeNote = document.text.components(separatedBy: "> [!NOTE]")[0]
        XCTAssertTrue(beforeNote.hasSuffix("```\n\n"), "the note must not end up inside the code block")
    }

    func testUnclosedFenceDetection() {
        XCTAssertNil(MarkdownDocument.unclosedFence(in: "plain text"))
        XCTAssertNil(MarkdownDocument.unclosedFence(in: "```\ncode\n```\n"))
        XCTAssertEqual(MarkdownDocument.unclosedFence(in: "```swift\ncode\n"), "```")
        XCTAssertEqual(MarkdownDocument.unclosedFence(in: "~~~\ncode\n"), "~~~")
        XCTAssertNil(MarkdownDocument.unclosedFence(in: "````\n```\ncode\n````\n"))
        XCTAssertEqual(MarkdownDocument.unclosedFence(in: "````\n```\ncode\n"), "````")
    }

    private func write(_ text: String, to name: String) throws -> URL {
        let file = try makeTemporaryDirectory().appendingPathComponent(name)
        try Data(text.utf8).write(to: file)
        return file
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mdql-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
