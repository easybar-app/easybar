import AppKit
import XCTest

@testable import EasyBarApp

final class BarFrameLayoutTests: XCTestCase {
  func testFrameOccupiesFullWidthAtSelectedTopEdge() {
    let frame = BarFrameLayout.frame(
      in: NSRect(x: -1_440, y: 0, width: 1_440, height: 900),
      topEdge: 900,
      height: 32
    )

    XCTAssertEqual(frame, NSRect(x: -1_440, y: 868, width: 1_440, height: 32))
  }

  func testFramePreservesFullScreenWidthWhenUsableAreaIsNarrower() {
    let screenFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_080)
    let usableFrame = NSRect(x: 80, y: 0, width: 1_840, height: 1_055)

    let frame = BarFrameLayout.frame(
      in: screenFrame,
      topEdge: usableFrame.maxY,
      height: 30
    )

    XCTAssertEqual(frame, NSRect(x: 0, y: 1_025, width: 1_920, height: 30))
  }

  func testFramePreservesFractionalGeometry() {
    let frame = BarFrameLayout.frame(
      in: NSRect(x: 10.5, y: 20.25, width: 900.75, height: 600.5),
      topEdge: 620.75,
      height: 27.5
    )

    XCTAssertEqual(frame.origin.x, 10.5)
    XCTAssertEqual(frame.origin.y, 593.25)
    XCTAssertEqual(frame.width, 900.75)
    XCTAssertEqual(frame.height, 27.5)
  }
}
