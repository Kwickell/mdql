import Foundation

public enum PreviewMode: String, Codable {
    case preview
    case thumbnail
}

/// Where the page's own assets come from, which decides what the content
/// security policy has to allow.
public enum AssetOrigin: String, Codable {
    /// Served by the extension over the `mdql:` scheme.
    case schemeHandler
    /// Plain files next to the generated page, used by `mdql-render`.
    case localFiles

    /// Scripts are allowed by nonce alone, never by origin: a file sitting next
    /// to the markdown is served over the same scheme as the bundled engines.
    func contentSecurityPolicy(nonce: String) -> String {
        let source = self == .schemeHandler ? "mdql:" : "file:"
        return [
            "default-src 'none'",
            "script-src 'nonce-\(nonce)'",
            "style-src 'unsafe-inline' \(source)",
            "img-src \(source) data:",
            "font-src \(source) data:",
            "connect-src 'none'",
            "frame-src 'none'",
            "object-src 'none'",
            "base-uri 'none'",
            "form-action 'none'"
        ].joined(separator: "; ")
    }
}

public struct PreviewPage {
    public let html: String
    public let nonce: String
}

/// Fills `preview.html` with the document's text and the settings the
/// JavaScript side needs. The markdown never reaches the page as markup: it is
/// carried as a JSON string and parsed in the web view.
public struct PreviewDocumentBuilder {
    private let resourcesURL: URL

    public init(resourcesURL: URL) {
        self.resourcesURL = resourcesURL
    }

    public func build(
        document: MarkdownDocument,
        mode: PreviewMode,
        dark: Bool,
        assets: AssetOrigin = .schemeHandler
    ) throws -> PreviewPage {
        let template = try String(contentsOf: resourcesURL.appendingPathComponent("preview.html"), encoding: .utf8)
        return try Self.render(template: template, document: document, mode: mode, dark: dark, assets: assets)
    }

    static func render(
        template: String,
        document: MarkdownDocument,
        mode: PreviewMode,
        dark: Bool,
        assets: AssetOrigin = .schemeHandler,
        nonce: String = makeNonce()
    ) throws -> PreviewPage {
        let payload = Payload(
            markdown: document.text,
            mode: mode,
            dark: dark,
            vendor: "vendor/",
            title: document.title,
            nonce: nonce
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(payload), as: UTF8.self)

        return PreviewPage(html: fill(template, with: [
            "CSP": assets.contentSecurityPolicy(nonce: nonce),
            "NONCE": nonce,
            "THEME": dark ? "dark" : "light",
            "TITLE": escapeHTML(document.title),
            "BODY_CLASS": mode == .thumbnail ? "mdql-thumbnail" : "mdql-preview",
            "PAYLOAD": escapeForInlineScript(json)
        ]), nonce: nonce)
    }

    /// One pass, so that a value containing `{{SOMETHING}}` is never itself
    /// treated as a placeholder. Markdown and file names reach this.
    static func fill(_ template: String, with values: [String: String]) -> String {
        var output = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            output += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}") else {
                return output + rest[open.lowerBound...]
            }
            let key = String(rest[open.upperBound..<close.lowerBound])
            output += values[key] ?? "{{\(key)}}"
            rest = rest[close.upperBound...]
        }
        return output + rest

    }

    private struct Payload: Encodable {
        let markdown: String
        let mode: PreviewMode
        let dark: Bool
        let vendor: String
        let title: String
        /// The page needs it to stamp the engines it loads on demand.
        let nonce: String
    }

    public static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    static func escapeHTML(_ text: String) -> String {
        var out = text
        for (needle, replacement) in [("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"), ("'", "&#39;")] {
            out = out.replacingOccurrences(of: needle, with: replacement)
        }
        return out
    }

    /// JSON is not safe to drop into a `<script>` element as-is: `</script>` in
    /// the markdown would close the element, and U+2028/U+2029 are line breaks
    /// to a JavaScript parser but not to JSON.
    static func escapeForInlineScript(_ json: String) -> String {
        json
            .replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "<!--", with: "<\\!--")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
