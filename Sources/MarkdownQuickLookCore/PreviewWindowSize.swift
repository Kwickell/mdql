import CoreGraphics

/// How big the Quick Look panel opens.
///
/// Quick Look takes the size from the preview controller's
/// `preferredContentSize`; without one it falls back to a panel too small to
/// read a document in. The size someone drags the panel to is kept and offered
/// back the next time.
public enum PreviewWindowSize {
    /// Used only when the extension cannot see a screen to scale against.
    public static let fallback = CGSize(width: 1100, height: 1280)

    /// Below this, a layout is Quick Look setting the view up rather than a
    /// size someone chose, and storing it would shrink every later preview.
    public static let minimum = CGSize(width: 480, height: 360)

    /// Resizing by less than this is not worth a write.
    public static let tolerance: CGFloat = 8

    public static func preferred(stored: CGSize?, screen: CGSize?) -> CGSize {
        clamped(isUsable(stored ?? .zero) ?? defaultSize(for: screen), to: screen)
    }

    /// A panel proportional to the display: a fixed size that reads well on a
    /// laptop is a postage stamp on a 4K desktop.
    static func defaultSize(for screen: CGSize?) -> CGSize {
        guard let screen, screen.width > 0, screen.height > 0 else { return fallback }
        let height = min(max(screen.height * 0.8, 620), 1700)
        let width = min(max(height * 0.8, 860), screen.width * 0.6)
        return CGSize(width: width, height: height)
    }

    private static func clamped(_ size: CGSize, to screen: CGSize?) -> CGSize {
        var size = size
        if let screen, screen.width > 0, screen.height > 0 {
            size.width = min(size.width, screen.width * 0.95)
            size.height = min(size.height, screen.height * 0.95)
        }
        return CGSize(width: max(size.width, minimum.width).rounded(),
                      height: max(size.height, minimum.height).rounded())
    }

    public static func shouldRemember(_ size: CGSize, stored: CGSize?) -> Bool {
        guard isUsable(size) != nil else { return false }
        guard let stored else { return true }
        return abs(size.width - stored.width) >= tolerance || abs(size.height - stored.height) >= tolerance
    }

    private static func isUsable(_ size: CGSize) -> CGSize? {
        size.width >= minimum.width && size.height >= minimum.height ? size : nil
    }
}
