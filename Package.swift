// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
  name: "TypeLocXC",
  platforms: [
    .macOS(.v12),
    .iOS(.v13)
  ],
  products: [
//    .executable(name: "TypeLocXC", targets: ["TypeLocXC"])
    .plugin(name: "TypeLocXCPlugin", targets: ["TypeLocXCPlugin"])
  ],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
  ],
  targets: [
    .executableTarget(
      name: "TypeLocXC",
      dependencies: ["Yams"]
    ),
    .plugin(
      name: "TypeLocXCPlugin",
      capability: .buildTool(),
      dependencies: ["TypeLocXC"],
      path: "Plugins/TypeLocXCPlugin"
    )
  ]
)


