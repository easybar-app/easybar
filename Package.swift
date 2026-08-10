// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "EasyBar",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "EasyBar", targets: ["EasyBarApp"])
  ],
  dependencies: [
    // .package(path: "../easybar-kit")
    .package(
      url: "https://github.com/easybar-app/easybar-kit",
      from: "0.54.0",
    )
  ],
  targets: [
    .executableTarget(
      name: "EasyBarApp",
      dependencies: [
        .product(name: "EasyBarKit", package: "easybar-kit"),
        .product(name: "EasyBarShared", package: "easybar-kit"),
      ],
      path: "Sources/EasyBarApp",
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "EasyBarAppTests",
      dependencies: [
        "EasyBarApp",
        .product(name: "EasyBarKit", package: "easybar-kit"),
        .product(name: "EasyBarShared", package: "easybar-kit"),
      ],
      path: "Tests/EasyBarAppTests",
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
  ]
)
