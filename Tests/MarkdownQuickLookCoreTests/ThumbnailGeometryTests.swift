import XCTest
@testable import MarkdownQuickLookCore

final class ThumbnailGeometryTests: XCTestCase {
    func testFitsPageInsideASquareRequest() {
        let size = ThumbnailGeometry.pageSize(fitting: CGSize(width: 512, height: 512))
        XCTAssertEqual(size.height, 512)
        XCTAssertEqual(size.width, 396)
        XCTAssertLessThan(size.width, size.height)
    }

    func testFitsPageInsideAWideRequest() {
        let size = ThumbnailGeometry.pageSize(fitting: CGSize(width: 1000, height: 400))
        XCTAssertEqual(size.height, 400)
        XCTAssertLessThanOrEqual(size.width, 1000)
    }

    func testFitsPageInsideATallRequest() {
        let size = ThumbnailGeometry.pageSize(fitting: CGSize(width: 200, height: 2000))
        XCTAssertLessThanOrEqual(size.width, 200)
        XCTAssertLessThanOrEqual(size.height, 2000)
        XCTAssertEqual(size.width / size.height, ThumbnailGeometry.pageAspect, accuracy: 0.01)
    }

    func testZeroRequestIsPassedThrough() {
        XCTAssertEqual(ThumbnailGeometry.pageSize(fitting: .zero), .zero)
    }
}
