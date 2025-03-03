import Foundation
import Yams

// MARK: - Argument Parsing

let arguments = Array(CommandLine.arguments.dropFirst()) // Exclude executable name
var sourceArg: String?
var destinationArg: String?
var configArg: String?
var positionalArgs: [String] = []

var i = 0
while i < arguments.count {
  let arg = arguments[i]

  if arg == "--help" || arg == "-?" {
    print("HELP OUTPUT:")
    print(helpMessage())
    fflush(stdout) // Ensure output is flushed
    exit(0)
  }

  if arg == "--source", i + 1 < arguments.count {
    sourceArg = arguments[i + 1]
    i += 2
  } else if arg == "--destination", i + 1 < arguments.count {
    destinationArg = arguments[i + 1]
    i += 2
  } else if arg == "--config", i + 1 < arguments.count {
    configArg = arguments[i + 1]
    i += 2
  } else if arg.hasPrefix("--") {
    print("Unknown flag: \(arg)")
    exit(1)
  } else {
    positionalArgs.append(arg)
    i += 1
  }
}

print("Arguments received: \(CommandLine.arguments)")

// MARK: - Path Variables

var xcstringsPath: String = ""
var outputFilePath: String = ""
let projectRoot = FileManager.default.currentDirectoryPath // Assume script runs from project root

// MARK: - Configuration Functions

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

/// Finds the first .xcstrings file in the project root or subdirectories.
func findDefaultSource() -> String? {
  let enumerator = FileManager.default.enumerator(atPath: projectRoot)
  while let file = enumerator?.nextObject() as? String {
    if file.hasSuffix(".xcstrings") {
      print("Found Localized Strings file: \(file)")
      return "\(projectRoot)/\(file)"
    }
  }
  return nil
}

/// Sets up the default destination path.
func setupDefaultDestination() -> String {
  let defaultPath = "\(projectRoot)/Resources/Strings+Generated.swift"
  let resourcesDir = "\(projectRoot)/Resources"
  if !FileManager.default.fileExists(atPath: resourcesDir) {
    do {
      try FileManager.default.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true)
      print("Created Resources directory at: \(resourcesDir)")
    } catch {
      fatalError("Error creating Resources directory: \(error)")
    }
  }
  return defaultPath
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
    guard let defaultSource = findDefaultSource() else {
      fatalError("No .xcstrings file found in project root and no source provided.")
    }
    return defaultSource
  }
}

