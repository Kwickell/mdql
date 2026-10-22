import Foundation
import os

/// Quick Look extensions have no console of their own. Everything they report
/// goes to the unified log:
///
///     log stream --predicate 'subsystem == "com.kimwickell.MarkdownQuickLook"'
public enum Log {
    public static let preview = Logger(subsystem: subsystem, category: "preview")
    public static let thumbnail = Logger(subsystem: subsystem, category: "thumbnail")
    public static let page = Logger(subsystem: subsystem, category: "page")

    private static var subsystem: String {
        // The extensions are named <app bundle id>.Preview and .Thumbnail, so
        // the app's identifier is what both of them log under.
        let identifier = Bundle.main.bundleIdentifier ?? "MarkdownQuickLook"
        return identifier.hasSuffix(".Preview") || identifier.hasSuffix(".Thumbnail")
            ? String(identifier.split(separator: ".").dropLast().joined(separator: "."))
            : identifier
    }
}
