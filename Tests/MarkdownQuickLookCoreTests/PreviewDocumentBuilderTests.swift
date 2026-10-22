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
        XCTAssertTrue(html.contains("{{NONCE}} {{TITLE}} {{PAYLOAD}}"))
        XCTAssertTrue(html.contains("data-nonce=\"TESTNONCE\""))
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
    func testScriptsAreAllowedByNonceOnly() {
        for origin in [AssetOrigin.schemeHandler, .localFiles] {
            let policy = origin.contentSecurityPolicy(nonce: "ABC")
            XCTAssertTrue(policy.contains("script-src 'nonce-ABC'"))
            XCTAssertFalse(policy.contains("script-src 'nonce-ABC' mdql:"))
            XCTAssertFalse(policy.contains("script-src 'nonce-ABC' file:"))
            XCTAssertTrue(policy.contains("default-src 'none'"))
            XCTAssertTrue(policy.contains("connect-src 'none'"))
            XCTAssertFalse(policy.contains("http"))
        }
    }

    func testAssetOriginPicksTheScheme() {
        XCTAssertTrue(AssetOrigin.schemeHandler.contentSecurityPolicy(nonce: "x").contains("img-src mdql: data:"))
        XCTAssertTrue(AssetOrigin.localFiles.contentSecurityPolicy(nonce: "x").contains("img-src file: data:"))
    }

    func testNonceReachesThePolicyAndTheScriptTags() throws {
        let document = MarkdownDocument(text: "x", title: "a.md", directory: URL(fileURLWithPath: "/tmp"))
        let html = try PreviewDocumentBuilder.render(
            template: "<meta content=\"{{CSP}}\"><script nonce=\"{{NONCE}}\"></script><body class=\"{{BODY_CLASS}}\"><title>{{TITLE}}</title>{{PAYLOAD}}",
            document: document,
            mode: .preview,
            dark: false,
            assets: .schemeHandler,
            nonce: "ABC"
        ).html
        XCTAssertTrue(html.contains("'nonce-ABC'"))
        XCTAssertTrue(html.contains("<script nonce=\"ABC\">"))
        XCTAssertFalse(html.contains("{{"))
    }
}

final class TemplateFillingTests: XCTestCase {
    func testReplacesKnownKeys() {
        XCTAssertEqual(PreviewDocumentBuilder.fill("a{{X}}b{{Y}}c", with: ["X": "1", "Y": "2"]), "a1b2c")
    }

    func testLeavesUnknownKeysAlone() {
        XCTAssertEqual(PreviewDocumentBuilder.fill("a{{Z}}b", with: ["X": "1"]), "a{{Z}}b")
    }

    func testDoesNotSubstituteInsideASubstitutedValue() {
        XCTAssertEqual(
            PreviewDocumentBuilder.fill("<title>{{TITLE}}</title>{{PAYLOAD}}", with: ["TITLE": "{{PAYLOAD}}", "PAYLOAD": "data"]),
            "<title>{{PAYLOAD}}</title>data"
        )
    }

    func testHandlesAnUnterminatedPlaceholder() {
        XCTAssertEqual(PreviewDocumentBuilder.fill("a{{X", with: ["X": "1"]), "a{{X")
    }

    func testPassesThroughATemplateWithNoPlaceholders() {
        XCTAssertEqual(PreviewDocumentBuilder.fill("plain", with: ["X": "1"]), "plain")
    }
}
