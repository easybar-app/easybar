import XCTest

@testable import EasyBarApp

final class ApplicationIdentityTests: XCTestCase {
  func testCustomBarIdentityOwnsDefaultPaths() {
    let identity = EasyBarAppMain.identity

    XCTAssertEqual(identity.displayName, "EasyBar")
    XCTAssertEqual(identity.processName, "easybar")
    XCTAssertEqual(identity.loggerLabel, "easybar")
    XCTAssertEqual(identity.logFileName, "easybar.out")
    XCTAssertEqual(identity.defaultConfigRelativePath, ".config/easybar/config.toml")
    XCTAssertEqual(identity.defaultRuntimeRelativePath, ".local/state/easybar/runtime")
    XCTAssertEqual(identity.builtInSurfacePolicy, .all)
    XCTAssertTrue(identity.defaultEnvironment.isEmpty)
  }
}
