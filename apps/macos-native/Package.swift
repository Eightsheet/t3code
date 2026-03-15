// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "T3CodeMacOS",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "T3CodeMacOSRuntime",
      targets: ["T3CodeMacOSRuntime"]
    ),
    .executable(
      name: "T3CodeMacOS",
      targets: ["T3CodeMacOS"]
    ),
  ],
  targets: [
    .target(
      name: "T3CodeMacOSRuntime",
      path: "Sources/Runtime"
    ),
    .executableTarget(
      name: "T3CodeMacOS",
      dependencies: ["T3CodeMacOSRuntime"],
      path: "Sources/App"
    ),
    .testTarget(
      name: "T3CodeMacOSRuntimeTests",
      dependencies: ["T3CodeMacOSRuntime"],
      path: "Tests/T3CodeMacOSRuntimeTests"
    ),
  ]
)
