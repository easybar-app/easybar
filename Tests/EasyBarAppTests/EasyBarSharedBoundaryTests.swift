import EasyBarShared
import XCTest

/// Verifies the shared widget-position contract consumed by the custom frontend.
final class EasyBarSharedBoundaryTests: XCTestCase {
  func testWidgetPositionsRemainAvailableToFrontend() {
    XCTAssertEqual(
      WidgetPosition.allCases.map(\.rawValue),
      ["left", "center", "right"]
    )
  }
}