/// Validates and sets the destination path, ensuring it's within project root.
func validateDestination(_ path: String?, projectRoot: String) -> String {
  let destination = path ?? setupDefaultDestination()
  let absoluteDestination = (destination as NSString).isAbsolutePath ? destination : "\(projectRoot)/\(destination)"
  let outputDirectory = (absoluteDestination as NSString).deletingLastPathComponent

  // Check if destination is within project root
  let projectRootURL = URL(fileURLWithPath: projectRoot).standardized
  let outputDirURL = URL(fileURLWithPath: outputDirectory).standardized
  guard outputDirURL.path.hasPrefix(projectRootURL.path) else {
    fatalError("Destination directory '\(outputDirectory)' is outside project root '\(projectRoot)'.")
  }

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

// MARK: - Main Logic

// Step 1: Handle config
if let configPath = configArg, let (source, destination) = loadConfig(from: configPath, isArg: configArg != nil) {
  xcstringsPath = source
  outputFilePath = destination
} else if let (source, destination) = loadConfig(from: "TypeLocXC.yml") {
  xcstringsPath = source
  outputFilePath = destination
} else if positionalArgs.count == 2 {
  xcstringsPath = positionalArgs[0]
  outputFilePath = positionalArgs[1]
} else {
  // No config or positional args; use defaults later
  xcstringsPath = "" // Will be set by validateSource
  outputFilePath = "" // Will be set by validateDestination
}

// Step 2: Validate and override with source and destination arguments
xcstringsPath = validateSource(sourceArg)
outputFilePath = validateDestination(destinationArg, projectRoot: projectRoot)

print("Using source: \(xcstringsPath)")
print("Using destination: \(outputFilePath)")

// MARK: - String Generation

// Load and parse the .xcstrings file
guard let data = try? Data(contentsOf: URL(fileURLWithPath: xcstringsPath)),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let strings = json["strings"] as? [String: Any] else {
  fatalError("Failed to read or parse .xcstrings file at \(xcstringsPath)")
}

// MARK: MAIN HELPER FUNCTIONS

// Extract format specifiers from a string
func extractSpecifiers(from string: String) -> [String] {
  // Updated regex to match common printf-style specifiers
  let regex = try! NSRegularExpression(pattern: "%[@cdiouxXeEfFgGaAsSpn%]")
  let matches = regex.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
  return matches.map { String(string[Range($0.range, in: string)!]) }
}

// Map specifiers to Swift types
func mapSpecifierToType(_ specifier: String) -> String {
  switch specifier {
  case "%@": return "String"           // Objects (NSString, etc.)
  case "%c": return "Character"       // Single character
  case "%d", "%i": return "Int"       // Signed integers
  case "%o", "%u": return "UInt"      // Unsigned integers
  case "%x", "%X": return "UInt"      // Hexadecimal (treated as unsigned)
  case "%e", "%E", "%f", "%F": return "Double" // Floating-point (Double for precision)
  case "%g", "%G": return "Double"    // General floating-point
  case "%a", "%A": return "Double"    // Hex floating-point
  case "%s": return "String"          // C-style string
  case "%p": return "UnsafeRawPointer" // Pointer (rare in localization)
  case "%%": return ""                // Literal %, no parameter needed
  default:
    print("Warning: Unknown specifier '\(specifier)', defaulting to Any")
    return "Any"                    // Fallback for unrecognized specifiers
  }
}

// Generate labeled parameters (e.g., "p1: Int, p2: String")
func generateParameters(for specifiers: [String]) -> String {
  specifiers.enumerated().map { (index, specifier) in
    let type = mapSpecifierToType(specifier)
    if type.isEmpty { return "" }
    return "p\(index + 1): \(type)"
  }
  .filter { !$0.isEmpty } // Remove empty entries (e.g., for %%)
  .joined(separator: ", ")
}

// Generate arguments for String(format:) (e.g., "p1, p2")
func generateArguments(for specifiers: [String]) -> String {
  specifiers.enumerated()
    .filter { mapSpecifierToType($1) != "" } // Exclude %% (no parameter)
    .map { index, _ in "p\(index + 1)" }
    .joined(separator: ", ")
}

// Generate a function for plural strings
func generatePluralFunction(for key: String, pluralData: [String: Any], output: inout String) {
  let countParam = "count: Int"
  // Assume all plural variations have the same specifiers; use the first category to detect them
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

// MARK: - Output Generation

var output = """
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

// Process each string key
for (key, value) in strings {
  guard let valueDict = value as? [String: Any],
        let localizations = valueDict["localizations"] as? [String: Any],
        let enLocalization = localizations["en"] as? [String: Any] else {
    continue
  }

  let safeKey = key.replacingOccurrences(of: ".", with: "_")

  if let variation = enLocalization["variation"] as? [String: Any],
     let plural = variation["plural"] as? [String: Any] {
    // Handle plural strings
    generatePluralFunction(for: safeKey, pluralData: plural, output: &output)
  } else if let stringUnit = enLocalization["stringUnit"] as? [String: String],
            let stringValue = stringUnit["value"] {
    // Handle simple or formatted strings
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

// Write the output file
do {
  try output.write(toFile: outputFilePath, atomically: true, encoding: .utf8)
  print("✅ Generated \(outputFilePath) successfully!")
} catch {
  fatalError("Failed to write to \(outputFilePath): \(error)")
}

// MARK: - Help Message

func helpMessage() -> String { """
Usage: TypeLocXC [OPTIONS] [SOURCE DESTINATION]

Generate type-safe Swift code from an .xcstrings file.

Options:
  --source <file>        Specify the input .xcstrings file
  --destination <file>   Specify the output Swift file
  --config <file>        Use a custom YAML config file (e.g., config.yml)
  --help, -?             Display this help message

Positional Arguments:
  SOURCE                 Input .xcstrings file (optional if --source is used)
  DESTINATION            Output Swift file (optional if --destination is used)

If no arguments or config are provided, the script searches for a TypeLocXC.yml
in the project root. If absent, it finds the first .xcstrings file and outputs to
Resources/Strings+Generated.swift, creating the Resources directory if needed.

Examples:
  TypeLocXC Strings.xcstrings Output/Strings.swift
  TypeLocXC --source Custom.xcstrings --destination Generated.swift
  TypeLocXC --config myconfig.yml
  TypeLocXC --help
"""
}
