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
        let limited = data.count > byteLimit ? data.prefix(byteLimit) : data
        var text = decodeText(Data(limited))
        let truncated = data.count > byteLimit
        if truncated {
            // Cut back to the last complete line so a half-written fence or table
            // row does not derail the parser.
            if let lastNewline = text.lastIndex(of: "\n") {
                text = String(text[..<lastNewline])
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
    public static func decodeText(_ data: Data) -> String {
        let candidates: [String.Encoding] = [.utf8, .utf16, .windowsCP1252, .isoLatin1, .macOSRoman]
        for encoding in candidates {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return stripByteOrderMark(text)
            }
        }
        return stripByteOrderMark(String(decoding: data, as: UTF8.self))
    }

    private static func stripByteOrderMark(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}
