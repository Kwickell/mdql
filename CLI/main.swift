import Foundation
import MarkdownQuickLookCore

// Renders a markdown file to a folder of static files. Used to check the
// rendering pipeline in a browser without installing the extension.
let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: mdql-render <input.md> <output-dir> [--dark] [--copy]\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let outputDirectory = URL(fileURLWithPath: arguments[2]).standardizedFileURL
let dark = arguments.contains("--dark")
let copyAssets = arguments.contains("--copy")

let resourcesURL: URL = {
    if let override = ProcessInfo.processInfo.environment["MDQL_RESOURCES"] {
        return URL(fileURLWithPath: override)
    }
    return URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")
}()

do {
    let document = try MarkdownDocument.load(contentsOf: input)
    let page = try PreviewDocumentBuilder(resourcesURL: resourcesURL)
        .build(document: document, mode: .preview, dark: dark, assets: .localFiles)

    let fileManager = FileManager.default
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try Data(page.html.utf8).write(to: outputDirectory.appendingPathComponent("index.html"))

    for asset in ["style.css", "render.js", "vendor"] {
        let destination = outputDirectory.appendingPathComponent(asset)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let source = resourcesURL.appendingPathComponent(asset)
        if copyAssets {
            try fileManager.copyItem(at: source, to: destination)
        } else {
            try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
        }
    }

    // Relative image paths resolve against the output folder, so every sibling
    // of the markdown file is linked in next to the generated page.
    for sibling in (try? fileManager.contentsOfDirectory(at: document.directory, includingPropertiesForKeys: nil)) ?? [] {
        let destination = outputDirectory.appendingPathComponent(sibling.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) { continue }
        try? fileManager.createSymbolicLink(at: destination, withDestinationURL: sibling)
    }

    print(outputDirectory.appendingPathComponent("index.html").path)
} catch {
    FileHandle.standardError.write(Data("mdql-render: \(error)\n".utf8))
    exit(1)
}
