import CoreGraphics

public enum ThumbnailGeometry {
    /// US Letter, so a thumbnail reads as a page rather than as a square.
    public static let pageAspect: CGFloat = 8.5 / 11.0

    /// Largest page-shaped rectangle that fits inside what Quick Look asked for.
    public static func pageSize(fitting maximum: CGSize) -> CGSize {
        guard maximum.width > 0, maximum.height > 0 else { return maximum }
        let byHeight = CGSize(width: (maximum.height * pageAspect).rounded(), height: maximum.height)
        guard byHeight.width > maximum.width else { return byHeight }
        return CGSize(width: maximum.width, height: (maximum.width / pageAspect).rounded())
    }
}
