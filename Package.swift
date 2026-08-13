// swift-tools-version: 6.2

import Foundation
import PackageDescription

let easyBarKitDependency: Package.Dependency
if let root = ProcessInfo.processInfo.environment["EASYBAR_KIT_ROOT"], !root.isEmpty {
  easyBarKitDependency = .package(name: "easybar-kit", path: root)
} else {
  easyBarKitDependency = .package(
    url: "https://github.com/easybar-app/easybar-kit",
    from: "0.2.5"
  )
}

let package = Package(
  name: "EasyBar",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "EasyBar",
      targets: ["EasyBarApp"]
    )
  ],
  dependencies: [
    easyBarKitDependency
  ],
  targets: [
    .executableTarget(
      name: "EasyBarApp",
      dependencies: [
        .product(
          name: "EasyBarKit",
          package: "easybar-kit"
        ),
        .product(
          name: "EasyBarShared",
          package: "easybar-kit"
        ),
      ],
      path: "Sources/EasyBarApp",
      exclude: [
        "Info.plist"
      ]
    ),
    .testTarget(
      name: "EasyBarAppTests",
      dependencies: [
        "EasyBarApp",
        .product(
          name: "EasyBarShared",
          package: "easybar-kit"
        ),
      ],
      path: "Tests/EasyBarAppTests"
    ),
  ]
)
