import AppKit
import MarkdownQuickLookCore
import WebKit

// Renders a markdown file through the same web view the extension uses and
// reports what ended up in the DOM. This is the end-to-end check: scheme
// handler, content security policy, lazy engine loading and all.
let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: mdql-probe <input.md> [--dark] [--png <path>] [--width <points>] [--eval <js>]\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let dark = arguments.contains("--dark")
let pngPath = arguments.firstIndex(of: "--png").map { arguments[arguments.index(after: $0)] }
let customScript = arguments.firstIndex(of: "--eval").map { arguments[arguments.index(after: $0)] }
let width = arguments.firstIndex(of: "--width").flatMap { Double(arguments[arguments.index(after: $0)]) } ?? 900

let resourcesURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources")

let probeScript = """
JSON.stringify({
  ready: document.documentElement.getAttribute('data-mdql-ready'),
  notice: (document.getElementById('mdql-notice') || {}).textContent,
  frontMatterRows: document.querySelectorAll('.mdql-frontmatter dt').length,
  headings: document.querySelectorAll('h1,h2,h3').length,
  diagrams: document.querySelectorAll('.mdql-diagram svg').length,
  diagramErrors: document.querySelectorAll('.mdql-diagram-error').length,
  katex: document.querySelectorAll('.katex').length,
  katexDisplay: document.querySelectorAll('.katex-display').length,
  dollarsLeftInText: document.getElementById('content').innerText.split('$').length - 1,
  highlighted: document.querySelectorAll('pre code.hljs').length,
  highlightTokens: document.querySelectorAll('pre code.hljs span').length,
  tables: document.querySelectorAll('table').length,
  tableRows: document.querySelectorAll('tbody tr').length,
  callouts: Array.from(document.querySelectorAll('.mdql-callout')).map(c => c.dataset.kind),
  tasks: document.querySelectorAll('li.task-list-item').length,
  checkedTasks: document.querySelectorAll('li.task-list-item input:checked').length,
  wikiLinks: document.querySelectorAll('a.mdql-wikilink').length,
  footnotes: document.querySelectorAll('.footnotes li').length,
  definitions: document.querySelectorAll('dl dd').length,
  marks: document.querySelectorAll('mark').length,
  sub: document.querySelectorAll('sub').length,
  sup: document.querySelectorAll('sup:not(.footnote-ref)').length,
  abbr: document.querySelectorAll('abbr').length,
  strikes: document.querySelectorAll('s,del').length,
  images: Array.from(document.querySelectorAll('img')).map(i => i.getAttribute('src') + ' -> ' + i.naturalWidth + 'px'),
  missingAssets: Array.from(document.querySelectorAll('.mdql-missing-asset')).map(n => n.textContent),
  height: document.body.scrollHeight
}, null, 2)
"""

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let document = try MarkdownDocument.load(contentsOf: input)
let frame = CGRect(x: 0, y: 0, width: width, height: 1400)
let renderer = MarkdownWebRenderer(resourcesURL: resourcesURL, frame: frame)
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = renderer.webView
window.orderOut(nil)

var exitCode: Int32 = 0
var finished = false
let started = Date()

renderer.render(document: document, mode: .preview, dark: dark, timeout: 15) { result in
    if case .failure(let error) = result {
        FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
        exitCode = 1
    }
    let elapsed = Date().timeIntervalSince(started)

    renderer.webView.evaluateJavaScript(customScript ?? probeScript) { value, error in
        if let text = value.map({ String(describing: $0) }) {
            print(text)
            print("elapsedSeconds: \(String(format: "%.2f", elapsed))")
        } else {
            FileHandle.standardError.write(Data("probe failed: \(String(describing: error))\n".utf8))
            exitCode = 1
        }

        guard let pngPath else { finished = true; return }
        // The snapshot only covers the viewport, so grow the view to the full
        // document first.
        renderer.webView.evaluateJavaScript("document.body.scrollHeight") { value, _ in
        let fullHeight = (value as? Double) ?? Double(frame.height)
        let pageFrame = CGRect(x: 0, y: 0, width: width, height: min(fullHeight + 40, 20000))
        window.setContentSize(pageFrame.size)
        renderer.webView.frame = pageFrame
        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = pageFrame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        renderer.webView.takeSnapshot(with: snapshot) { image, error in
            if let image, let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: pngPath))
            } else {
                FileHandle.standardError.write(Data("snapshot failed: \(String(describing: error))\n".utf8))
                exitCode = 1
            }
            finished = true
        }
        }
        }
    }
}

while !finished && RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) {
    if Date().timeIntervalSince(started) > 60 {
        FileHandle.standardError.write(Data("probe timed out\n".utf8))
        exitCode = 1
        break
    }
}
exit(exitCode)
