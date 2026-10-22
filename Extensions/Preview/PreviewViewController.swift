import Cocoa
import QuickLookUI

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private static let widthKey = "previewWidth"
    private static let heightKey = "previewHeight"

    private var renderer: MarkdownWebRenderer?
    private var sizeRecorder: DispatchWorkItem?

    override func loadView() {
        let screen = NSScreen.main?.visibleFrame.size
        Log.preview.debug("screen \(screen.map { "\(Int($0.width))x\(Int($0.height))" } ?? "unknown", privacy: .public)")
        let size = PreviewWindowSize.preferred(stored: Self.rememberedSize, screen: screen)
        view = NSView(frame: CGRect(origin: .zero, size: size))
        view.autoresizingMask = [.width, .height]
        preferredContentSize = size
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Opening a panel produces several transient layouts before it settles,
        // and a resize produces one per frame, so only the last one is kept.
        sizeRecorder?.cancel()
        let recorder = DispatchWorkItem { [weak self] in
            guard let size = self?.view.bounds.size,
                  PreviewWindowSize.shouldRemember(size, stored: Self.rememberedSize) else { return }
            Log.preview.debug("remembering panel size \(Int(size.width))x\(Int(size.height))")
            Self.rememberedSize = size
        }
        sizeRecorder = recorder
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: recorder)
    }

    /// The extension's own container, which is where its defaults live.
    private static var rememberedSize: CGSize? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: widthKey) != nil else { return nil }
            return CGSize(
                width: defaults.double(forKey: widthKey),
                height: defaults.double(forKey: heightKey)
            )
        }
        set {
            guard let newValue else { return }
            UserDefaults.standard.set(Double(newValue.width), forKey: widthKey)
            UserDefaults.standard.set(Double(newValue.height), forKey: heightKey)
        }
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let started = Date()
        Log.preview.info("preparing \(url.lastPathComponent, privacy: .private)")

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
