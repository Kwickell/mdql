import XCTest
@testable import MarkdownQuickLookCore

final class PreviewDocumentBuilderTests: XCTestCase {
    private let template = """
    <html data-nonce="{{NONCE}}"><title>{{TITLE}}</title><body class="{{BODY_CLASS}}">
    <script nonce="{{NONCE}}">window.MDQL_PAYLOAD = {{PAYLOAD}};</script></body></html>
    """

    private func render(_ markdown: String, title: String = "note.md", mode: PreviewMode = .preview) throws -> String {
        let document = MarkdownDocument(
            text: markdown,
            title: title,
            directory: URL(fileURLWithPath: "/tmp")
        )
        return try PreviewDocumentBuilder.render(
            template: template,
            document: document,
            mode: mode,
            dark: false,
            nonce: "TESTNONCE"
        ).html
    }

    func testSubstitutesPlaceholders() throws {
        let html = try render("# Hello")
        XCTAssertTrue(html.contains("data-nonce=\"TESTNONCE\""))
        XCTAssertTrue(html.contains("<title>note.md</title>"))
        XCTAssertTrue(html.contains("class=\"mdql-preview\""))
        XCTAssertFalse(html.contains("{{"))
    }

    func testThumbnailModeSetsBodyClass() throws {
        XCTAssertTrue(try render("x", mode: .thumbnail).contains("class=\"mdql-thumbnail\""))
    }

    func testEscapesTitleInMarkup() throws {
        // The same title also travels inside the JSON payload, where it is a
        // string literal and needs no HTML escaping, so only check the element.
        let html = try render("x", title: "<img src=x onerror=alert(1)>.md")
        XCTAssertTrue(html.contains("<title>&lt;img src=x onerror=alert(1)&gt;.md</title>"))
    }

    func testMarkdownCannotCloseTheScriptElement() throws {
        let html = try render("</script><script>alert(1)</script>")
        XCTAssertFalse(html.contains("</script><script>alert(1)"))
        XCTAssertTrue(html.contains("<\\/script>"))
    }

    func testMarkdownCannotOpenAnHTMLComment() throws {
        XCTAssertTrue(try render("<!-- x").contains("<\\!--"))
    }

    func testPlaceholdersInMarkdownAreNotSubstituted() throws {
        let html = try render("{{NONCE}} {{TITLE}} {{PAYLOAD}}")
        XCTAssertEqual(html.components(separatedBy: "TESTNONCE").count - 1, 2)
        XCTAssertTrue(html.contains("{{NONCE}} {{TITLE}} {{PAYLOAD}}"))
    }

    func testEscapesJavaScriptLineSeparators() throws {
        let html = try render("a\u{2028}b\u{2029}c")
        XCTAssertFalse(html.contains("\u{2028}"))
        XCTAssertFalse(html.contains("\u{2029}"))
        XCTAssertTrue(html.contains("\\u2028"))
    }

    func testPayloadCarriesMarkdownVerbatim() throws {
        let html = try render("# Title\n\n* item")
        XCTAssertTrue(html.contains("# Title\\n\\n* item"))
    }

    func testNonceIsRandomAndUnpadded() {
        let first = PreviewDocumentBuilder.makeNonce()
        XCTAssertNotEqual(first, PreviewDocumentBuilder.makeNonce())
        XCTAssertFalse(first.contains("="))
    }
}

final class ContentSecurityPolicyTests: XCTestCase {
    func testExtensionPolicyAllowsOnlyTheCustomScheme() {
        let policy = AssetOrigin.schemeHandler.contentSecurityPolicy
        XCTAssertTrue(policy.contains("script-src 'nonce-{{NONCE}}' mdql:"))
        XCTAssertTrue(policy.contains("default-src 'none'"))
        XCTAssertTrue(policy.contains("connect-src 'none'"))
        XCTAssertFalse(policy.contains("http"))
        XCTAssertFalse(policy.contains("'unsafe-inline' mdql:; script"))
    }

    func testLocalFilePolicyAllowsFileURLs() {
        let policy = AssetOrigin.localFiles.contentSecurityPolicy
        XCTAssertTrue(policy.contains("script-src 'nonce-{{NONCE}}' file:"))
        XCTAssertFalse(policy.contains("mdql:"))
        XCTAssertFalse(policy.contains("http"))
    }

    func testNonceIsSubstitutedInsideThePolicy() throws {
        let document = MarkdownDocument(text: "x", title: "a.md", directory: URL(fileURLWithPath: "/tmp"))
        let html = try PreviewDocumentBuilder.render(
            template: "<meta content=\"{{CSP}}\"><body class=\"{{BODY_CLASS}}\"><title>{{TITLE}}</title>{{PAYLOAD}}",
            document: document,
            mode: .preview,
            dark: false,
            assets: .schemeHandler,
            nonce: "ABC"
        ).html
        XCTAssertTrue(html.contains("'nonce-ABC'"))
        XCTAssertFalse(html.contains("{{NONCE}}"))
    }
}
