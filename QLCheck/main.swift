import AppKit
import QuickLookThumbnailing
import QuickLookUI

// Renders a file the way Finder does, through whichever Quick Look extension
// the system picks. Use it to confirm that the installed extension is the one
// being asked, and that it answers.
let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: mdql-qlcheck <file> [--show] [--png <path>] [--seconds <n>]\n".utf8))
    exit(2)
}

let fileURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let pngPath = arguments.firstIndex(of: "--png").map { arguments[arguments.index(after: $0)] }
let seconds = arguments.firstIndex(of: "--seconds")
    .flatMap { Double(arguments[arguments.index(after: $0)]) } ?? 8

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

if arguments.contains("--thumbnail") {
    let request = QLThumbnailGenerator.Request(
        fileAt: fileURL,
        size: CGSize(width: 512, height: 512),
        scale: 2,
        representationTypes: .all
    )
    var done = false
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
        if let representation {
            print("thumbnail type: \(representation.type.rawValue), size: \(Int(representation.nsImage.size.width))x\(Int(representation.nsImage.size.height))")
            if let pngPath,
               let tiff = representation.nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: pngPath))
                print("wrote \(pngPath)")
            }
        } else {
            FileHandle.standardError.write(Data("thumbnail failed: \(String(describing: error))\n".utf8))
        }
        done = true
    }
    let limit = Date().addingTimeInterval(seconds)
    while !done, Date() < limit {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    exit(done ? 0 : 1)
}

let height = arguments.firstIndex(of: "--height").flatMap { Double(arguments[arguments.index(after: $0)]) } ?? 1200
let frame = CGRect(x: 0, y: 0, width: 900, height: height)
let previewView = QLPreviewView(frame: frame, style: .normal)!
previewView.autostarts = true
previewView.previewItem = fileURL as NSURL

let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = previewView
if arguments.contains("--show") {
    // The preview arrives in an NSRemoteView, whose contents the host process
    // cannot draw into a bitmap. Capturing it means putting it on screen.
    window.setFrameOrigin(NSPoint(x: 40, y: 40))
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    print("windowNumber: \(window.windowNumber)")
    fflush(stdout)
} else {
    window.orderOut(nil)
}

let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline {
    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
}

func describe(_ view: NSView, depth: Int = 0) -> [String] {
    let frame = view.frame
    let size = "\(Int(frame.width))x\(Int(frame.height)) at \(Int(frame.minX)),\(Int(frame.minY))"
    var lines = [String(repeating: "  ", count: depth) + String(describing: type(of: view)) + " [\(size)] hidden=\(view.isHidden)"]
    for subview in view.subviews { lines += describe(subview, depth: depth + 1) }
    return lines
}

let tree = describe(previewView)
print(tree.joined(separator: "\n"))
print("subviewCount: \(tree.count)")

if let pngPath {
    if let bitmap = previewView.bitmapImageRepForCachingDisplay(in: previewView.bounds) {
        previewView.cacheDisplay(in: previewView.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: pngPath))
            print("wrote \(pngPath)")
        }
    }
}
exit(0)
