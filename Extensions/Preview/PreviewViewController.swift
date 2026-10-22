import Cocoa
import QuickLookUI

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var renderer: MarkdownWebRenderer?

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.autoresizingMask = [.width, .height]
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let started = Date()
        Log.preview.info("preparing \(url.lastPathComponent, privacy: .public)")

        guard let resourcesURL = Bundle.main.resourceURL else {
            Log.preview.error("extension bundle has no resources")
            handler(CocoaError(.fileNoSuchFile))
            return
        }

        let document: MarkdownDocument
        do {
            document = try MarkdownDocument.load(contentsOf: url)
        } catch {
            Log.preview.error("could not read the file: \(error.localizedDescription, privacy: .public)")
            handler(error)
            return
        }

        let renderer = MarkdownWebRenderer(resourcesURL: resourcesURL, frame: view.bounds)
        self.renderer = renderer

        let webView = renderer.webView
        webView.autoresizingMask = [.width, .height]
        webView.frame = view.bounds
        view.addSubview(webView)

        let dark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        renderer.render(document: document, mode: .preview, dark: dark, timeout: 4.0) { result in
            let elapsed = Date().timeIntervalSince(started)
            switch result {
            case .success:
                Log.preview.info("rendered in \(elapsed, format: .fixed(precision: 2))s")
                handler(nil)
            case .failure(RenderError.timedOut):
                Log.preview.notice("render timed out after \(elapsed, format: .fixed(precision: 2))s, showing what is drawn")
                // Whatever finished rendering is worth more than an error panel;
                // a slow Mermaid diagram should not blank the whole preview.
                handler(nil)
            case .failure(let error):
                Log.preview.error("render failed: \(String(describing: error), privacy: .public)")
                handler(error)
            }
        }
    }
}
