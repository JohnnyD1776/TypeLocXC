import PackagePlugin
import Foundation

@main
struct TypeLocXCPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    // Locate the TypeLocXC tool
    guard let target = target.sourceModule else { return [] }
    let inputFiles = target.sourceFiles.filter({ $0.path.extension == "xcstrings" })
    return try inputFiles.map {
      let inputFile = $0
      let inputPath = inputFile.path
      let outputName = inputPath.stem + ".swift"
      let outputPath = context.pluginWorkDirectory.appending(outputName)
      return .buildCommand(
        displayName: "Generating \(outputName) from \(inputPath.lastComponent)",
        executable: try context.tool(named: "TypeLocXC").path,
        arguments: [ "--source", "\(inputPath)",  "--destination", "\(outputPath)" ],
        inputFiles: [ inputPath, ],
        outputFiles: [ outputPath ]
      )
    }
  }
}
