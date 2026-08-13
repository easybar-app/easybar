import EasyBarShared
import XCTest

/// Verifies that the shared presentation API remains consumable by the custom frontend.
final class EasyBarKitBoundaryTests: XCTestCase {
  func testWidgetPositionsRemainAvailableToFrontend() {
    XCTAssertEqual(
      WidgetPosition.allCases.map(\.rawValue),
      ["left", "center", "right"]
    )
  }
}
