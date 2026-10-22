import Foundation

/// Text of a markdown file, decoded for display.
public struct MarkdownDocument {
    public let text: String
    public let title: String
    public let directory: URL
    public let truncated: Bool

    /// Files above this size are truncated: Quick Look has a few hundred
    /// milliseconds to produce something, and nobody reads a 20 MB preview.
    public static let byteLimit = 4 * 1024 * 1024

    public init(text: String, title: String, directory: URL, truncated: Bool = false) {
        self.text = text
        self.title = title
        self.directory = directory
        self.truncated = truncated
    }

    public static func load(contentsOf url: URL) throws -> MarkdownDocument {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let truncated = data.count > byteLimit
        let limited = truncated ? trimmedToCharacterBoundary(data.prefix(byteLimit)) : data
        var text = decodeText(Data(limited))
        if truncated {
            // Cut back to the last complete line so a half-written table row or
            // fence does not derail the parser. `isNewline` rather than "\n",
            // because a CRLF pair is one Character.
            if let lastNewline = text.lastIndex(where: \.isNewline) {
                text = String(text[..<lastNewline])
            }
            if let fence = unclosedFence(in: text) {
                text += "\n\(fence)"
            }
            text += "\n\n> [!NOTE]\n> Preview truncated at \(byteLimit / (1024 * 1024)) MB.\n"
        }
        return MarkdownDocument(
            text: text,
            title: url.lastPathComponent,
            directory: url.deletingLastPathComponent(),
            truncated: truncated
        )
    }

    /// Markdown is nominally UTF-8, but files written by older editors are not.
    ///
    /// A byte order mark is decisive. Without one, UTF-8 is tried first and the
    /// single-byte encodings last, because every one of those accepts any byte
    /// sequence and would silently win over the right answer.
    public static func decodeText(_ data: Data) -> String {
        if let marked = encodingForByteOrderMark(data),
           let text = String(data: data, encoding: marked) {
            return stripByteOrderMark(text)
        }
        for encoding in [String.Encoding.utf8, .windowsCP1252, .isoLatin1, .macOSRoman] {
            if let text = String(data: data, encoding: encoding) {
                return stripByteOrderMark(text)
            }
        }
        return stripByteOrderMark(String(decoding: data, as: UTF8.self))
    }

    /// The marker needed to close a code fence the truncated text left open,
    /// so that the note appended after it is not swallowed by the block.
    static func unclosedFence(in text: String) -> String? {
        var open: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " })
            guard let first = trimmed.first, first == "`" || first == "~" else { continue }
            let marker = String(trimmed.prefix(while: { $0 == first }))
            guard marker.count >= 3 else { continue }
            if let current = open {
                if marker.first == current.first, marker.count >= current.count { open = nil }
            } else {
                open = marker
            }
        }
        return open
    }

    static func encodingForByteOrderMark(_ data: Data) -> String.Encoding? {
        let bytes = [UInt8](data.prefix(4))
        func starts(with prefix: [UInt8]) -> Bool {
            bytes.count >= prefix.count && Array(bytes.prefix(prefix.count)) == prefix
        }
        if starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8 }
        if starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return .utf32LittleEndian }
        if starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return .utf32BigEndian }
        if starts(with: [0xFF, 0xFE]) { return .utf16LittleEndian }
        if starts(with: [0xFE, 0xFF]) { return .utf16BigEndian }
        return nil
    }

    /// Cutting a file at a fixed byte count can land in the middle of a UTF-8
    /// character, which makes the whole prefix fail to decode and sends the
    /// document through a single-byte fallback as mojibake.
    static func trimmedToCharacterBoundary<C: DataProtocol>(_ data: C) -> Data {
        var bytes = Data(data)
        var dropped = 0
        while let last = bytes.last, last & 0b1100_0000 == 0b1000_0000, dropped < 3 {
            bytes.removeLast()
            dropped += 1
        }
        if let last = bytes.last, last & 0b1100_0000 == 0b1100_0000 {
            bytes.removeLast()
        }
        return bytes
    }

    static func stripByteOrderMark(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}
