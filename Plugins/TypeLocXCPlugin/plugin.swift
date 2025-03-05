import PackagePlugin
import Foundation
import XcodeProjectPlugin

@main
struct TypeLocXCPlugin: XcodeBuildToolPlugin {
  func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
    // Filter input files with the ".xcstrings" extension
    let inputFiles = target.inputFiles.filter { $0.path.extension == "xcstrings" }

    // Generate build commands for each input file
    return try inputFiles.map { inputFile in
      let inputPath = inputFile.path
      let outputName = inputPath.stem + ".swift"
      let outputPath = context.pluginWorkDirectory.appending(outputName)
      return .buildCommand(
        displayName: "Generating \(outputName) from \(inputPath.lastComponent)",
        executable: try context.tool(named: "TypeLocXC").path,
        arguments: ["--source", "\(inputPath)", "--destination", "\(outputPath)"],
        inputFiles: [inputPath],
        outputFiles: [outputPath]
      )
    }
  }
}
