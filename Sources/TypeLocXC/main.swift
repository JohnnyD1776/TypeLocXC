import Foundation
import Yams
import CryptoKit

// MARK: - Argument Parsing

let arguments = Array(CommandLine.arguments.dropFirst()) // Exclude executable name
var pluginMode = false
var sourceArg: String?
var destinationArg: String?
var configArg: String?
var positionalArgs: [String] = []

var i = 0
while i < arguments.count {
  let arg = arguments[i]
  switch arg {
  case "--help", "-?":
    print("HELP OUTPUT:")
    print(helpMessage())
    fflush(stdout)
    exit(0)
  case "--plugin-mode":
    pluginMode = true
    i += 1
  case "--source" where i + 1 < arguments.count:
    sourceArg = arguments[i + 1]
    i += 2
  case "--destination" where i + 1 < arguments.count:
    destinationArg = arguments[i + 1]
    i += 2
  case "--config" where i + 1 < arguments.count:
    configArg = arguments[i + 1]
    i += 2
  default:
    if arg.hasPrefix("--") {
      print("Unknown flag: \(arg)")
      exit(1)
    } else {
      positionalArgs.append(arg)
      i += 1
    }
  }
}

print("Arguments received: \(CommandLine.arguments)")

// MARK: - Path Variables

var xcstringsPath: String = ""
var outputFilePath: String = ""
let projectRoot = FileManager.default.currentDirectoryPath

// MARK: - Helper Functions

/// Loads source and destination from a config file.
func loadConfig(from path: String, isArg: Bool? = nil) -> (source: String, destination: String)? {
  let configPath = (path as NSString).isAbsolutePath ? path : "\(projectRoot)/\(path)"
  guard FileManager.default.fileExists(atPath: configPath) else {
    if isArg == true {
      fatalError("Config file not found at: \(configPath)")
    } else {
      print("Config file not found at: \(configPath)")
      return nil
    }
  }
  print("Config file found at: \(configPath)")
  do {
    let configData = try String(contentsOfFile: configPath)
    guard let config = try Yams.load(yaml: configData) as? [String: String],
          let source = config["source"],
          let destination = config["destination"] else {
      print("Invalid format in '\(configPath)'. Expected 'source' and 'destination' keys.")
      return nil
    }
    return (source, destination)
  } catch {
    print("Error reading config file '\(configPath)': \(error)")
    return nil
  }
}

/// Checks if the current directory is the project root by looking for .xcodeproj.
func isProjectRoot(_ directory: String) -> Bool {
  let contents = try? FileManager.default.contentsOfDirectory(atPath: directory)
  return contents?.contains(where: { $0.hasSuffix(".xcodeproj") }) ?? false
}

/// Finds all .xcstrings files in the project root and subdirectories.
func findAllXCStringsFiles(in directory: String) -> [String] {
  var xcstringsFiles: [String] = []
  let enumerator = FileManager.default.enumerator(atPath: directory)
  while let file = enumerator?.nextObject() as? String {
    if file.hasSuffix(".xcstrings") {
      xcstringsFiles.append("\(directory)/\(file)")
    }
  }
  return xcstringsFiles
}

/// Finds all +generated.swift files in the project root and subdirectories.
func findAllGeneratedFiles(in directory: String) -> [String] {
  var generatedFiles: [String] = []
  let enumerator = FileManager.default.enumerator(atPath: directory)
  while let file = enumerator?.nextObject() as? String {
    if file.hasSuffix("+generated.swift") {
      generatedFiles.append("\(directory)/\(file)")
    }
  }
  return generatedFiles
}


/// Computes SHA256 checksum of a file.
func computeSHA256(of file: String) -> String? {
  guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
    return nil
  }
  let hash = SHA256.hash(data: data)
  return hash.compactMap { String(format: "%02x", $0) }.joined()
}

/// Extracts checksum from the generated file and returns it along with the source path.
func extractChecksumAndSource(from outputFile: String) -> (checksum: String?, sourcePath: String?) {
  guard let content = try? String(contentsOfFile: outputFile),
        let firstLine = content.components(separatedBy: .newlines).first,
        firstLine.hasPrefix("// Checksum: "),
        let secondLine = content.components(separatedBy: .newlines).dropFirst().first,
        secondLine.hasPrefix("// Generated from: ") else {
    return (nil, nil)
  }
  let checksum = firstLine.replacingOccurrences(of: "// Checksum: ", with: "").trimmingCharacters(in: .whitespaces)
  let sourcePath = secondLine.replacingOccurrences(of: "// Generated from: ", with: "").trimmingCharacters(in: .whitespaces)
  return (checksum, sourcePath)
}

