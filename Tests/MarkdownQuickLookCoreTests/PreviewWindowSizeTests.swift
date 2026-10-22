import XCTest
@testable import MarkdownQuickLookCore

final class PreviewWindowSizeTests: XCTestCase {
    private let screen = CGSize(width: 1800, height: 1000)

    func testUsesTheFallbackWhenNoScreenIsKnown() {
        XCTAssertEqual(PreviewWindowSize.preferred(stored: nil, screen: nil), PreviewWindowSize.fallback)
    }

    func testDefaultScalesWithTheScreen() {
        let big = PreviewWindowSize.preferred(stored: nil, screen: CGSize(width: 3840, height: 2129))
        let small = PreviewWindowSize.preferred(stored: nil, screen: CGSize(width: 1440, height: 850))
        XCTAssertGreaterThan(big.width, small.width)
        XCTAssertGreaterThan(big.height, small.height)
        XCTAssertLessThanOrEqual(big.width, 3840 * 0.6)
        XCTAssertLessThanOrEqual(big.height, 1700)
    }

    func testDefaultIsTallerThanItIsWide() {
        let size = PreviewWindowSize.preferred(stored: nil, screen: CGSize(width: 3840, height: 2129))
        XCTAssertLessThan(size.width, size.height)
    }

    func testDefaultFitsASmallLaptopScreen() {
        let screen = CGSize(width: 1440, height: 850)
        let size = PreviewWindowSize.preferred(stored: nil, screen: screen)
        XCTAssertLessThanOrEqual(size.width, screen.width)
        XCTAssertLessThanOrEqual(size.height, screen.height)
    }

    func testUsesAStoredSize() {
        let stored = CGSize(width: 900, height: 700)
        XCTAssertEqual(PreviewWindowSize.preferred(stored: stored, screen: screen), stored)
    }

    func testIgnoresAStoredSizeSmallerThanTheMinimum() {
        let size = PreviewWindowSize.preferred(stored: CGSize(width: 100, height: 80), screen: nil)
        XCTAssertEqual(size, PreviewWindowSize.fallback)
    }

    func testAStoredSizeBeatsTheScreenDefault() {
        let stored = CGSize(width: 900, height: 700)
        XCTAssertEqual(PreviewWindowSize.preferred(stored: stored, screen: CGSize(width: 3840, height: 2129)), stored)
    }

    func testNeverExceedsTheScreen() {
        let size = PreviewWindowSize.preferred(stored: CGSize(width: 4000, height: 4000), screen: screen)
        XCTAssertLessThanOrEqual(size.width, screen.width)
        XCTAssertLessThanOrEqual(size.height, screen.height)
    }

    func testDefaultIsClampedToATinyScreen() {
        let small = CGSize(width: 800, height: 600)
        let size = PreviewWindowSize.preferred(stored: nil, screen: small)
        XCTAssertLessThanOrEqual(size.width, small.width)
        XCTAssertLessThanOrEqual(size.height, small.height)
        XCTAssertGreaterThanOrEqual(size.height, PreviewWindowSize.minimum.height)
    }

    func testStaysAboveTheMinimumOnATinyScreen() {
        let size = PreviewWindowSize.preferred(stored: nil, screen: CGSize(width: 200, height: 150))
        XCTAssertEqual(size, PreviewWindowSize.minimum)
    }

    func testRemembersTheFirstUsableSize() {
        XCTAssertTrue(PreviewWindowSize.shouldRemember(CGSize(width: 900, height: 700), stored: nil))
    }

    func testDoesNotRememberALayoutBelowTheMinimum() {
        XCTAssertFalse(PreviewWindowSize.shouldRemember(CGSize(width: 320, height: 200), stored: nil))
        XCTAssertFalse(PreviewWindowSize.shouldRemember(.zero, stored: CGSize(width: 900, height: 700)))
    }

    func testIgnoresASizeThatBarelyChanged() {
        let stored = CGSize(width: 900, height: 700)
        XCTAssertFalse(PreviewWindowSize.shouldRemember(CGSize(width: 903, height: 702), stored: stored))
        XCTAssertTrue(PreviewWindowSize.shouldRemember(CGSize(width: 930, height: 700), stored: stored))
        XCTAssertTrue(PreviewWindowSize.shouldRemember(CGSize(width: 900, height: 760), stored: stored))
    }
}
