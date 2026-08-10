import EasyBarKit
import EasyBarShared
import XCTest

@MainActor
private func widgetSurfaces(
  from presentationModel: EasyBarPresentationModel,
  at position: WidgetPosition
) -> [EasyBarPresentationModel.WidgetSurface] {
  presentationModel.widgets(at: position)
}

/// Verifies that the shared presentation API remains consumable by the custom frontend.
final class EasyBarKitBoundaryTests: XCTestCase {
  func testWidgetPositionsRemainAvailableToFrontend() {
    XCTAssertEqual(
      WidgetPosition.allCases.map(\.rawValue),
      ["left", "center", "right"]
    )
  }
}
