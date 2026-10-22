import Cocoa
import QuickLookThumbnailing
import WebKit

@objc(ThumbnailProvider)
final class ThumbnailProvider: QLThumbnailProvider {
    /// Width the document is laid out at before being scaled down, so a
    /// thumbnail shows a sensible amount of text rather than two huge words.
    private static let layoutWidth: CGFloat = 820

    private var renderer: MarkdownWebRenderer?
    private var window: NSWindow?

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        DispatchQueue.main.async { [self] in
            Log.thumbnail.info("preparing \(request.fileURL.lastPathComponent, privacy: .public)")
            guard let resourcesURL = Bundle.main.resourceURL,
                  let document = try? MarkdownDocument.load(contentsOf: request.fileURL) else {
                Log.thumbnail.error("could not read the file")
                handler(nil, CocoaError(.fileReadCorruptFile))
                return
            }

            let reply = ThumbnailGeometry.pageSize(fitting: request.maximumSize)
            let layout = CGRect(
                x: 0,
                y: 0,
                width: Self.layoutWidth,
                height: (Self.layoutWidth / reply.width * reply.height).rounded()
            )

            let renderer = MarkdownWebRenderer(resourcesURL: resourcesURL, frame: layout)
            self.renderer = renderer

            // WebKit only paints a web view that belongs to a window.
            let host = NSWindow(contentRect: layout, styleMask: [.borderless], backing: .buffered, defer: false)
            host.contentView = renderer.webView
            host.orderOut(nil)
            self.window = host

            renderer.render(document: document, mode: .thumbnail, dark: false, timeout: 2.5) { result in
                if case .failure(let error) = result {
                    Log.thumbnail.notice("render incomplete: \(String(describing: error), privacy: .public)")
                }

                let snapshot = WKSnapshotConfiguration()
                snapshot.rect = layout
                snapshot.snapshotWidth = NSNumber(value: Double(reply.width * request.scale))
                renderer.webView.takeSnapshot(with: snapshot) { image, error in
                    guard let image,
                          let page = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        Log.thumbnail.error("snapshot failed: \(String(describing: error), privacy: .public)")
                        handler(nil, error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    Log.thumbnail.info("thumbnail ready")
                    handler(QLThumbnailReply(contextSize: reply) { context in
                        // Whether the context is scaled is up to Quick Look, so
                        // the drawable area is taken from the context itself.
                        context.draw(page, in: context.boundingBoxOfClipPath)
                        return true
                    }, nil)
                }
            }
        }
    }
}