/// Determines if the output file should be regenerated based on checksum and source path.
func shouldGenerate(xcstringsFile: String, existingGeneratedFiles: [String]) -> (needsGeneration: Bool, outputFile: String) {
  let expectedFilename = (((xcstringsFile as NSString).lastPathComponent as NSString).deletingPathExtension) + "+generated.swift"
  for generatedFile in existingGeneratedFiles {
    let filename = (generatedFile as NSString).lastPathComponent
    if filename == expectedFilename {
      let checksumAndSource = extractChecksumAndSource(from: generatedFile)
      if let storedSourcePath = checksumAndSource.sourcePath, storedSourcePath == xcstringsFile {
        // Found a generated file for this xcstringsFile with matching filename and source path
        guard let storedChecksum = checksumAndSource.checksum,
              let currentChecksum = computeSHA256(of: xcstringsFile) else {
          return (true, generatedFile) // Regenerate if checksums can't be computed
        }
        if storedChecksum != currentChecksum {
          return (true, generatedFile) // Checksums differ, regenerate in place
        } else {
          return (false, generatedFile) // Up to date, no need to regenerate
        }
      }
    }
  }
  // No matching generated file found, generate a new one in the same directory
  let directory = (xcstringsFile as NSString).deletingLastPathComponent
  let outputFile = "\(directory)/\(expectedFilename)"
  return (true, outputFile)
}

/// Validates and sets the source path.
func validateSource(_ path: String?) -> String {
  if let source = path {
    let absoluteSource = (source as NSString).isAbsolutePath ? source : "\(projectRoot)/\(source)"
    guard FileManager.default.fileExists(atPath: absoluteSource) else {
      fatalError("Specified source file does not exist: \(absoluteSource)")
    }
    return absoluteSource
  } else {
    guard let defaultSource = findAllXCStringsFiles(in: projectRoot).first else {
      fatalError("No .xcstrings file found in project root and no source provided.")
    }
    return defaultSource
  }
}

/// Validates and sets the destination path.
func validateDestination(_ path: String?, projectRoot: String, pluginMode: Bool) -> String {
  let destination = path ?? "\(projectRoot)/Resources/Strings+Generated.swift"
  let absoluteDestination = (destination as NSString).isAbsolutePath ? destination : "\(projectRoot)/\(destination)"
  let outputDirectory = (absoluteDestination as NSString).deletingLastPathComponent

  if !pluginMode {
    let projectRootURL = URL(fileURLWithPath: projectRoot).standardized
    let outputDirURL = URL(fileURLWithPath: outputDirectory).standardized
    guard outputDirURL.path.hasPrefix(projectRootURL.path) else {
      fatalError("Destination directory '\(outputDirectory)' is outside project root '\(projectRoot)'.")
    }
  }

  // Create the output directory if it doesn’t exist
  if !FileManager.default.fileExists(atPath: outputDirectory) {
    do {
      try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
      print("Created output directory: \(outputDirectory)")
    } catch {
      fatalError("Error creating output directory '\(outputDirectory)': \(error)")
    }
  }
  return absoluteDestination
}

// MARK: - Generation Function

