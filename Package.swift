// swift-tools-version: 5.10

import PackageDescription

let strictConcurrencySettings: [SwiftSetting] = [
  .enableUpcomingFeature("StrictConcurrency")
]

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
    .package(
      url: "https://github.com/easybar-app/easybar-kit",
      from: "0.8.0"
    )
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
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "EasyBarAppTests",
      dependencies: [
        "EasyBarApp",
        .product(
          name: "EasyBarKit",
          package: "easybar-kit"
        ),
        .product(
          name: "EasyBarShared",
          package: "easybar-kit"
        ),
      ],
      path: "Tests/EasyBarAppTests",
      swiftSettings: strictConcurrencySettings
    ),
  ]
)
