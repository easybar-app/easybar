import AppKit
import XCTest

@testable import EasyBarApp

final class BarFrameLayoutTests: XCTestCase {
  func testFrameOccupiesTopEdgeOfSelectedScreenArea() {
    let frame = BarFrameLayout.frame(
      in: NSRect(x: -1_440, y: 25, width: 1_440, height: 875),
      height: 32
    )

    XCTAssertEqual(frame, NSRect(x: -1_440, y: 868, width: 1_440, height: 32))
  }

  func testFramePreservesFractionalGeometry() {
    let frame = BarFrameLayout.frame(
      in: NSRect(x: 10.5, y: 20.25, width: 900.75, height: 600.5),
      height: 27.5
    )

    XCTAssertEqual(frame.origin.x, 10.5)
    XCTAssertEqual(frame.origin.y, 593.25)
    XCTAssertEqual(frame.width, 900.75)
    XCTAssertEqual(frame.height, 27.5)
  }
}