func generateOutput(from xcstringsPath: String, to outputFilePath: String) {
  guard let checksum = computeSHA256(of: xcstringsPath) else {
    fatalError("Failed to compute checksum for \(xcstringsPath)")
  }

  guard let data = try? Data(contentsOf: URL(fileURLWithPath: xcstringsPath)),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let strings = json["strings"] as? [String: Any] else {
    fatalError("Failed to read or parse .xcstrings file at \(xcstringsPath)")
  }

  var output = """
    // Checksum: \(checksum)
    // Generated from: \(xcstringsPath)
    // Auto-generated file for type-safe access to .xcstrings
    import Foundation

    /// Type-safe access to localized strings from `Localizable.xcstrings`.
    /// Automatically generated by `TypeLocXC.swift`. Do not edit manually.
    ///
    /// The `L10n` enum provides functions for each string key in `Localizable.xcstrings`.
    /// - Keys with dots (e.g., "GameOver.backToMain") are converted to underscores (e.g., `GameOver_backToMain`).
    /// - For simple strings without format specifiers, the function takes no parameters.
    /// - For strings with format specifiers (`%d`, `%@`, `%f`), the function includes labeled parameters (`p1`, `p2`, etc.) with types `Int`, `String`, `Double`, respectively.
    /// - For plural strings defined with variations in `.xcstrings`, pass the count as the first parameter (`count: Int`), followed by additional parameters if needed.
    ///
    /// Example usage:
    /// ```swift
    /// // Simple string
    /// let mainMenu = L10n.GameOver_backToMain()  // "Main Menu"
    ///
    /// // Parameterized string
    /// let score = L10n.HUD_Label_score(p1: 42)   // "Score: 42"
    ///
    /// // Plural string (assuming "apple_count" is<|control374|> with plurals)
    /// let oneApple = L10n.apple_count(count: 1)     // "1 apple"
    /// let manyApples = L10n.apple_count(count: 5)   // "5 apples"
    /// ```
    ///
    /// Supported format specifiers:
    /// - `%@`: `String`
    /// - `%d`, `%i`: `Int`
    /// - `%f`: `Double`
    /// - `%s`: `String` (C-style string)

    enum L10n {
    """

  for (key, value) in strings {
    guard let valueDict = value as? [String: Any],
          let localizations = valueDict["localizations"] as? [String: Any],
          let enLocalization = localizations["en"] as? [String: Any] else {
      continue
    }

    let safeKey = key.replacingOccurrences(of: ".", with: "_")

    if let variation = enLocalization["variation"] as? [String: Any],
       let plural = variation["plural"] as? [String: Any] {
      generatePluralFunction(for: safeKey, pluralData: plural, output: &output)
    } else if let stringUnit = enLocalization["stringUnit"] as? [String: String],
              let stringValue = stringUnit["value"] {
      let specifiers = extractSpecifiers(from: stringValue)
      let parameters = generateParameters(for: specifiers)
      let arguments = generateArguments(for: specifiers)

      if specifiers.isEmpty {
        output += """
                    
                    static func \(safeKey)() -> String {
                        return NSLocalizedString("\(key)", tableName: "Localizable", comment: "")
                    }
                    """
      } else {
        output += """
                    
                    static func \(safeKey)(\(parameters)) -> String {
                        return String(format: NSLocalizedString("\(key)", tableName: "Localizable", comment: ""), \(arguments))
                    }
                    """
      }
    }
  }

  output += "\n}\n"

  do {
    try output.write(toFile: outputFilePath, atomically: true, encoding: .utf8)
    print("✅ Generated \(outputFilePath) successfully!")
  } catch {
    fatalError("Failed to write to \(outputFilePath): \(error)")
  }
}

// MARK: - String Generation Helpers

func extractSpecifiers(from string: String) -> [String] {
  let regex = try! NSRegularExpression(pattern: "%[@cdiouxXeEfFgGaAsSpn%]")
  let matches = regex.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
  return matches.map { String(string[Range($0.range, in: string)!]) }
}

func mapSpecifierToType(_ specifier: String) -> String {
  switch specifier {
  case "%@": return "String"
  case "%c": return "Character"
  case "%d", "%i": return "Int"
  case "%o", "%u", "%x", "%X": return "UInt"
  case "%e", "%E", "%f", "%F", "%g", "%G", "%a", "%A": return "Double"
  case "%s": return "String"
  case "%p": return "UnsafeRawPointer"
  case "%%": return ""
  default:
    print("Warning: Unknown specifier '\(specifier)', defaulting to Any")
    return "Any"
  }
}

func generateParameters(for specifiers: [String]) -> String {
  specifiers.enumerated().map { (index, specifier) in
    let type = mapSpecifierToType(specifier)
    if type.isEmpty { return "" }
    return "p\(index + 1): \(type)"
  }
  .filter { !$0.isEmpty }
  .joined(separator: ", ")
}

