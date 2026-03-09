// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "T3CodeMacOS",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(
      name: "T3CodeMacOS",
      targets: ["T3CodeMacOS"]
    ),
  ],
  targets: [
    .executableTarget(
      name: "T3CodeMacOS",
      path: "Sources"
    ),
  ]
)
