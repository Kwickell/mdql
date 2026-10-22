import Foundation

/// Resolves the URLs the preview page asks for.
///
/// Everything the page loads goes through the `mdql:` scheme: bundle assets
/// under `mdql://doc/vendor/...` and the previewed file's own images under
/// `mdql://doc/<relative path>`. Nothing outside the extension's resources and
/// the directory holding the markdown file is reachable.
public struct ResourceRouter {
    public enum Resolution: Equatable {
        case entry
        case bundleResource(URL)
        case documentResource(URL)
        case notFound
    }

    public static let scheme = "mdql"
    public static let host = "doc"
    public static let entryPath = "__mdql_preview__.html"

    /// Images beyond this are refused rather than read into memory on the main
    /// thread while Quick Look waits.
    public static let fileSizeLimit = 64 * 1024 * 1024

    private let resourcesURL: URL
    private let documentDirectory: URL

    public init(resourcesURL: URL, documentDirectory: URL) {
        self.resourcesURL = resourcesURL.standardizedFileURL.resolvingSymlinksInPath()
        self.documentDirectory = documentDirectory.standardizedFileURL.resolvingSymlinksInPath()
    }

    public static func entryURL() -> URL {
        URL(string: "\(scheme)://\(host)/\(entryPath)")!
    }

    public func resolve(_ url: URL) -> Resolution {
        guard url.scheme == Self.scheme, url.host == Self.host else { return .notFound }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        guard !path.isEmpty else { return .notFound }
        if path == Self.entryPath { return .entry }

        // Assets that ship with the extension win over same-named files sitting
        // next to the markdown, so a stray vendor/ folder cannot shadow them.
        if let bundled = resolve(path, under: resourcesURL), Self.isBundleAsset(bundled, under: resourcesURL) {
            return .bundleResource(bundled)
        }
        if let local = resolve(path, under: documentDirectory) {
            return .documentResource(local)
        }
        return .notFound
    }

    private static func isBundleAsset(_ url: URL, under root: URL) -> Bool {
        let relative = url.path.dropFirst(root.path.count + 1)
        return relative == "style.css" || relative == "render.js" || relative.hasPrefix("vendor/")
    }

    private func resolve(_ path: String, under root: URL) -> URL? {
        guard !path.contains("\0") else { return nil }
        // url.path is already percent-decoded; decoding again would both hide a
        // file whose name contains a percent sign and re-expose encoded traversal.
        let candidate = root.appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }

        guard let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) <= Self.fileSizeLimit else { return nil }
        return candidate
    }

    public static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html"
        case "css": return "text/css"
        case "js", "mjs": return "application/javascript"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "bmp": return "image/bmp"
        case "heic", "heif": return "image/heic"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }
}
