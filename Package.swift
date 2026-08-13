// swift-tools-version: 6.2

import PackageDescription

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
      from: "0.2.5"
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
