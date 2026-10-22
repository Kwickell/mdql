import AppKit

// The extensions do the work; this app exists because macOS only loads an app
// extension that ships inside an application bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown Quick Look"
        window.center()
        window.contentView = makeContentView()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func makeContentView() -> NSView {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

        let title = NSTextField(labelWithString: "Markdown Quick Look \(version)")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: """
        Press the space bar on a .md file in Finder to see it rendered: \
        GitHub-flavoured Markdown with tables and task lists, syntax \
        highlighting, Mermaid diagrams, LaTeX math, callouts and wiki links.

        Previews never reach the network. Everything is rendered from files \
        inside this app.

        If a preview does not appear, make sure the extension is ticked under \
        Quick Look in System Settings.
        """)
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor

        let settingsButton = NSButton(
            title: "Open Quick Look Settings…",
            target: self,
            action: #selector(openExtensionSettings)
        )
        settingsButton.bezelStyle = .rounded
        settingsButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, body, settingsButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])
        return container
    }

    @objc private func openExtensionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!
        NSWorkspace.shared.open(url)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
