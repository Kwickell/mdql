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

    var contentSecurityPolicy: String {
        let source = self == .schemeHandler ? "mdql:" : "file:"
        return [
            "default-src 'none'",
            "script-src 'nonce-{{NONCE}}' \(source)",
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
            title: document.title
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(payload), as: UTF8.self)

        var html = template
        html = html.replacingOccurrences(of: "{{CSP}}", with: assets.contentSecurityPolicy)
        html = html.replacingOccurrences(of: "{{NONCE}}", with: nonce)
        html = html.replacingOccurrences(of: "{{THEME}}", with: dark ? "dark" : "light")
        html = html.replacingOccurrences(of: "{{TITLE}}", with: escapeHTML(document.title))
        html = html.replacingOccurrences(of: "{{BODY_CLASS}}", with: mode == .thumbnail ? "mdql-thumbnail" : "mdql-preview")
        // Last, so that markdown containing a placeholder is never substituted.
        html = html.replacingOccurrences(of: "{{PAYLOAD}}", with: escapeForInlineScript(json))
        return PreviewPage(html: html, nonce: nonce)
    }

    private struct Payload: Encodable {
        let markdown: String
        let mode: PreviewMode
        let dark: Bool
        let vendor: String
        let title: String
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
