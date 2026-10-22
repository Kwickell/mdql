import AppKit
import Foundation
import WebKit

public enum RenderError: Error {
    case timedOut
    case webViewFailed(Error)
}

/// Loads a markdown file into a web view and reports when the page has finished
/// drawing. Shared by the preview and thumbnail extensions.
///
/// Quick Look will not wait indefinitely and Mermaid renders asynchronously, so
/// the page signals completion over a message handler and a watchdog finishes
/// the load regardless after `timeout`.
public final class MarkdownWebRenderer: NSObject {
    public let webView: WKWebView

    private let resourcesURL: URL
    private let bridge: Bridge
    private var router: ResourceRouter?
    private var pageHTML: String?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var watchdog: DispatchWorkItem?

    public init(resourcesURL: URL, frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)) {
        self.resourcesURL = resourcesURL

        // A web view copies its configuration on init, so the scheme and message
        // handlers have to be in place before it exists. They cannot be `self`
        // yet, hence the bridge.
        let bridge = Bridge()
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(bridge, forURLScheme: ResourceRouter.scheme)
        configuration.userContentController.add(bridge, name: Bridge.readyMessageName)
        configuration.userContentController.add(bridge, name: Bridge.logMessageName)
        configuration.userContentController.add(bridge, name: Bridge.openMessageName)
        configuration.userContentController.addUserScript(Bridge.consoleForwarder)

        self.bridge = bridge
        self.webView = WKWebView(frame: frame, configuration: configuration)
        super.init()

        bridge.owner = self
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .textBackgroundColor
        }
    }

    deinit {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: Bridge.readyMessageName)
        controller.removeScriptMessageHandler(forName: Bridge.logMessageName)
        controller.removeScriptMessageHandler(forName: Bridge.openMessageName)
    }

    public func render(
        document: MarkdownDocument,
        mode: PreviewMode,
        dark: Bool,
        timeout: TimeInterval,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.completion = completion
        router = ResourceRouter(resourcesURL: resourcesURL, documentDirectory: document.directory)

        do {
            let builder = PreviewDocumentBuilder(resourcesURL: resourcesURL)
            pageHTML = try builder.build(document: document, mode: mode, dark: dark, assets: .schemeHandler).html
        } catch {
            finish(.failure(error))
            return
        }

        let work = DispatchWorkItem { [weak self] in self?.finish(.failure(RenderError.timedOut)) }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)

        Log.page.debug("loading entry page, \(self.pageHTML?.utf8.count ?? 0) bytes")
        webView.load(URLRequest(url: ResourceRouter.entryURL()))
    }

    fileprivate func finish(_ result: Result<Void, Error>) {
        guard let completion else { return }
        self.completion = nil
        watchdog?.cancel()
        watchdog = nil
        completion(result)
    }

    fileprivate func data(for url: URL) -> (Data, String)? {
        guard let router else { return nil }
        switch router.resolve(url) {
        case .entry:
            return (Data((pageHTML ?? "").utf8), "text/html")
        case .bundleResource(let fileURL), .documentResource(let fileURL):
            guard let contents = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else { return nil }
            return (contents, ResourceRouter.mimeType(for: fileURL))
        case .notFound:
            return nil
        }
    }
}

extension MarkdownWebRenderer: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Only the generated page may load. A link in the markdown must never
        // navigate the preview, least of all to a remote address.
        decisionHandler(navigationAction.request.url == ResourceRouter.entryURL() ? .allow : .cancel)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.page.debug("document loaded")
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.page.error("the web content process stopped")
        finish(.failure(RenderError.webViewFailed(CocoaError(.fileReadUnknown))))
    }

    private func fail(with error: Error) {
        // The navigation policy cancels every load but the entry page, and a
        // cancellation reported here is that policy working, not a failure.
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else { return }
        finish(.failure(RenderError.webViewFailed(error)))
    }
}

/// Serves `mdql:` requests and receives the page's "finished rendering" message.
private final class Bridge: NSObject, WKURLSchemeHandler, WKScriptMessageHandler {
    static let readyMessageName = "mdqlReady"
    static let logMessageName = "mdqlLog"
    static let openMessageName = "mdqlOpen"

    /// Page-side failures are invisible otherwise: an extension has no console.
    static let consoleForwarder = WKUserScript(
        source: """
        (function () {
          function send(kind, text) {
            try { window.webkit.messageHandlers.mdqlLog.postMessage(kind + ": " + text); } catch (e) {}
          }
          var error = console.error;
          console.error = function () {
            send("console", Array.prototype.map.call(arguments, String).join(" "));
            error.apply(console, arguments);
          };
          window.addEventListener("error", function (event) {
            send("error", (event.message || "") + " @ " + (event.filename || "") + ":" + (event.lineno || 0));
          });
          window.addEventListener("unhandledrejection", function (event) {
            send("rejection", String(event.reason));
          });
          window.addEventListener("securitypolicyviolation", function (event) {
            send("csp", event.violatedDirective + " blocked " + event.blockedURI);
          });
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    weak var owner: MarkdownWebRenderer?
    private var activeTasks = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        activeTasks.insert(ObjectIdentifier(task))
        // The path comes from the previewed document, so it is not logged openly.
        Log.page.debug("request \(task.request.url?.absoluteString ?? "?", privacy: .private)")
        guard let url = task.request.url, let payload = owner?.data(for: url) else {
            respond(task, status: 404, mimeType: "text/plain", data: Data())
            return
        }
        respond(task, status: 200, mimeType: payload.1, data: payload.0)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(task))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case Self.readyMessageName:
            owner?.finish(.success(()))
        case Self.logMessageName:
            let text = String(describing: message.body).prefix(500)
            Log.page.error("\(text, privacy: .private)")
        case Self.openMessageName:
            guard let link = message.body as? String, let url = URL(string: link),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else { return }
            NSWorkspace.shared.open(url)
        default:
            break
        }
    }

    private func respond(_ task: WKURLSchemeTask, status: Int, mimeType: String, data: Data) {
        // Sending to a task WebKit already stopped raises an Objective-C exception.
        guard activeTasks.contains(ObjectIdentifier(task)), let url = task.request.url else { return }
        let headers = [
            "Content-Type": mimeType,
            "Content-Length": String(data.count),
            "Cache-Control": "no-store"
        ]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
        activeTasks.remove(ObjectIdentifier(task))
    }
}
