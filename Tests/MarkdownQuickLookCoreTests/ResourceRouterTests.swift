import XCTest
@testable import MarkdownQuickLookCore

final class ResourceRouterTests: XCTestCase {
    private var resources: URL!
    private var documents: URL!
    private var router: ResourceRouter!

    override func setUpWithError() throws {
        resources = try makeTemporaryDirectory()
        documents = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: resources.appendingPathComponent("vendor"),
            withIntermediateDirectories: true
        )
        try Data("body{}".utf8).write(to: resources.appendingPathComponent("style.css"))
        try Data("x".utf8).write(to: resources.appendingPathComponent("vendor/markdown-it.min.js"))
        try Data("png".utf8).write(to: documents.appendingPathComponent("diagram.png"))
        try Data("secret".utf8).write(to: documents.deletingLastPathComponent().appendingPathComponent("outside.txt"))
        router = ResourceRouter(resourcesURL: resources, documentDirectory: documents)
    }

    private func resolve(_ string: String) -> ResourceRouter.Resolution {
        router.resolve(URL(string: string)!)
    }

    func testResolvesEntry() {
        XCTAssertEqual(resolve("mdql://doc/\(ResourceRouter.entryPath)"), .entry)
    }

    func testResolvesBundleAssets() {
        guard case .bundleResource(let url) = resolve("mdql://doc/style.css") else {
            return XCTFail("expected a bundle resource")
        }
        XCTAssertEqual(url.lastPathComponent, "style.css")
        guard case .bundleResource = resolve("mdql://doc/vendor/markdown-it.min.js") else {
            return XCTFail("expected a bundle resource")
        }
    }

    func testResolvesDocumentAssets() {
        guard case .documentResource(let url) = resolve("mdql://doc/diagram.png") else {
            return XCTFail("expected a document resource")
        }
        XCTAssertEqual(url.lastPathComponent, "diagram.png")
    }

    func testRejectsTraversalOutOfTheDocumentDirectory() {
        XCTAssertEqual(resolve("mdql://doc/../outside.txt"), .notFound)
        XCTAssertEqual(resolve("mdql://doc/%2e%2e/outside.txt"), .notFound)
        XCTAssertEqual(resolve("mdql://doc/a/../../outside.txt"), .notFound)
    }

    func testRejectsAbsolutePaths() {
        XCTAssertEqual(resolve("mdql://doc//etc/passwd"), .notFound)
    }

    func testRejectsOtherSchemesAndHosts() {
        XCTAssertEqual(resolve("https://example.com/tracker.png"), .notFound)
        XCTAssertEqual(resolve("mdql://elsewhere/style.css"), .notFound)
        XCTAssertEqual(resolve("mdql://doc/"), .notFound)
    }

    func testRejectsDirectories() {
        XCTAssertEqual(resolve("mdql://doc/vendor"), .notFound)
    }

    func testMissingFileIsNotFound() {
        XCTAssertEqual(resolve("mdql://doc/nope.png"), .notFound)
    }

    func testBundleAssetsWinOverDocumentFilesOfTheSameName() throws {
        try Data("evil".utf8).write(to: documents.appendingPathComponent("style.css"))
        guard case .bundleResource = resolve("mdql://doc/style.css") else {
            return XCTFail("bundle asset should take precedence")
        }
    }

    func testMimeTypes() {
        XCTAssertEqual(ResourceRouter.mimeType(for: URL(fileURLWithPath: "a/b.css")), "text/css")
        XCTAssertEqual(ResourceRouter.mimeType(for: URL(fileURLWithPath: "a/b.js")), "application/javascript")
        XCTAssertEqual(ResourceRouter.mimeType(for: URL(fileURLWithPath: "a/b.woff2")), "font/woff2")
        XCTAssertEqual(ResourceRouter.mimeType(for: URL(fileURLWithPath: "a/b.PNG")), "image/png")
        XCTAssertEqual(ResourceRouter.mimeType(for: URL(fileURLWithPath: "a/b.xyz")), "application/octet-stream")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mdql-router-\(UUID().uuidString)")
            .appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return url
    }
}

final class ResourceRouterSymlinkTests: XCTestCase {
    private var resources: URL!
    private var documents: URL!
    private var outside: URL!
    private var router: ResourceRouter!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mdql-links-\(UUID().uuidString)")
        resources = base.appendingPathComponent("resources")
        documents = base.appendingPathComponent("documents")
        outside = base.appendingPathComponent("elsewhere")
        for directory in [resources!, documents!, outside!] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        try Data("secret".utf8).write(to: outside.appendingPathComponent("keys.txt"))
        try Data("ok".utf8).write(to: documents.appendingPathComponent("real.png"))
        router = ResourceRouter(resourcesURL: resources, documentDirectory: documents)
    }

    private func resolve(_ string: String) -> ResourceRouter.Resolution {
        router.resolve(URL(string: string)!)
    }

    func testRefusesSymlinkPointingOutOfTheDocumentDirectory() throws {
        try FileManager.default.createSymbolicLink(
            at: documents.appendingPathComponent("escape.png"),
            withDestinationURL: outside.appendingPathComponent("keys.txt")
        )
        XCTAssertEqual(resolve("mdql://doc/escape.png"), .notFound)
    }

    func testRefusesSymlinkedDirectoryPointingOut() throws {
        try FileManager.default.createSymbolicLink(
            at: documents.appendingPathComponent("away"),
            withDestinationURL: outside
        )
        XCTAssertEqual(resolve("mdql://doc/away/keys.txt"), .notFound)
    }

    func testAllowsSymlinkStayingInsideTheDocumentDirectory() throws {
        try FileManager.default.createSymbolicLink(
            at: documents.appendingPathComponent("alias.png"),
            withDestinationURL: documents.appendingPathComponent("real.png")
        )
        guard case .documentResource = resolve("mdql://doc/alias.png") else {
            return XCTFail("a link that stays inside the directory should resolve")
        }
    }

    func testRefusesNonRegularFiles() throws {
        let fifo = documents.appendingPathComponent("pipe.png")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertEqual(resolve("mdql://doc/pipe.png"), .notFound)
    }

    func testServesFileWhoseNameContainsAPercentSign() throws {
        try Data("ok".utf8).write(to: documents.appendingPathComponent("a%20b.png"))
        guard case .documentResource(let url) = resolve("mdql://doc/a%2520b.png") else {
            return XCTFail("expected the literally named file")
        }
        XCTAssertEqual(url.lastPathComponent, "a%20b.png")
    }

    func testRefusesOversizedFiles() throws {
        let big = documents.appendingPathComponent("huge.png")
        try Data(count: ResourceRouter.fileSizeLimit + 1).write(to: big)
        XCTAssertEqual(resolve("mdql://doc/huge.png"), .notFound)
    }
}
