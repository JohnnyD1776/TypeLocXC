//
//  CodeGenerator.swift
//  TypeLocXC
//
//  Created by John Durcan on 06/03/2025.
//

import Foundation

// MARK: - Generation Function
struct CodeGenerator {

  /// Create the Type Safe swift File Output
  static func generateOutput(from xcstringsPath: String, to outputFilePath: String) {
    guard let checksum = FileHandler.computeSHA256(of: xcstringsPath) else {
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
        // Auto-generated file for type-safe access to .xcstrings. Do not edit manually.
        import Foundation
        
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
        /// // Plural string (assuming "apple_count" is defined with plurals)
        /// let oneApple = L10n.apple_count(count: 1)     // "1 apple"
        /// let manyApples = L10n.apple_count(count: 5)   // "5 apples"
        /// ```
        ///
        /// Supported format specifiers:
        /// - `%@`: `String`
        /// - `%c`: `Character`
        /// - `%d`, `%i`: `Int`
        /// - `%o`, `%u`, `%x`, `%X`: `UInt`
        /// - `%e`, `%E`, `%f`, `%F`, `%g`, `%G`, `%a`, `%A`: `Double`
        /// - `%s`: `String`
        /// - `%p`: `UnsafeRawPointer`
        /// - `%%`: No argument (literal percent sign)
        ///
        /// Note: For any unsupported specifiers, the type defaults to `Any`, and a warning is printed.
        
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

  private static func extractSpecifiers(from string: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: "%[@cdiouxXeEfFgGaAsSpn%]")
    let matches = regex.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
    return matches.map { String(string[Range($0.range, in: string)!]) }
  }

  private static func mapSpecifierToType(_ specifier: String) -> String {
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

  private static func generateParameters(for specifiers: [String]) -> String {
    specifiers.enumerated().map { (index, specifier) in
      let type = mapSpecifierToType(specifier)
      if type.isEmpty { return "" }
      return "p\(index + 1): \(type)"
    }
    .filter { !$0.isEmpty }
    .joined(separator: ", ")
  }

  private static func generateArguments(for specifiers: [String]) -> String {
    specifiers.enumerated()
      .filter { mapSpecifierToType($1) != "" }
      .map { index, _ in "p\(index + 1)" }
      .joined(separator: ", ")
  }

  private static func generatePluralFunction(for key: String, pluralData: [String: Any], output: inout String) {
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
}
