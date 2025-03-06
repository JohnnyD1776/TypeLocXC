import Foundation
import Yams
import CryptoKit

// MARK: - Main Logic

let args = CommandLineArguments(arguments: Array(CommandLine.arguments.dropFirst()))
print("Arguments received: \(CommandLine.arguments)")

let projectRoot = FileManager.default.currentDirectoryPath

if let configPath = args.configArg, let (source, destination) = ConfigLoader.loadConfig(from: configPath, isArg: true) {
  let validatedSource = FileHandler.validateSource(source)
  let validatedDestination = FileHandler.validateDestination(destination, projectRoot: projectRoot, pluginMode: args.pluginMode)
  CodeGenerator.generateOutput(from: validatedSource, to: validatedDestination)
} else if let (source, destination) = ConfigLoader.loadConfig(from: "TypeLocXC.yml") {
  let validatedSource = FileHandler.validateSource(source)
  let validatedDestination = FileHandler.validateDestination(destination, projectRoot: projectRoot, pluginMode: args.pluginMode)
  CodeGenerator.generateOutput(from: validatedSource, to: validatedDestination)
} else if args.positionalArgs.count == 2 {
  let validatedSource = FileHandler.validateSource(args.positionalArgs[0])
  let validatedDestination = FileHandler.validateDestination(args.positionalArgs[1], projectRoot: projectRoot, pluginMode: args.pluginMode)
  CodeGenerator.generateOutput(from: validatedSource, to: validatedDestination)
} else if let source = args.sourceArg, let destination = args.destinationArg {
  let validatedSource = FileHandler.validateSource(source)
  let validatedDestination = FileHandler.validateDestination(destination, projectRoot: projectRoot, pluginMode: args.pluginMode)
  CodeGenerator.generateOutput(from: validatedSource, to: validatedDestination)
} else {
  runAutoMode(projectRoot: projectRoot)
}

func runAutoMode(projectRoot: String) {
  if !FileHandler.isProjectRoot(projectRoot) {
    fatalError("Please run the script from the project root directory containing .xcodeproj")
  }
  let xcstringsFiles = FileHandler.findAllXCStringsFiles(in: projectRoot)
  if xcstringsFiles.isEmpty {
    fatalError("No .xcstrings files found in project directory: \(projectRoot)")
  }
  let existingGeneratedFiles = FileHandler.findAllGeneratedFiles(in: projectRoot)
  for xcstringsFile in xcstringsFiles {
    let (needsGeneration, outputFile) = FileHandler.shouldGenerate(xcstringsFile: xcstringsFile, existingGeneratedFiles: existingGeneratedFiles)
    if needsGeneration {
      CodeGenerator.generateOutput(from: xcstringsFile, to: outputFile)
    } else {
      print("Skipping \(outputFile) as it is up to date.")
    }
  }
}