func generateArguments(for specifiers: [String]) -> String {
  specifiers.enumerated()
    .filter { mapSpecifierToType($1) != "" }
    .map { index, _ in "p\(index + 1)" }
    .joined(separator: ", ")
}

func generatePluralFunction(for key: String, pluralData: [String: Any], output: inout String) {
  let countParam = "count: Int"
  if let firstCategory = pluralData.keys.first,
     let categoryData = pluralData[firstCategory] as? [String: Any],
     let stringUnit = categoryData["stringUnit"] as? [String: String],
     let stringValue = stringUnit["value"] {
    let specifiers = extractSpecifiers(from: stringValue)
    let additionalParams = generateParameters(for: specifiers)
    let arguments = generateArguments(for: specifiers)
    let params = [countParam] + (additionalParams.isEmpty ? [] : [additionalParams])
    let paramString = params.joined(separator: ", ")
    let argList = ["count"] + (arguments.isEmpty ? [] : [arguments])

    output += """
            
            static func \(key)(\(paramString)) -> String {
                let format = NSLocalizedString("\(key)", tableName: "Localizable", comment: "")
                return String.localizedStringWithFormat(format, \(argList.joined(separator: ", ")))
            }
            """
  } else {
    output += """
            
            static func \(key)(\(countParam)) -> String {
                let format = NSLocalizedString("\(key)", tableName: "Localizable", comment: "")
                return String.localizedStringWithFormat(format, count)
            }
            """
  }
}

// MARK: - Main Logic

var autoMode = false

if let configPath = configArg, let (source, destination) = loadConfig(from: configPath, isArg: configArg != nil) {
  xcstringsPath = source
  outputFilePath = destination
} else if let (source, destination) = loadConfig(from: "TypeLocXC.yml") {
  xcstringsPath = source
  outputFilePath = destination
} else if positionalArgs.count == 2 {
  xcstringsPath = positionalArgs[0]
  outputFilePath = positionalArgs[1]
} else if let source = sourceArg, let destination = destinationArg {
  xcstringsPath = source
  outputFilePath = destination
} else {
  autoMode = true
}

if autoMode {
  if !isProjectRoot(projectRoot) {
    fatalError("Please run the script from the project root directory containing .xcodeproj")
  }
  let xcstringsFiles = findAllXCStringsFiles(in: projectRoot)
  if xcstringsFiles.isEmpty {
    fatalError("No .xcstrings files found in project directory: \(projectRoot)")
  }
  let existingGeneratedFiles = findAllGeneratedFiles(in: projectRoot)
  for xcstringsFile in xcstringsFiles {
    let (needsGeneration, outputFile) = shouldGenerate(xcstringsFile: xcstringsFile, existingGeneratedFiles: existingGeneratedFiles)
    if needsGeneration {
      generateOutput(from: xcstringsFile, to: outputFile)
    } else {
      print("Skipping \(outputFile) as it is up to date.")
    }
  }
} else {
  xcstringsPath = validateSource(xcstringsPath)
  outputFilePath = validateDestination(outputFilePath, projectRoot: projectRoot, pluginMode: pluginMode)
  generateOutput(from: xcstringsPath, to: outputFilePath)
}

// MARK: - Help Message

func helpMessage() -> String {
    """
    Usage: TypeLocXC [OPTIONS] [SOURCE DESTINATION]
    
    Generate type-safe Swift code from .xcstrings files.
    
    Options:
      --source <file>        Specify the input .xcstrings file
      --destination <file>   Specify the output Swift file
      --config <file>        Use a custom YAML config file (e.g., config.yml)
      --plugin-mode          Run in plugin mode (used by SPM/Xcode build tool)
      --help, -?             Display this help message
    
    Positional Arguments:
      SOURCE                 Input .xcstrings file (optional if --source is used)
      DESTINATION            Output Swift file (optional if --destination is used)
    
    Behavior:
      - If run with --plugin-mode, processes files as specified by the plugin.
      - If run without parameters, enters auto mode: finds all .xcstrings files in the project
        and generates <name>+generated.swift files in the same directory.
      - Otherwise, uses config, positional arguments, or defaults to generate a single file.
    
    Examples:
      TypeLocXC --source Custom.xcstrings --destination Generated.swift
      TypeLocXC --config myconfig.yml
      TypeLocXC (runs in auto mode)
    """
}
