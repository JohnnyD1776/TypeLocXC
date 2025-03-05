import PackagePlugin
import Foundation

@main
struct TypeLocXCPlugin: BuildToolPlugin {
  /// Entry point for creating build commands for targets in Swift packages.
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {

    // Find the code generator tool to run (This is what we named our actual one.).
    let generatorTool = try context.tool(named: "TypeLocXC")

    // Still ensures that the target is a source module.
    guard let target = target as? SourceModuleTarget else { return [] }

    let filesToProcess = try filesFromDirectory(path: target.directory, shallow: false)

    // Construct a build command for each source file with a particular suffix.
    return filesToProcess.compactMap {
      createBuildCommand(for: $0, in: context.pluginWorkDirectory, with: generatorTool.path)
    }
  }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension TypeLocXCPlugin: XcodeBuildToolPlugin {
  // Entry point for creating build commands for targets in Xcode projects.
  func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
    // Find the code generator tool to run (replace this with the actual one).
    let generatorTool = try context.tool(named: "TypeLocXC")

    // Construct a build command for each source file with a particular suffix.
    return target.inputFiles.map(\.path).compactMap {
      createBuildCommand(for: $0, in: context.pluginWorkDirectory, with: generatorTool.path)
    }
  }
}

#endif

extension TypeLocXCPlugin {
  /// Shared function that returns a configured build command if the input files is one that should be processed.
  func createBuildCommand(for inputPath: Path, in outputDirectoryPath: Path, with generatorToolPath: Path) -> Command? {
    // Skip any file that doesn't have the extension we're looking for (replace this with the actual one).
    guard inputPath.extension == "xcstrings" else { return .none }

    print("PROOF OF PLUGIN LIFE from createBuildCommand")

    // Return a command that will run during the build to generate the output file.
    let inputName = inputPath.lastComponent
    let outputName = inputPath.stem + "+generated.swift" // Changed to +generated.swift
    let outputPath = outputDirectoryPath.appending(outputName)
    return .buildCommand(
      displayName: "------------ Generating \(outputName) from \(inputName) ------------",
      executable: generatorToolPath,
      arguments: ["--plugin-mode", "--source", "\(inputPath)", "--destination", "\(outputPath)"],
      inputFiles: [inputPath],
      outputFiles: [outputPath]
    )
  }
}

func filesFromDirectory(path providedPath:Path, shallow:Bool = true) throws -> [Path] {
  if shallow {
    return try FileManager.default.contentsOfDirectory(atPath: providedPath.string).compactMap { fileName in
      providedPath.appending([fileName])
    }
  } else {
    let dataDirectoryURL = URL(fileURLWithPath: providedPath.string, isDirectory: true)
    var allFiles = [Path?]()
    let enumerator = FileManager.default.enumerator(at: dataDirectoryURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])

    while let fileURL = enumerator?.nextObject() as? URL {
      if let regularFileCheck = try fileURL.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile, regularFileCheck == true {
        allFiles.append((Path(fileURL.path())))
      }
    }
    return allFiles.compactMap({$0})
  }
}
